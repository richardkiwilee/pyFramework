"""
Tick 驱动的自动战斗引擎。

一场战斗默认 200 Tick。每 Tick 各单位行动条按速度累加,达 100 出手。
同 Tick 多人达 100:防守方优先、前排优先。
200 Tick 走完不判胜负:防守方留守,进攻方回出发结点。
一方全灭则另一方占据该结点。

战斗前通过统一修正管道收集所有修正(月相/昼夜/词条/羁绊/信念/技能/装备/地形/标志建筑 buff),
计算各单位的有效属性,再进入 Tick 循环。

批次2(ADR-0008/0010/0011)接通:
  - A1 主动技能执行:行动段按策略表主动区行序检测,首个可释放(active 效果 AP/Mana
    足 + 无目标型必要条件满足)的主动技能释放(ap_damage 走统一命中/格挡/暴击管道),
    扣 AP/Mana;都不满足则普通攻击。
  - A2 被动时点调度:10 个触发时点在循环中接入;每个时点按当前速度降序、单位内按
    被动行序检测;每时点最多 1 个单位响应(按时点各自计);判定满足即扣 PP(响应前)。
  - A3 策略表条件:8 槽两区,必要(筛合法目标/释放门槛)+ 优先(软排)两型,见 formation.py。
  - A4 状态系统:消费模型(无 tick 计时),ON_SELF_ATTACK/ON_SELF_HIT/BATTLE_LONG
    三类消费;冻结轮到自身行动跳过出手并扣层;battle_end 清场;状态作为条件输入。

RNG 注入:run_battle 接 rng 参数(注入 random.Random,脱离全局 random.seed,便于测试)。
"""
from __future__ import annotations
import math
import random
from dataclasses import dataclass, field
from typing import Any

from .army import Army, row_of, col_of, ROWS, ROW_CN, GRID_SIZE
from .unit import Unit, ATTR_BOUNDS
from .modifier import Modifier, ModifierCollection, compute_attribute, ModifierSource
from .formation import UnitStrategy, choose_target_with_slots
from .effects import (
    Effect, build_skill_effects, skill_kind, SKILL_ACTIVE, SKILL_PASSIVE,
    execute_active_effect, execute_passive_effect, active_cost, passive_pp_cost,
)
from .triggers import (
    TriggerPoint, StatusType, StatusConsume, STATUS_META,
    is_frozen, consume_on_self_attack, consume_on_self_hit, clear_statuses,
    has_status, eval_necessary, is_necessary,
)

BATTLE_TICKS = 200
ATB_THRESHOLD = 100.0
# 行动条累加速率:spd / ATB_RATE per tick。speed 75 -> +2.5/tick,
# 约 40 tick 出手一次,200 tick 内约 5 次出手,使战斗可在限定 tick 内分出胜负。
ATB_RATE = 30.0

# 格挡/闪避掷骰开关(批次2)。False 时恒命中、无格挡/闪避,on_block/on_eva 不触发。
# 若 smoke_test 胜负翻转,先动此开关或 BLOCK_DMG_FACTOR 调参,不改代码。
BLOCK_EVA_ENABLED = True
BLOCK_DMG_FACTOR = 0.5   # 格挡成功时的伤害减免系数


@dataclass
class BattleSide:
    army: Army
    is_attacker: bool
    home_node: str | None = None   # 进攻方出发结点(用于失败后退回)
    units: list[Unit] = field(default_factory=list)


@dataclass
class BattleResult:
    attacker_wiped: bool = False
    defender_wiped: bool = False
    log: list[str] = field(default_factory=list)
    # 结局:谁占据结点(None 表示无变化,进攻方退回)
    occupier_side: str | None = None   # 'attacker' | 'defender' | None
    # 本场阵亡单位 id 列表(用于结算死亡经验)
    casualties: list[str] = field(default_factory=list)


@dataclass
class StrikeResult:
    """一次攻击(普通或 ap_damage)的结算结果。"""
    hit: bool = True      # 是否命中(非闪避)
    blocked: bool = False
    evaded: bool = False
    crit: bool = False
    dmg: int = 0
    kind: str = ""        # "physical" | "magic"


@dataclass
class BattleContext:
    """承载战斗循环跨切状态,避免调度函数 8 参签名(批次2)。"""
    attacker_side: BattleSide
    defender_side: BattleSide
    strategies: dict[str, UnitStrategy]
    eff_map: dict[str, dict[str, float]]
    skill_defs: dict[str, dict]
    result: BattleResult
    log_detail: bool
    rng: random.Random
    block_eva_enabled: bool = BLOCK_EVA_ENABLED
    # 本轮攻击已触发的时点集合(按时点各自计,防同一时点重复触发,ADR-0011)
    trigger_fired_this_attack: set = field(default_factory=set)


def collect_all_mods(
    attacker: BattleSide,
    defender: BattleSide,
    all_units: list[Unit],
    extra_mods: list[Modifier],
) -> list[Modifier]:
    """合并外部预收集的修正(词条/羁绊/技能/装备/月相/昼夜等)。原型直接接收 extra_mods。"""
    return list(extra_mods)


def effective_attrs(unit: Unit, mods: list[Modifier]) -> dict[str, float]:
    """计算单位的有效属性(基础 + 修正管道)。"""
    eff: dict[str, float] = {}
    for attr in unit.base:
        lo, hi = ATTR_BOUNDS.get(attr, (0, 99999))
        eff[attr] = compute_attribute(unit.base.get(attr, 0), mods, attr, lo, hi)
    # 额外属性(如 mana_regen)
    eff.setdefault("mana_regen", 0)
    lo, hi = ATTR_BOUNDS.get("mana_regen", (0, 999))
    eff["mana_regen"] = compute_attribute(0, mods, "mana_regen", lo, hi)
    return eff


# ---------------------------------------------------------------------------
# 命中/格挡/闪避/暴击统一管道(A1 普通攻击与 ap_damage 共用,单一来源)
# ---------------------------------------------------------------------------

def resolve_strike(ctx: BattleContext, attacker: Unit, target: Unit,
                   kind: str, flat_dmg: int | None = None) -> StrikeResult:
    """结算一次攻击。

    kind: "physical" | "magic"(决定取攻防属性)。
    flat_dmg: None=用攻击者 atk − 目标 def 算基础伤害;非 None=用此值作基础伤害
        (ap_damage 走此分支,使主动技能伤害仍走命中/格挡/暴击管道)。

    在此函数内按序触发 4 个受击相关时点:on_block / on_eva / after_phys /
    after_magic。ally_attacked_start/end 由调用方在 strike 前后发(集中受击顺序)。
    """
    ueff = ctx.eff_map.get(attacker.id, {})
    teff = ctx.eff_map.get(target.id, {})
    res = StrikeResult(kind=kind)
    # 闪避/格挡掷骰
    if ctx.block_eva_enabled:
        # 命中:acc vs 0(简化,未与目标 eva 对抗判定命中,先命中再单独闪避)
        # 这里采用:命中恒成立(攻击已发起即视为命中意图),再判闪避/格挡
        # 闪避:eva/100
        if ctx.rng.random() < (teff.get("eva", 0) / 100.0):
            res.evaded = True
            res.hit = False
            res.dmg = 0
            dispatch_trigger(ctx, TriggerPoint.ON_EVA, actor=attacker, target=target)
            return res
        # 格挡:block/100
        if ctx.rng.random() < (teff.get("block", 0) / 100.0):
            res.blocked = True
    # 基础伤害
    if flat_dmg is None:
        if kind == "magic":
            base = ueff.get("m_atk", 0) - teff.get("m_def", 0)
        else:
            base = ueff.get("p_atk", 0) - teff.get("p_def", 0)
        dmg = max(1, int(math.floor(base)))
    else:
        dmg = max(1, int(flat_dmg))
    if res.blocked:
        dmg = int(math.floor(dmg * BLOCK_DMG_FACTOR))
    # 暴击
    if ctx.rng.random() < (ueff.get("crit", 0) / 100.0):
        res.crit = True
        dmg = int(math.floor(dmg * 1.5))
    res.dmg = max(0, dmg) if res.evaded else max(1, dmg)
    target.cur_hp -= res.dmg
    # 命中分支:受击消耗(冻结受击破冰,ADR-0010)
    consume_on_self_hit(target)
    # 格挡时点
    if res.blocked:
        dispatch_trigger(ctx, TriggerPoint.ON_BLOCK, actor=attacker, target=target)
    # after_phys / after_magic
    tp = TriggerPoint.AFTER_PHYS if kind == "physical" else TriggerPoint.AFTER_MAGIC
    dispatch_trigger(ctx, tp, actor=attacker, target=target, dmg=res.dmg, kind=kind)
    return res


# ---------------------------------------------------------------------------
# 主动技能可释放判定(A1)
# ---------------------------------------------------------------------------

def _can_fire_active(ctx: BattleContext, u: Unit, row) -> Effect | None:
    """查 row.skill_id 的 active 效果,校验 AP/Mana 够 + 无目标型必要条件满足。

    返回可执行的 Effect(首个 trigger==active 的 ap_damage/apply_status),或 None。
    目标型必要条件(target_pref_*/enemy_has_frozen)不在此查,交给 choose_target 过滤。
    """
    if ctx.skill_defs is None:
        return None
    sd = ctx.skill_defs.get(row.skill_id)
    if sd is None or skill_kind(sd) != SKILL_ACTIVE:
        return None
    effs = build_skill_effects(sd)
    # 该技能所有 active 效果的总成本
    total_ap = sum(e.ap_cost for e in effs if e.trigger == "active")
    total_mana = sum(e.mana_cost for e in effs if e.trigger == "active")
    if u.cur_ap < total_ap or u.cur_mana < total_mana:
        return None
    # 无目标型必要条件 gate 释放(self_hp_le/ally_avg_hp_le/row_count_ge)
    for cond in (row.necessary or []):
        t = cond.get("type")
        if t in ("self_hp_le", "ally_avg_hp_le", "row_count_ge"):
            if not eval_necessary(cond, ctx, u, target=None, eff_map=ctx.eff_map):
                return None
    # 返回首个 active 效果(简化:一个主动技能一次行动;多 effect 时由调用方逐 effect 执行)
    for e in effs:
        if e.trigger == "active" and e.effect_type in ("ap_damage", "apply_status"):
            return e
    return None


# ---------------------------------------------------------------------------
# 被动时点调度(A2)
# ---------------------------------------------------------------------------

def _unit_side(ctx: BattleContext, u: Unit) -> BattleSide:
    if u in ctx.attacker_side.units:
        return ctx.attacker_side
    return ctx.defender_side


def _passive_candidates(ctx: BattleContext, tp: TriggerPoint, actor: Unit | None,
                        target: Unit | None) -> list[Unit]:
    """该时点的候选响应单位(按当前速度降序)。

    ally_attacked_*:只看 target 同侧(排除 target 自身)。
    self_attack_*:只看 actor。
    其余(battle_start/end、on_block/eva、after_*):看双方所有存活。
    """
    all_units = ctx.attacker_side.units + ctx.defender_side.units
    alive = [u for u in all_units if u.alive]
    if tp in (TriggerPoint.ALLY_ATTACKED_START, TriggerPoint.ALLY_ATTACKED_END):
        if target is None:
            return []
        side = _unit_side(ctx, target)
        cand = [u for u in side.units if u.alive and u.id != target.id]
    elif tp in (TriggerPoint.SELF_ATTACK_START, TriggerPoint.SELF_ATTACK_END):
        if actor is None:
            return []
        cand = [actor] if actor.alive else []
    else:
        cand = alive
    # 只保留有匹配 trigger_point 的被动行的单位
    cands = []
    for u in cand:
        strat = ctx.strategies.get(u.id)
        if strat is None:
            continue
        for prow in strat.passive_rows:
            if prow.trigger_point == tp:
                cands.append(u)
                break
    # 按当前速度降序(每次现排,速度可被临时改,ADR-0011)
    cands.sort(key=lambda u: -ctx.eff_map.get(u.id, {}).get("speed", 1))
    return cands


def dispatch_trigger(ctx: BattleContext, tp: TriggerPoint,
                      actor: Unit | None = None, target: Unit | None = None,
                      dmg: int = 0, kind: str = "",
                      blocked: bool = False, evaded: bool = False) -> None:
    """被动时点调度(ADR-0011)。

    每个时点按时点各自计:最多 1 个单位响应。速度降序、单位内按被动行序检测;
    满足必要条件 + PP 足 → 判定满足即扣 PP(响应前)→ 执行 → 结束该时点。
    PP 不足视为不满足,继续下行/下一单位,不扣 PP。
    """
    # 防同一时点重复触发(本轮攻击内)
    if tp in ctx.trigger_fired_this_attack:
        return
    ctx.trigger_fired_this_attack.add(tp)

    cands = _passive_candidates(ctx, tp, actor, target)
    for u in cands:
        if not u.alive:
            continue
        strat = ctx.strategies.get(u.id)
        if strat is None:
            continue
        for prow in strat.passive_rows:
            if prow.trigger_point != tp:
                continue
            # 查该被动技能的效果(取 trigger==passive 的 effect)
            if ctx.skill_defs is None:
                break
            sd = ctx.skill_defs.get(prow.skill_id)
            if sd is None or skill_kind(sd) != SKILL_PASSIVE:
                continue
            effs = build_skill_effects(sd)
            # 必要条件 gate(本时点上下文)
            ok = True
            for cond in (prow.necessary or []):
                if not eval_necessary(cond, ctx, u, target=target, eff_map=ctx.eff_map):
                    ok = False
                    break
            if not ok:
                continue
            # PP 成本(取该技能 passive 效果总 pp_cost)
            total_pp = sum(e.pp_cost for e in effs if e.trigger == "passive")
            if u.cur_pp < total_pp:
                continue   # PP 不足视为不满足,不扣 PP,继续
            # 判定满足即扣 PP(响应前)
            u.cur_pp -= total_pp
            # 执行被动效果(apply_status 对 target;ap_damage 追击对 target)
            eff = None
            for e in effs:
                if e.trigger == "passive" and e.effect_type in ("ap_damage", "apply_status"):
                    eff = e
                    break
            if eff is not None:
                # 被动响应的 target:有 target 用 target,否则 actor(如 battle_start 无 target)
                resp_target = target if target is not None and target.alive else actor
                if resp_target is not None and resp_target.alive:
                    r = execute_passive_effect(eff, ctx, u, resp_target)
                    if ctx.log_detail:
                        ctx.result.log.append(
                            f"  [被动 {tp.value}] {u.name} 响应({prow.skill_id})"
                            + (f" 伤害{r['dmg']}" if r["dmg"] else "")
                            + (f" 施加{','.join(r['status_applied'])}" if r["status_applied"] else ""))
                    # 死亡检查(被动追击可能致死)
                    if resp_target.cur_hp <= 0 and resp_target.alive:
                        resp_target.alive = False
                        resp_target.cur_hp = 0
                        if resp_target.id not in ctx.result.casualties:
                            ctx.result.casualties.append(resp_target.id)
            # 结束该时点(按时点各自计,本时点最多 1 响应)
            return


# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------

def run_battle(
    attacker: BattleSide,
    defender: BattleSide,
    strategies: dict[str, UnitStrategy],   # unit_id -> strategy
    extra_mods: list[Modifier],
    log_detail: bool = True,
    rng: random.Random | None = None,
    skill_defs: dict[str, dict] | None = None,
) -> BattleResult:
    """执行一场战斗,返回 BattleResult。strategies 含双方所有单位的策略。

    rng:注入随机数(脱离全局 random.seed,便于测试定种子);None 用 random.Random()。
    skill_defs:技能定义(A1/A2 调度需要);None 时主动/被动不触发(退化旧行为,
    主动区为空则只普通攻击)。
    """
    result = BattleResult()
    all_units = attacker.units + defender.units
    if rng is None:
        rng = random.Random()

    # 计算每个单位的有效属性
    eff_map: dict[str, dict[str, float]] = {}
    for u in all_units:
        umods = [m for m in extra_mods if m.target == u.id]
        eff_map[u.id] = effective_attrs(u, umods)

    # 初始化战斗内状态
    for u in all_units:
        u.cur_ap = eff_map[u.id].get("ap", 0)
        u.cur_pp = eff_map[u.id].get("pp", 0)
        # Mana 跨场累积不回满:进场只 clamp 到当前有效上限(ADR-0008)。
        mana_cap = eff_map[u.id].get("mana", 0)
        u.cur_mana = mana_cap if u.cur_mana <= 0 else min(u.cur_mana, mana_cap)
        u.atb = 0.0
        u.alive = True
        # HP 跨战斗累积(不每场回满):保留进场 cur_hp,仅 clamp 到当前有效上限。
        eff_hp = eff_map[u.id].get("hp", u.base.get("hp", 1))
        u.cur_hp = eff_hp if u.cur_hp <= 0 else min(u.cur_hp, eff_hp)
        # 状态不跨场:进场清空(ADR-0010)
        clear_statuses(u)

    ctx = BattleContext(
        attacker_side=attacker, defender_side=defender,
        strategies=strategies, eff_map=eff_map, skill_defs=skill_defs or {},
        result=result, log_detail=log_detail, rng=rng,
        block_eva_enabled=BLOCK_EVA_ENABLED,
    )
    # 把 resolve_strike 挂到 ctx,供 effects.py 的 execute_active/passive_effect
    # 通过 ctx.resolve_strike(ctx, ...) 调用(避免 effects.py 顶层 import battle.py
    # 造成循环依赖;resolve_strike 签名首参即 ctx,显式传 ctx 与此契合)。
    ctx.resolve_strike = resolve_strike  # type: ignore[attr-defined]

    def side_slots(side: BattleSide) -> list[tuple[int, Unit]]:
        slots = []
        for i, uid in enumerate(side.army.grid):
            if uid is not None:
                u = next((x for x in side.units if x.id == uid), None)
                if u and u.alive:
                    slots.append((i, u))
        return slots

    def side_alive(side: BattleSide) -> list[Unit]:
        return [u for u in side.units if u.alive]

    # battle_start 一次性
    dispatch_trigger(ctx, TriggerPoint.BATTLE_START)

    tick = 0
    while tick < BATTLE_TICKS:
        # 累加行动条
        for u in all_units:
            if u.alive:
                spd = eff_map[u.id].get("speed", 1)
                u.atb += spd / ATB_RATE
        ready = [u for u in all_units if u.alive and u.atb >= ATB_THRESHOLD]
        if not ready:
            tick += 1
            continue
        ready.sort(key=_order_key_factory(attacker, defender))

        for u in ready:
            if not u.alive:
                continue
            u.atb -= ATB_THRESHOLD
            # A4 冻结跳过(轮到自身行动时消耗)
            if is_frozen(u):
                if log_detail:
                    result.log.append(f"[T{tick}] {u.name} 冰封,无法行动")
                consume_on_self_attack(u)
                continue
            in_att = u in attacker.units
            my_side = attacker if in_att else defender
            foe_side = defender if in_att else attacker
            foes = side_slots(foe_side)
            strat = strategies.get(u.id)
            if strat is None:
                continue
            my_slot = my_side.army.slot_of(u.id)
            ctx.trigger_fired_this_attack.clear()

            # A1 主动区按行序检测
            fired = False
            for row in strat.active_rows:
                eff = _can_fire_active(ctx, u, row)
                if eff is None:
                    continue
                target = choose_target_with_slots(
                    my_slot if my_slot is not None else 0, u.tags, foes, strat,
                    rng=ctx.rng, necessary=row.necessary, priority=row.priority,
                    eff_map=eff_map, ctx=ctx, attacker=u)
                if target is None:
                    continue
                t_slot, t_unit = target
                # self_attack_start(选目标后、strike 前)
                dispatch_trigger(ctx, TriggerPoint.SELF_ATTACK_START, actor=u, target=t_unit)
                dispatch_trigger(ctx, TriggerPoint.ALLY_ATTACKED_START, actor=u, target=t_unit)
                # 执行主动效果:ap_damage 走 resolve_strike;apply_status 施加
                sd = (skill_defs or {}).get(row.skill_id, {})
                sum_dmg = 0
                sum_kind = ""
                sum_status: list[str] = []
                for e in build_skill_effects(sd):
                    if e.trigger != "active":
                        continue
                    if e.effect_type in ("ap_damage", "apply_status"):
                        r = execute_active_effect(e, ctx, u, t_unit)
                        sum_dmg += r.get("dmg", 0)
                        if r.get("kind"):
                            sum_kind = r["kind"]
                        sum_status.extend(r.get("status_applied", []))
                # 扣 AP/Mana(总成本)
                total_ap = sum(e.ap_cost for e in build_skill_effects(sd) if e.trigger == "active")
                total_mana = sum(e.mana_cost for e in build_skill_effects(sd) if e.trigger == "active")
                u.cur_ap -= total_ap
                u.cur_mana -= total_mana
                if log_detail:
                    result.log.append(f"[T{tick}] {u.name} 释放 {row.skill_id}→{t_unit.name}"
                                      + (f" 伤害{sum_dmg}({sum_kind})" if sum_dmg else "")
                                      + (f" 施加{','.join(sum_status)}" if sum_status else "")
                                      + f" 余{max(0, int(t_unit.cur_hp))}")
                if t_unit.cur_hp <= 0 and t_unit.alive:
                    t_unit.alive = False
                    t_unit.cur_hp = 0
                    if t_unit.id not in result.casualties:
                        result.casualties.append(t_unit.id)
                    if log_detail:
                        result.log.append(f"  {t_unit.name} 阵亡")
                dispatch_trigger(ctx, TriggerPoint.ALLY_ATTACKED_END, actor=u, target=t_unit, dmg=sum_dmg)
                dispatch_trigger(ctx, TriggerPoint.SELF_ATTACK_END, actor=u, target=t_unit, dmg=sum_dmg, kind=sum_kind)
                # 自身攻击消耗层状态 -1
                consume_on_self_attack(u)
                fired = True
                break   # 首个可释放主动即出手,本次行动结束

            if not fired:
                # 普通攻击(走 resolve_strike)
                target = choose_target_with_slots(
                    my_slot if my_slot is not None else 0, u.tags, foes, strat,
                    rng=ctx.rng, eff_map=eff_map, ctx=ctx, attacker=u)
                if target is None:
                    if log_detail:
                        result.log.append(f"[T{tick}] {u.name} 无可打目标")
                    consume_on_self_attack(u)
                    continue
                t_slot, t_unit = target
                ueff = eff_map[u.id]
                is_magic = "magic" in u.tags and ueff.get("m_atk", 0) > ueff.get("p_atk", 0)
                kind = "magic" if is_magic else "physical"
                dispatch_trigger(ctx, TriggerPoint.SELF_ATTACK_START, actor=u, target=t_unit)
                dispatch_trigger(ctx, TriggerPoint.ALLY_ATTACKED_START, actor=u, target=t_unit)
                sres = resolve_strike(ctx, u, t_unit, kind)
                kind_cn = "魔攻" if is_magic else "物攻"
                if log_detail:
                    if sres.evaded:
                        result.log.append(f"[T{tick}] {u.name} {kind_cn}→{t_unit.name} 闪避 余{max(0, int(t_unit.cur_hp))}")
                    else:
                        result.log.append(f"[T{tick}] {u.name} {kind_cn}→{t_unit.name} 伤害{sres.dmg}"
                                          + ("(格挡)" if sres.blocked else "")
                                          + ("(暴击)" if sres.crit else "")
                                          + f" 余{max(0, int(t_unit.cur_hp))}")
                if t_unit.cur_hp <= 0 and t_unit.alive:
                    t_unit.alive = False
                    t_unit.cur_hp = 0
                    if t_unit.id not in result.casualties:
                        result.casualties.append(t_unit.id)
                    if log_detail:
                        result.log.append(f"  {t_unit.name} 阵亡(Lv{getattr(t_unit, 'level', 1)})")
                dispatch_trigger(ctx, TriggerPoint.ALLY_ATTACKED_END, actor=u, target=t_unit, dmg=sres.dmg)
                dispatch_trigger(ctx, TriggerPoint.SELF_ATTACK_END, actor=u, target=t_unit, dmg=sres.dmg, kind=kind)
                consume_on_self_attack(u)

            tick += 1
            if not side_alive(attacker):
                result.attacker_wiped = True
                break
            if not side_alive(defender):
                result.defender_wiped = True
                break

    # battle_end 一次性 + 状态清场(状态不跨场,ADR-0010)
    dispatch_trigger(ctx, TriggerPoint.BATTLE_END)
    for u in all_units:
        clear_statuses(u)

    # 结局
    if result.defender_wiped and not result.attacker_wiped:
        result.occupier_side = "attacker"
    elif result.attacker_wiped and not result.defender_wiped:
        result.occupier_side = "defender"
    else:
        result.occupier_side = None  # 走完 200 tick 未分胜负
    return result


def _order_key_factory(attacker: BattleSide, defender: BattleSide):
    def order_key(u: Unit) -> tuple:
        in_att = u in attacker.units
        side_rank = 1 if in_att else 0   # 防守方(0)优先
        slot = attacker.army.slot_of(u.id) if in_att else defender.army.slot_of(u.id)
        row = row_of(slot) if slot is not None else "back"
        row_rank = {"front": 0, "mid": 1, "back": 2}.get(row, 3)
        return (side_rank, row_rank, -u.atb)
    return order_key

