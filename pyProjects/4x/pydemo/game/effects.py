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
  - tag_grant:     装备/技能使单位获得某词条(神器附带 Synergy 来源)。params: tag

效果分两类:被动(passive,持续修正)与主动(active,战斗内由策略调用)。
主动效果的类型集与被动相同的接口,但触发时机不同;原型主动技能用 'ap_damage' 等。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

from .modifier import Modifier, ModifierSource


@dataclass
class Effect:
    """数据描述的一条效果。"""
    effect_type: str          # 见上表
    params: dict[str, Any]    # 参数
    trigger: str = "passive"  # passive | active
    ap_cost: int = 0          # 主动效果消耗 AP
    mana_cost: int = 0        # 主动效果消耗 魔力点
    condition: Any = None


def build_skill_effects(skill_def: dict) -> list[Effect]:
    """从技能数据定义构造 Effect 列表。"""
    effects: list[Effect] = []
    for e in skill_def.get("effects", []):
        effects.append(Effect(
            effect_type=e["type"],
            params=e.get("params", {}),
            trigger=e.get("trigger", "passive"),
            ap_cost=e.get("ap_cost", 0),
            mana_cost=e.get("mana_cost", 0),
            condition=e.get("condition"),
        ))
    return effects


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
    return mods
