"""
Tick 驱动的自动战斗引擎。

一场战斗默认 200 Tick。每 Tick 各单位行动条按速度累加,达 100 出手。
同 Tick 多人达 100:防守方优先、前排优先。
200 Tick 走完不判胜负:防守方留守,进攻方回出发结点。
一方全灭则另一方占据该结点。

战斗前通过统一修正管道收集所有修正(月相/昼夜/词条/羁绊/信念/技能/装备/地形/标志建筑 buff),
计算各单位的有效属性,再进入 Tick 循环。
"""
from __future__ import annotations
import random
from dataclasses import dataclass, field
from typing import Any

from .army import Army, row_of, col_of, ROWS, ROW_CN, GRID_SIZE
from .unit import Unit, ATTR_BOUNDS
from .modifier import Modifier, ModifierCollection, compute_attribute, ModifierSource
from .formation import UnitStrategy, choose_target_with_slots
from .effects import Effect

BATTLE_TICKS = 200
ATB_THRESHOLD = 100.0
# 行动条累加速率:spd / ATB_RATE per tick。speed 75 -> +2.5/tick,
# 约 40 tick 出手一次,200 tick 内约 5 次出手,使战斗可在限定 tick 内分出胜负。
ATB_RATE = 30.0


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


def run_battle(
    attacker: BattleSide,
    defender: BattleSide,
    strategies: dict[str, UnitStrategy],   # unit_id -> strategy
    extra_mods: list[Modifier],
    log_detail: bool = True,
) -> BattleResult:
    """
    执行一场战斗。返回 BattleResult。
    strategies 含双方所有单位的策略。
    """
    result = BattleResult()
    all_units = attacker.units + defender.units

    # 计算每个单位的有效属性
    eff_map: dict[str, dict[str, float]] = {}
    for u in all_units:
        umods = [m for m in extra_mods if m.target == u.id]
        eff_map[u.id] = effective_attrs(u, umods)

    # 初始化战斗内状态
    for u in all_units:
        u.cur_ap = eff_map[u.id].get("ap", 0)
        u.cur_mana = eff_map[u.id].get("mana", 0)
        u.atb = 0.0
        u.alive = True
        u.cur_hp = eff_map[u.id].get("hp", u.cur_hp)

    # 构造槽位映射(unit -> slot)
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

    tick = 0
    while tick < BATTLE_TICKS:
        # 累加行动条
        for u in all_units:
            if u.alive:
                spd = eff_map[u.id].get("speed", 1)
                u.atb += spd / ATB_RATE  # speed 75 -> +2.5/tick,约 40 tick 出手
        # 找出达 100 的单位
        ready = [u for u in all_units if u.alive and u.atb >= ATB_THRESHOLD]
        if not ready:
            tick += 1
            continue
        # 排序:防守方优先、前排优先(按部队与槽位)
        def order_key(u: Unit) -> tuple:
            in_att = u in attacker.units
            side_rank = 1 if in_att else 0   # 防守方(0)优先
            slot = attacker.army.slot_of(u.id) if in_att else defender.army.slot_of(u.id)
            row = row_of(slot) if slot is not None else "back"
            row_rank = {"front": 0, "mid": 1, "back": 2}.get(row, 3)
            return (side_rank, row_rank, -u.atb)
        ready.sort(key=order_key)
        # 行动
        for u in ready:
            if not u.alive:
                continue
            u.atb -= ATB_THRESHOLD
            in_att = u in attacker.units
            my_side = attacker if in_att else defender
            foe_side = defender if in_att else attacker
            foes = side_slots(foe_side)
            strat = strategies.get(u.id)
            if strat is None:
                continue
            my_slot = my_side.army.slot_of(u.id)
            target = choose_target_with_slots(my_slot if my_slot is not None else 0,
                                               u.tags, foes, strat)
            if target is None:
                if log_detail:
                    result.log.append(f"[T{tick}] {u.name} 无可打目标")
                continue
            t_slot, t_unit = target
            # 伤害计算(简化:物攻 vs 物防 / 魔攻 vs 魔防,取主攻属性)
            ueff = eff_map[u.id]
            teff = eff_map[t_unit.id]
            is_magic = "magic" in u.tags and ueff.get("m_atk", 0) > ueff.get("p_atk", 0)
            if is_magic:
                dmg = max(1, ueff.get("m_atk", 0) - teff.get("m_def", 0))
                kind = "魔攻"
            else:
                dmg = max(1, ueff.get("p_atk", 0) - teff.get("p_def", 0))
                kind = "物攻"
            # 暴击/命中简化
            crit = random.random() < (ueff.get("crit", 0) / 100.0)
            if crit:
                dmg = int(dmg * 1.5)
            t_unit.cur_hp -= dmg
            if log_detail:
                result.log.append(f"[T{tick}] {u.name} {kind}→{t_unit.name} 伤害{dmg}"
                                  + ("(暴击)" if crit else "")
                                  + f" 余{max(0, int(t_unit.cur_hp))}")
            if t_unit.cur_hp <= 0:
                t_unit.alive = False
                t_unit.cur_hp = 0
                if log_detail:
                    result.log.append(f"  {t_unit.name} 阵亡")
        tick += 1
        # 全灭检查
        if not side_alive(attacker):
            result.attacker_wiped = True
            break
        if not side_alive(defender):
            result.defender_wiped = True
            break

    # 结局
    if result.defender_wiped and not result.attacker_wiped:
        result.occupier_side = "attacker"
    elif result.attacker_wiped and not result.defender_wiped:
        result.occupier_side = "defender"
    else:
        result.occupier_side = None  # 走完 200 tick 未分胜负
    return result
