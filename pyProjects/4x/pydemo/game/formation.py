"""
战斗策略(Formation):战前为部队每单位预设的优先级表,战斗按预设自动结算。

原型策略以单位为单位,每单位一张策略卡:
  - target_pref: 目标偏好 'low_hp'(血最少)/'front'(前排优先)/'random'
  - skill_order: 主动技能释放顺序(技能 id 列表,按 AP/Mana 够则释放)
  - hold_position: 是否倾向不动(防守用)
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

from .unit import Unit
from .army import Army, row_of, col_of, ROWS, ROW_CN


@dataclass
class UnitStrategy:
    unit_id: str
    target_pref: str = "low_hp"      # low_hp | front | random
    skill_order: list[str] = field(default_factory=list)
    hold_position: bool = False


def default_strategy(unit: Unit) -> UnitStrategy:
    """根据单位词条给默认策略。"""
    pref = "low_hp"
    if "ranged" in unit.tags or "magic" in unit.tags:
        pref = "low_hp"
    elif "melee" in unit.tags:
        pref = "front"
    # 主动技能顺序 = 单位的 skills 中标为 active 的(由战斗时再筛)
    return UnitStrategy(unit_id=unit.id, target_pref=pref,
                       skill_order=list(unit.skills), hold_position=False)


def build_default_formation(army: Army, unit_index: dict[str, Unit]) -> dict[str, UnitStrategy]:
    """为部队每个活着的单位生成默认策略。"""
    return {u.id: default_strategy(u) for u in army.alive_units(unit_index)}


def choose_target(
    attacker: Unit,
    attacker_slot: int,
    enemies: list[Unit],
    strat: UnitStrategy,
    rng_pick=None,
) -> Unit | None:
    """按可达性与策略选目标。"""
    import random as _r
    rng_pick = rng_pick or _r.choice
    atk_row = row_of(attacker_slot)
    atk_col = col_of(attacker_slot)
    alive_enemies = [e for e in enemies if e.alive]
    if not alive_enemies:
        return None
    # 敌方槽位信息需要 enemy 的 slot;此处简化:近战只能打前排存活者
    # 完整可达性需 enemy slot,在 battle 中传入
    return None  # 由 battle 用带 slot 的版本选目标


def choose_target_with_slots(
    attacker_slot: int,
    attacker_tags: set[str],
    enemy_slots: list[tuple[int, Unit]],
    strat: UnitStrategy,
    rng_pick=None,
) -> tuple[int, Unit] | None:
    """
    带敌方槽位的可达性 + 策略选目标。
    近战:只能打到对方最前排(最近一排有人的);前排有人打前排,否则中排,否则后排。
         这体现"前排掩护后排":前排尚存时无法越过,前排清空后近战推进到下一排。
    远程/魔法:可打任意存活单位(越排)。
    """
    import random as _r
    rng_pick = rng_pick or _r.choice
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
    # 策略偏好
    if strat.target_pref == "low_hp":
        return sorted(pool, key=lambda su: su[1].cur_hp)[0]
    elif strat.target_pref == "front":
        front = [(s, u) for s, u in pool if row_of(s) == "front"]
        return (front or pool)[0]
    else:
        return rng_pick(pool)
