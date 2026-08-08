"""
阵营:玩家或 AI 拥有的实体。

持有资源、信念、据点、部队、英雄、招募池、待命池。
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
    # 待命池:单位 id -> 冷却剩余回合(0=可用,>0=不可用,下场后 5 回合冷却)
    # 阵营级、无位置:所有己方单位要么在某部队,要么在待命池。见 ADR-0005。
    standby: dict[str, int] = field(default_factory=dict)
    # 仓库:阵营持有的装备实例列表,最多 200 件(ADR-0007)。
    # 每件 ArtifactInstance 有 def_id/state/cooldown/equipped_by。
    inventory: list = field(default_factory=list)
    # 每据点的招募池
    recruitment_pools: dict[str, RecruitmentPool] = field(default_factory=dict)
    # 领主任命:据点 id -> 英雄单位 id(领主职责待重定义,见 ADR-0006)
    lords: dict[str, str] = field(default_factory=dict)
    alive: bool = True

    def standby_available_ids(self) -> list[str]:
        """待命·可用的单位 id(冷却 <= 0)。"""
        return [uid for uid, cd in self.standby.items() if cd <= 0]

    def inventory_instances(self) -> list:
        """仓库内所有装备实例(已装备 + 在库)。"""
        return list(self.inventory)

    def inventory_available_instances(self) -> list:
        """在库且可装备/可卖出的实例(state=available 且未装备)。"""
        return [a for a in self.inventory if a.is_available()]

    def describe(self) -> str:
        return (f"{self.name}({self.id}) {'[AI]' if self.is_ai else '[玩家]'} "
                f"首都:{self.capital_id} 据点:{len(self.stronghold_ids)} "
                f"部队:{len(self.army_ids)} 英雄:{len(self.hero_ids)} "
                f"待命:{len(self.standby)}")
