"""
统一修正管道。

所有修正源——月相、昼夜、兵种词条、羁绊、信念、技能、装备、地形——经同一条管道收集,
以统一结构 (来源类型, 目标, 属性, 数值, 条件) 表达,按目标聚合后按固定顺序计算:
先固定加,再百分比乘,最后 clamp 到属性上下界。

详见 ADR-0002。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable


class ModifierSource(str, Enum):
    MOON = "moon"            # 月相
    DAY_NIGHT = "day_night"  # 昼夜
    TAG = "tag"              # 兵种词条
    SYNERGY = "synergy"      # 羁绊
    BELIEF = "belief"        # 信念(作为修正)
    SKILL = "skill"          # 技能/被动
    ARTIFACT = "artifact"    # 装备
    TERRAIN = "terrain"      # 地形
    LANDMARK = "landmark"    # 据点标志建筑(驻军 buff)


@dataclass
class Modifier:
    """一条修正。op 为 'flat'(固定加)或 'pct'(百分比乘,以小数表示,+10% = 0.1)。"""
    source: ModifierSource
    source_id: str           # 来源的具体 id(技能 id/词条名/建筑 id 等)
    target: str              # 目标标识,如单位实例 id 或部队 id 或建筑 id
    attr: str                # 被修正的属性名
    value: float             # 数值
    op: str = "flat"         # 'flat' | 'pct'
    condition: Any = None    # 可选条件,由收集器解释(通常为 None)


@dataclass
class ModifierCollection:
    """所有修正的暂存池。每个回合/每次战斗前收集,然后按目标聚合计算。"""
    mods: list[Modifier] = field(default_factory=list)

    def add(self, mod: Modifier) -> None:
        self.mods.append(mod)

    def extend(self, mods: list[Modifier]) -> None:
        self.mods.extend(mods)

    def for_target(self, target: str) -> list[Modifier]:
        return [m for m in self.mods if m.target == target]


def compute_attribute(
    base: float,
    mods: list[Modifier],
    attr: str,
    lo: float | None = None,
    hi: float | None = None,
) -> float:
    """
    按固定顺序计算:固定加 -> 百分比乘 -> clamp,每阶段向下取整(floor)。
    玩家面板与战斗所用均为整数,玩家可用整数反推公式,故底层不留隐藏小数。
    只处理 attr 匹配的修正。
    """
    import math
    relevant = [m for m in mods if m.attr == attr]
    flat = sum(m.value for m in relevant if m.op == "flat")
    pct = sum(m.value for m in relevant if m.op == "pct")
    # 阶段 1:base + flat,floor
    result = float(math.floor(base + flat))
    # 阶段 2:*(1+pct),floor
    result = float(math.floor(result * (1.0 + pct)))
    # 阶段 3:clamp(边界本身为整数,clamp 后天然整数)
    if lo is not None:
        result = max(lo, result)
    if hi is not None:
        result = min(hi, result)
    return float(math.floor(result))
