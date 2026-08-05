"""
资源与信念。

11 种全局资源:金币、食物、木材、石材、铁矿、魔石、科技、文化、信仰、奢侈品、政令。
信念:阵营多维属性,原型 3 维(道德/功利/自由),每维 [-100, +100],以 0 为中心。
维度独立、互不制约。

资源定义来自 data/resources.json;信念维度固定为 3 维(代码常量)。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

# 资源枚举(顺序无关,仅用于展示)
RESOURCE_TYPES = [
    "gold", "food", "wood", "stone", "iron", "mana_stone",
    "tech", "culture", "faith", "luxury", "decree",
]
RESOURCE_CN = {
    "gold": "金币", "food": "食物", "wood": "木材", "stone": "石材",
    "iron": "铁矿", "mana_stone": "魔石", "tech": "科技", "culture": "文化",
    "faith": "信仰", "luxury": "奢侈品", "decree": "政令",
}

# 信念维度(原型 3 维)
BELIEF_DIMS = ["morality", "utility", "liberty"]
BELIEF_CN = {"morality": "道德", "utility": "功利", "liberty": "自由"}
BELIEF_BOUND = 100  # 每维 [-100, +100]


@dataclass
class Resources:
    """阵营持有的全局资源。"""
    amounts: dict[str, int] = field(default_factory=lambda: {k: 0 for k in RESOURCE_TYPES})

    def get(self, k: str) -> int:
        return self.amounts.get(k, 0)

    def add(self, k: str, v: int) -> None:
        self.amounts[k] = self.amounts.get(k, 0) + v

    def can_afford(self, costs: dict[str, int]) -> bool:
        return all(self.get(k) >= v for k, v in costs.items())

    def pay(self, costs: dict[str, int]) -> bool:
        if not self.can_afford(costs):
            return False
        for k, v in costs.items():
            self.add(k, -v)
        return True

    def describe(self) -> str:
        return "  ".join(f"{RESOURCE_CN[k]}:{self.amounts[k]}" for k in RESOURCE_TYPES
                        if self.amounts[k] != 0)


@dataclass
class Belief:
    """阵营信念,3 维,每维 [-100, +100]。"""
    values: dict[str, int] = field(default_factory=lambda: {d: 0 for d in BELIEF_DIMS})

    def get(self, dim: str) -> int:
        return self.values.get(dim, 0)

    def change(self, dim: str, delta: int) -> None:
        v = self.values.get(dim, 0) + delta
        self.values[dim] = max(-BELIEF_BOUND, min(BELIEF_BOUND, v))

    def meets(self, dim: str, threshold: int) -> bool:
        return self.get(dim) >= threshold

    def describe(self) -> str:
        return "  ".join(f"{BELIEF_CN[d]}:{self.values[d]:+d}" for d in BELIEF_DIMS)
