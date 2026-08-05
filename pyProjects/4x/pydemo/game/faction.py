"""
阵营:玩家或 AI 拥有的实体。

持有资源、信念、据点、部队、英雄、招募池、聚贤庄。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

from .economy import Resources, Belief
from .hero import RecruitmentPool
from .army import Army


@dataclass
class Faction:
    id: str
    name: str
    is_ai: bool = False
    resources: Resources = field(default_factory=Resources)
    belief: Belief = field(default_factory=Belief)
    capital_id: str | None = None
    army_ids: list[str] = field(default_factory=list)         # 玩家编组部队 id
    hero_ids: list[str] = field(default_factory=list)        # 在地图上的英雄单位 id
    stronghold_ids: list[str] = field(default_factory=list)  # 拥有的据点 id
    # 聚贤庄:英雄单位 id -> 进入时的冷却剩余回合
    hall_of_worthies: dict[str, int] = field(default_factory=dict)
    # 每据点的招募池
    recruitment_pools: dict[str, RecruitmentPool] = field(default_factory=dict)
    # 领主任命:据点 id -> 英雄单位 id
    lords: dict[str, str] = field(default_factory=dict)
    alive: bool = True

    def describe(self) -> str:
        return (f"{self.name}({self.id}) {'[AI]' if self.is_ai else '[玩家]'} "
                f"首都:{self.capital_id} 据点:{len(self.stronghold_ids)} "
                f"部队:{len(self.army_ids)} 英雄:{len(self.hero_ids)}")
