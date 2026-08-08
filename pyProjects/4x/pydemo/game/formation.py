"""战斗策略(Formation):战前为部队每单位预设的优先级表,战斗按预设自动结算。

单位策略表 = 至多 8 条,分上下两区(主动区 + 被动区),两区合计 ≤8 自由分配
(ADR-0011)。每行 = 一个技能 + 若干条件:
  - 主动区行:轮到本单位行动时按行序从上到下检测;首个可释放(必要条件满足 +
    AP/Mana 足)的主动技能即释放,结束本次行动。
  - 被动区行:在触发时点(TriggerPoint)检测;一次攻击的每个时点最多 1 个单位响应
    (按时点各自计)。

条件分两型(ADR-0011):
  - 必要条件:全满足才允许释放并筛选合法目标(先过滤)。
  - 优先条件:满足则偏好该目标,不影响是否释放(后排序)。
条件编码为结构化 dict(如 {"type":"self_hp_le","threshold":50}),详见 triggers.py。

向后兼容:无 rows 时用旧 target_pref(low_hp/front/random)做选目标 fallback,
便于未接 skill_defs 的旧调用方继续工作。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

from .unit import Unit
from .army import Army, row_of, col_of, ROWS, ROW_CN
from .effects import skill_kind, SKILL_ACTIVE, SKILL_PASSIVE
from .triggers import (
    TriggerPoint, is_necessary, is_priority, eval_necessary, priority_key,
    has_status, StatusType,
)

STRATEGY_ROW_CAP = 8   # 主动区 + 被动区合计上限(ADR-0011)


@dataclass
class StrategyRow:
    """策略表一行:一个技能 + 若干条件。

    主动行 trigger_point=None,轮到本单位按行序检测;被动行 trigger_point 设,
    在该触发时点检测。costs 从技能的 Effect 在调度时读取,不在行内重复存储。
    """
    skill_id: str
    trigger_point: TriggerPoint | None = None
    necessary: list[dict] = field(default_factory=list)   # 必要条件(全满足才释放并筛目标)
    priority: list[dict] = field(default_factory=list)    # 优先条件(满足则偏好目标)


@dataclass
class UnitStrategy:
    """单位策略:主动区 + 被动区,合计 ≤8 行(ADR-0011)。

    旧字段 target_pref/skill_order/hold_position 保留作向后兼容:无 rows 时
    choose_target_with_slots 退化为用 target_pref 选目标。
    """
    unit_id: str
    active_rows: list[StrategyRow] = field(default_factory=list)
    passive_rows: list[StrategyRow] = field(default_factory=list)
    # 向后兼容(无 rows 时 fallback)
    target_pref: str = "low_hp"      # low_hp | front | random
    skill_order: list[str] = field(default_factory=list)
    hold_position: bool = False

    @property
    def total_rows(self) -> int:
        return len(self.active_rows) + len(self.passive_rows)


def validate_strategy(strat: UnitStrategy) -> None:
    """策略表合计 ≤8 行(ADR-0011)。"""
    if strat.total_rows > STRATEGY_ROW_CAP:
        raise ValueError(
            f"策略表超过 {STRATEGY_ROW_CAP} 行上限:单位 {strat.unit_id} "
            f"主动 {len(strat.active_rows)} + 被动 {len(strat.passive_rows)}")


def _trigger_point_of_passive(skill_def: dict) -> TriggerPoint | None:
    """从被动技能的 effect dict 读 trigger_point(放 effect dict,多 effect 可各发各时点)。

    取该技能第一个带 trigger_point 的 passive effect 的时点;无则 None(被动无时点
    视为不可调度,battle_start 可兜底)。
    """
    for e in skill_def.get("effects", []):
        tp = e.get("trigger_point")
        if tp:
            try:
                return TriggerPoint(tp)
            except ValueError:
                return None
    return None


def default_strategy(unit: Unit, skill_defs: dict[str, dict] | None = None) -> UnitStrategy:
    """根据单位词条与技能定义给默认策略。

    skill_defs 提供时:按 skill kind 分流——主动技能进 active_rows(必要条件按 tag
    给 target_pref_front/low_hp,各 1 行/技能,定义序),被动技能进 passive_rows
    (trigger_point 读 effect dict)。skill_defs=None 时退化为旧行为(skill_order=
    list(unit.skills) 全塞作向后兼容,不建 rows)。
    """
    pref = "low_hp"
    if "melee" in unit.tags:
        pref = "front"
    # 兼容旧默认偏好
    target_pref = pref
    active_rows: list[StrategyRow] = []
    passive_rows: list[StrategyRow] = []

    if skill_defs:
        for sid in unit.effective_skills():
            sd = skill_defs.get(sid)
            if sd is None:
                continue
            kind = skill_kind(sd)
            if kind == SKILL_ACTIVE:
                # 主动行:按 tag 给必要目标偏好(melee→front,远程/魔法→low_hp)
                nec = [{"type": "target_pref_front"}] if "melee" in unit.tags \
                     else [{"type": "target_pref_low_hp"}]
                active_rows.append(StrategyRow(skill_id=sid, trigger_point=None,
                                               necessary=nec, priority=[]))
            elif kind == SKILL_PASSIVE:
                tp = _trigger_point_of_passive(sd)
                passive_rows.append(StrategyRow(skill_id=sid, trigger_point=tp,
                                                 necessary=[], priority=[]))
            # perk 不进策略表(走修正管道,不占槽)

    strat = UnitStrategy(
        unit_id=unit.id,
        active_rows=active_rows,
        passive_rows=passive_rows,
        target_pref=target_pref,
        skill_order=list(unit.skills),   # 向后兼容
        hold_position=False,
    )
    validate_strategy(strat)
    return strat


def build_default_formation(army: Army, unit_index: dict[str, Unit],
                            skill_defs: dict[str, dict] | None = None,
                            ) -> dict[str, UnitStrategy]:
    """为部队每个活着的单位生成默认策略。合计 ≤8 行,超限抛 ValueError。"""
    return {u.id: default_strategy(u, skill_defs)
            for u in army.alive_units(unit_index)}


def choose_target_with_slots(
    attacker_slot: int,
    attacker_tags: set[str],
    enemy_slots: list[tuple[int, Unit]],
    strat: UnitStrategy,
    rng=None,
    necessary: list[dict] | None = None,
    priority: list[dict] | None = None,
    eff_map: dict[str, dict[str, float]] | None = None,
    ctx: Any = None,
    attacker: Unit | None = None,
) -> tuple[int, Unit] | None:
    """带敌方槽位的可达性 + 策略选目标。

    近战:只能打到对方最前排(最近一排有人的);前排有人打前排,否则中排,否则后排
    (体现「前排掩护后排」)。远程/魔法:可打任意存活单位(越排)。

    条件两阶段(ADR-0011):必要先过滤合法目标(池空回退可达性池,不软锁),优先后
    在合法目标中稳定排序(多个优先条件按列表序组合)。无 necessary/priority 时用旧
    strat.target_pref 选目标(向后兼容)。

    rng:带 .choice/.random() 的随机对象(注入,便于测试定种子);缺省用 random。
    ctx/attacker:供必要条件 self_hp_le/ally_avg_hp_le/row_count_ge 求值(无目标型)。
    """
    import random as _r
    if rng is None:
        rng = _r
    is_melee = "melee" in attacker_tags
    alive = [(s, u) for s, u in enemy_slots if u.alive]
    if not alive:
        return None
    if is_melee:
        # 打最前排(最近一排有人的)
        pool = []
        for row in ("front", "mid", "back"):
            row_units = [(s, u) for s, u in alive if row_of(s) == row]
            if row_units:
                pool = row_units
                break
        if not pool:
            return None
    else:
        pool = alive

    reachable = list(pool)   # 回退用

    # 必要条件过滤(目标型:target_pref_*/enemy_has_frozen)
    if necessary:
        filtered = []
        for s, u in pool:
            ok = True
            for cond in necessary:
                # 仅评估目标型必要条件;无目标型(self_hp_le 等)在此不评估
                t = cond.get("type")
                if t in ("self_hp_le", "ally_avg_hp_le", "row_count_ge"):
                    continue   # gate 释放,不在此筛
                c = dict(cond)
                c["_target_slot"] = s
                if not eval_necessary(c, ctx, attacker, target=u, eff_map=eff_map):
                    ok = False
                    break
            if ok:
                filtered.append((s, u))
        if filtered:
            pool = filtered
        else:
            pool = reachable   # 池空回退可达性池,不软锁

    # 优先条件稳定排序(多条件按列表序组合)
    if priority:
        def sort_key(su):
            s, u = su
            keys = []
            for cond in priority:
                keys.append(priority_key(cond, ctx, u, target_slot=s))
            keys.append(su[1].id)   # 稳定 tiebreak
            return tuple(keys)
        pool = sorted(pool, key=sort_key)
        return pool[0]

    # 旧 target_pref fallback(无 priority 时)
    tp = strat.target_pref if strat else "low_hp"
    if tp == "low_hp":
        return sorted(pool, key=lambda su: su[1].cur_hp)[0]
    if tp == "front":
        front = [(s, u) for s, u in pool if row_of(s) == "front"]
        return (front or pool)[0]
    # random
    return rng.choice(pool)
