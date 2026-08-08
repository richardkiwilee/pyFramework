"""
数据驱动的技能/被动效果解释器。

技能/被动 = 数据描述(效果类型 + 参数)+ 统一解释器。新增具体技能只改数据文件;
只有引入新的效果类型才改代码。详见 ADR-0001。

效果类型(原子效果,原型 5+ 示例覆盖):
  - flat_attr:     flat 加某属性(如 +10 物攻)。params: attr, value
  - pct_attr:      百分比加某属性(如 +10% 物攻)。params: attr, value
  - tag_bonus:     拥有某词条时加 flat 属性(兵种加成)。params: tag, attr, value, op
  - moon_regen:    按月相给魔力恢复加成(月相修正示例)。params: scale
  - aura_flat:     队长光环:全队某属性 flat 加成。params: attr, value
  - tag_grant:     装备/技能使单位获得某词条(装备附带 Synergy 来源)。params: tag
  - skill_grant:   装备使单位获得某技能(装上时加入 granted_skills,卸下时移除)。
                   params: skill(技能 id)。ADR-0008。

技能按 kind 三分类(ADR-0008):active(主动,耗 AP)、passive(被动,耗 PP,在触发
时点检测)、perk(免费常驻修正,走修正管道,不占策略表 8 槽)。主动效果的类型集与
被动相同的接口,但触发时机不同;原型主动技能用 'ap_damage' 等。
perk 与事件源 Perk 都走修正管道,但二者来源不同、互不混用槽位。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

from .modifier import Modifier, ModifierSource

# 技能 kind 三值(ADR-0008)
SKILL_ACTIVE = "active"
SKILL_PASSIVE = "passive"
SKILL_PERK = "perk"
SKILL_KINDS = (SKILL_ACTIVE, SKILL_PASSIVE, SKILL_PERK)


@dataclass
class Effect:
    """数据描述的一条效果。"""
    effect_type: str          # 见上表
    params: dict[str, Any]    # 参数
    trigger: str = "passive"  # passive | active
    ap_cost: int = 0          # 主动效果消耗 AP
    pp_cost: int = 0          # 被动效果消耗 PP(ADR-0008)
    mana_cost: int = 0        # 主动效果消耗 魔力点(部分主动/被动技能同时要求 AP/PP 与 Mana)
    condition: Any = None
    # 被动效果的触发时点(ADR-0011):放 effect dict,多 effect 被动可各发各时点。
    # 主动效果此字段为 None。值见 triggers.TriggerPoint。
    trigger_point: Any = None


def build_skill_effects(skill_def: dict) -> list[Effect]:
    """从技能数据定义构造 Effect 列表。"""
    effects: list[Effect] = []
    for e in skill_def.get("effects", []):
        effects.append(Effect(
            effect_type=e["type"],
            params=e.get("params", {}),
            trigger=e.get("trigger", "passive"),
            ap_cost=e.get("ap_cost", 0),
            pp_cost=e.get("pp_cost", 0),
            mana_cost=e.get("mana_cost", 0),
            condition=e.get("condition"),
            trigger_point=e.get("trigger_point"),
        ))
    return effects


def skill_kind(skill_def: dict | None) -> str:
    """取技能定义的 kind,缺省归为 perk(向后兼容旧无 kind 字段的被动修正技能)。"""
    if not skill_def:
        return SKILL_PERK
    return skill_def.get("kind", SKILL_PERK)


def collect_passive_modifiers(
    effects: list[Effect],
    owner_id: str,
    owner_tags: set[str],
    army_tags_count: dict[str, int],
    source: ModifierSource,
    source_id: str,
) -> list[Modifier]:
    """
    把一组被动效果展开为修正。主动效果在此不展开(由战斗策略在战斗内调用)。
    返回作用于 owner_id 的修正列表。

    owner_tags:        拥有者自身词条集合(用于 tag_bonus 条件)
    army_tags_count:   所在部队中各词条的数量(用于 aura 范围判断,原型简化)
    """
    mods: list[Modifier] = []
    for eff in effects:
        if eff.trigger != "passive":
            continue
        p = eff.params
        et = eff.effect_type
        if et == "flat_attr":
            mods.append(Modifier(source, source_id, owner_id, p["attr"],
                                 float(p["value"]), op="flat"))
        elif et == "pct_attr":
            mods.append(Modifier(source, source_id, owner_id, p["attr"],
                                 float(p["value"]), op="pct"))
        elif et == "tag_bonus":
            # 只有拥有该词条时才生效
            if p["tag"] in owner_tags:
                mods.append(Modifier(source, source_id, owner_id, p["attr"],
                                     float(p["value"]), op=p.get("op", "flat")))
        elif et == "moon_regen":
            # 月相修正:以 base=0 + scale*当前月相恢复 作为 flat 加成,
            # 这里登记一条标记修正,实际数值在收集时由 calendar 填入。
            # 为简化,我们登记为 flat 且 value=0,留 condition 标记供系统替换。
            mods.append(Modifier(source, source_id, owner_id, "mana_regen",
                                 float(p["scale"]), op="pct"))
        elif et == "aura_flat":
            # 光环:作用于部队所有单位(此处简化为仅登记 owner;部队级收集时再分发)
            mods.append(Modifier(source, source_id, owner_id, p["attr"],
                                 float(p["value"]), op="flat"))
        # tag_grant 不产生修正,它改变单位词条集合,在 unit 构造时处理
        # skill_grant 也不产生修正,它把技能加入单位 granted_skills(装/卸时重算)
        # ap_damage / apply_status 等战斗类效果不在修正管道展开:active 由战斗引擎
        # execute_active_effect 执行,被动类(如 apply_status with trigger_point)
        # 由 dispatch_trigger → execute_passive_effect 执行(ADR-0008/0011)。
    return mods


# ---------------------------------------------------------------------------
# 主动/被动效果执行器(批次2,由战斗引擎调用,ADR-0008/0010/0011)
# ---------------------------------------------------------------------------

def apply_status_from_effect(eff: Effect, target) -> list[str]:
    """施加状态(ADR-0010 消费模型):重施加取 max(当前, 新层),不叠加。

    读 params.status(状态类型字符串)、params.duration(层数,缺省取 STATUS_META 默认)。
    返回施加的状态名列表(可多状态,本效果通常单状态)。
    """
    from .triggers import apply_status, StatusType
    applied: list[str] = []
    p = eff.params or {}
    st = p.get("status")
    if not st:
        return applied
    layers = p.get("duration")
    try:
        applied.append(apply_status(target, st, layers))
    except ValueError:
        # 未知状态类型:跳过(脏数据容忍)
        pass
    return applied


def execute_active_effect(eff: Effect, ctx, attacker, target) -> dict:
    """执行一条主动效果(ap_damage / apply_status),由战斗引擎行动段调用。

    ap_damage 委托 ctx.resolve_strike(...) 走与普通攻击一致的命中/格挡/闪避/暴击管道
    (单一来源,不重复实现)。apply_status 调 apply_status_from_effect 对 target 施加。
    返回 {dmg, kind, blocked, evaded, crit, status_applied} 供日志与后续时点。
    """
    p = eff.params or {}
    et = eff.effect_type
    status_applied: list[str] = []
    if et == "ap_damage":
        kind = p.get("kind", "physical")
        value = int(p.get("value", 0))
        # 委托战斗管道:flat_dmg 传 value,由 resolve_strike 按 kind 取攻防
        res = ctx.resolve_strike(ctx, attacker, target, kind, flat_dmg=value)
        return {"dmg": res.dmg, "kind": res.kind, "blocked": res.blocked,
                "evaded": res.evaded, "crit": res.crit, "status_applied": []}
    if et == "apply_status":
        status_applied = apply_status_from_effect(eff, target)
        # apply_status 本身不造成伤害,但可能伴随 ap_damage(由调用方对每个 effect 逐条调)
        return {"dmg": 0, "kind": "", "blocked": False, "evaded": False,
                "crit": False, "status_applied": status_applied}
    # 未知主动效果类型:无操作
    return {"dmg": 0, "kind": "", "blocked": False, "evaded": False,
            "crit": False, "status_applied": []}


def execute_passive_effect(eff: Effect, ctx, actor, target) -> dict:
    """执行一条被动效果(被动响应时调用,ADR-0011)。

    apply_status→对 target 施加(如 frost_warden 在 on_block 时把攻击者冻结,target=攻击者)。
    ap_damage→委托 ctx.resolve_strike(被动追击也走管道)。
    返回同 execute_active_effect 的 dict。
    """
    p = eff.params or {}
    et = eff.effect_type
    if et == "apply_status":
        applied = apply_status_from_effect(eff, target)
        return {"dmg": 0, "kind": "", "blocked": False, "evaded": False,
                "crit": False, "status_applied": applied}
    if et == "ap_damage":
        kind = p.get("kind", "physical")
        value = int(p.get("value", 0))
        res = ctx.resolve_strike(ctx, actor, target, kind, flat_dmg=value)
        return {"dmg": res.dmg, "kind": res.kind, "blocked": res.blocked,
                "evaded": res.evaded, "crit": res.crit, "status_applied": []}
    return {"dmg": 0, "kind": "", "blocked": False, "evaded": False,
            "crit": False, "status_applied": []}


def active_cost(eff: Effect) -> tuple[int, int]:
    """主动效果的 (ap_cost, mana_cost)。"""
    return int(eff.ap_cost), int(eff.mana_cost)


def passive_pp_cost(eff: Effect) -> int:
    """被动效果的 pp_cost。"""
    return int(eff.pp_cost)
