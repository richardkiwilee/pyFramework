"""
地图:结点(据点 / 小地点)+ 连线。固定拓扑,简化移动。

据点规模映射普通建筑槽数:小 1 / 中 2 / 大 3。
据点不再有"失能"状态:驻军被全灭、进攻方进入据点即易主,标志建筑转进攻方版本。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

from .economy import Resources


SIZE_SLOTS = {"small": 1, "medium": 2, "large": 3}
SIZE_CN = {"small": "小", "medium": "中", "large": "大"}


@dataclass
class Building:
    """据点内一座建筑,占据一个普通槽位。"""
    id: str               # 实例 id
    type_id: str          # building 定义 id
    name: str
    produces: dict[str, int] = field(default_factory=dict)   # 每回合产出资源
    build_turns_left: int = 0    # >0 表示建造中,每回合 -1,到 0 才产出
    # 后期:为驻军提供 buff 等;原型不实现

    def is_ready(self) -> bool:
        return self.build_turns_left <= 0

    def tick_build(self) -> None:
        if self.build_turns_left > 0:
            self.build_turns_left -= 1


@dataclass
class Stronghold:
    """据点(强点):可被占领的结点。"""
    id: str
    name: str
    size: str            # small/medium/large -> 普通建筑槽数
    landmark_type: str   # 标志建筑类型 id(决定驻军编队档位 弱/中/强)
    owner: str | None    # 阵营 id,None 表示中立
    is_capital: bool = False
    # 普通建筑(数量 <= size 对应槽数)
    buildings: list[Building] = field(default_factory=list)
    # 玩家驻军部队 id(若有部队驻扎在此),由 Game 维护映射;此处仅记标记
    stationed_army_id: str | None = None
    # 坐标(仅用于展示)
    x: int = 0
    y: int = 0

    def slots(self) -> int:
        return SIZE_SLOTS.get(self.size, 1)

    def free_slots(self) -> int:
        return self.slots() - len(self.buildings)

    def add_building(self, b: Building) -> bool:
        if self.free_slots() <= 0:
            return False
        self.buildings.append(b)
        return True

    def tick_builds(self) -> dict[str, int]:
        """推进所有建筑建造,返回本回合已就绪建筑产出。"""
        gained: dict[str, int] = {}
        for b in self.buildings:
            was_ready = b.is_ready()
            b.tick_build()
            if not was_ready and b.is_ready():
                # 刚就绪,本回合开始产出(下回合也算)
                pass
            if b.is_ready():
                for k, v in b.produces.items():
                    gained[k] = gained.get(k, 0) + v
        return gained

    def describe(self) -> str:
        owner = self.owner if self.owner else "中立"
        cap = "(首都)" if self.is_capital else ""
        bld = "、".join(b.name + ("(建造中)" if not b.is_ready() else "")
                       for b in self.buildings) or "空"
        return (f"{self.name}[{SIZE_CN[self.size]}]{cap} 主:{owner} "
                f"标志:{self.landmark_type} 建筑:[{bld}] 槽:{len(self.buildings)}/{self.slots()}")


@dataclass
class MinorLocation:
    """小地点:仅地形,不可占领。"""
    id: str
    name: str
    terrain: str   # terrain 定义 id:平原/山地/森林
    x: int = 0
    y: int = 0


@dataclass
class GameMap:
    """整张地图:据点 + 小地点 + 邻接。"""
    strongholds: dict[str, Stronghold] = field(default_factory=dict)
    minors: dict[str, MinorLocation] = field(default_factory=dict)
    adj: dict[str, list[str]] = field(default_factory=dict)   # 无向图邻接表

    def add_stronghold(self, s: Stronghold) -> None:
        self.strongholds[s.id] = s

    def add_minor(self, m: MinorLocation) -> None:
        self.minors[m.id] = m

    def connect(self, a: str, b: str) -> None:
        self.adj.setdefault(a, [])
        self.adj.setdefault(b, [])
        if b not in self.adj[a]:
            self.adj[a].append(b)
        if a not in self.adj[b]:
            self.adj[b].append(a)

    def node_name(self, nid: str) -> str:
        if nid in self.strongholds:
            return self.strongholds[nid].name
        return self.minors[nid].name

    def is_stronghold(self, nid: str) -> bool:
        return nid in self.strongholds

    def neighbors(self, nid: str) -> list[str]:
        return self.adj.get(nid, [])

    def all_nodes(self) -> list[str]:
        return list(self.strongholds.keys()) + list(self.minors.keys())

    def describe(self) -> str:
        lines = ["=== 地图 ==="]
        for s in self.strongholds.values():
            lines.append(s.describe())
        for m in self.minors.values():
            lines.append(f"{m.name}(小地点·{m.terrain})")
        lines.append("--- 连接 ---")
        seen = set()
        for a, nbrs in self.adj.items():
            for b in nbrs:
                key = tuple(sorted([a, b]))
                if key in seen:
                    continue
                seen.add(key)
                lines.append(f"{self.node_name(a)} -- {self.node_name(b)}")
        return "\n".join(lines)
