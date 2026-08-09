"""
部队:3x3 九宫格,前/中/后三排,最多 9 个单位。

必须由英雄任队长,队长的 Leadership(领导力)决定部队可承载的 Occupy(占用)总和。
每个单位在九宫格恒占 1 格,但消耗的占用不同(强/大单位占用更高)。
部队必须始终有队长;队长离队须同据点指派接任,否则解散。

九宫格行列决定攻击可达性与掩拦:
近战只能打同列或邻列前排;远程/魔法可越排;前排掩护同列后排。

部队均为玩家编组部队(可编辑);据点不再拥有独立的不可编辑驻军(驻军系统已废除,
据点防御靠标志性建筑给驻守部队提供 buff)。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

from .unit import Unit

# 九宫格 3x3,索引 0..8,按行存储:0,1,2 为前排;3,4,5 为中排;6,7,8 为后排
# (前排索引最小、最先被打;后排索引最大。row_of 与此一致。)
ROWS = ["front", "mid", "back"]
ROW_CN = {"front": "前", "mid": "中", "back": "后"}
GRID_SIZE = 9


def row_of(slot: int) -> str:
    # slot 0..8 -> row: 0-2 前, 3-5 中, 6-8 后
    return ROWS[slot // 3]   # 0-2 -> front, 3-5 -> mid, 6-8 -> back


def col_of(slot: int) -> int:
    return slot % 3


@dataclass
class Army:
    """一支部队。"""
    id: str
    name: str
    captain_id: str | None = None     # 队长单位 id(必须为英雄)
    grid: list[str | None] = field(default_factory=lambda: [None] * GRID_SIZE)  # 单位 id
    owner: str | None = None           # 阵营 id
    node_id: str | None = None         # 当前所在结点
    # 战斗内标记
    has_acted_this_turn: bool = False  # 本回合是否已主动发起战斗
    supply: int = 10                   # 部队补给携带量
    supply_max: int = 10

    def units(self, unit_index: dict[str, Unit]) -> list[Unit]:
        return [unit_index[uid] for uid in self.grid if uid is not None]

    def occupy_total(self, unit_index: dict[str, Unit]) -> int:
        """部队当前占用的领导力总和。"""
        return sum(unit_index[uid].occupy() for uid in self.grid if uid is not None)

    def max_leadership(self, unit_index: dict[str, Unit]) -> int:
        """部队可承载的占用上限 = 队长的领导力。"""
        if self.captain_id and self.captain_id in unit_index:
            return unit_index[self.captain_id].leadership()
        return 0

    def can_add(self, unit: Unit, unit_index: dict[str, Unit]) -> bool:
        if unit.id not in unit_index:
            return False
        # 找空位(九宫格最多 9 个单位)
        if None not in self.grid:
            return False
        if self.occupy_total(unit_index) + unit.occupy() > self.max_leadership(unit_index):
            return False
        return True

    def _pick_slot(self, unit: Unit) -> int:
        """按兵种角色挑槽位:近战趋前排,远程/魔法趋后排,其余居中。"""
        if "melee" in unit.tags:
            pref = [0, 1, 2, 3, 4, 5, 6, 7, 8]      # 前排优先(0-2)
        elif "ranged" in unit.tags or "magic" in unit.tags:
            pref = [6, 7, 8, 3, 4, 5, 0, 1, 2]      # 后排优先(6-8)
        else:
            pref = [3, 4, 5, 0, 1, 2, 6, 7, 8]      # 中排优先(3-5)
        for s in pref:
            if self.grid[s] is None:
                return s
        return -1

    def add(self, unit: Unit, unit_index: dict[str, Unit], slot: int | None = None) -> bool:
        if not self.can_add(unit, unit_index):
            return False
        if slot is None:
            slot = self._pick_slot(unit)
            if slot < 0:
                return False
        if self.grid[slot] is not None:
            return False
        self.grid[slot] = unit.id
        unit.army_id = self.id
        return True

    def remove(self, unit_id: str) -> Unit | None:
        for i, uid in enumerate(self.grid):
            if uid == unit_id:
                self.grid[i] = None
                return None  # 返回占位;调用方自行处理 unit.army_id
        return None

    def alive_units(self, unit_index: dict[str, Unit]) -> list[Unit]:
        return [u for u in self.units(unit_index) if u.alive]

    def is_wiped(self, unit_index: dict[str, Unit]) -> bool:
        return len(self.alive_units(unit_index)) == 0

    def slot_of(self, unit_id: str) -> int | None:
        for i, uid in enumerate(self.grid):
            if uid == unit_id:
                return i
        return None

    def describe(self, unit_index: dict[str, Unit]) -> str:
        cap = unit_index[self.captain_id].name if self.captain_id and self.captain_id in unit_index else "无"
        rows = []
        for r in ROWS:  # front, mid, back
            cells = []
            for c in range(3):
                slot = ROWS.index(r) * 3 + c
                uid = self.grid[slot]
                if uid and uid in unit_index:
                    cells.append(unit_index[uid].name)
                else:
                    cells.append("·")
            rows.append(f"{ROW_CN[r]}排[{' '.join(cells)}]")
        return (f"{self.name}(队长:{cap} 占用:{self.occupy_total(unit_index)}/{self.max_leadership(unit_index)} "
                f"补给:{self.supply})\n  " + "\n  ".join(rows))


def empty_army(army_id: str, name: str, owner: str, node_id: str) -> Army:
    return Army(id=army_id, name=name, owner=owner, node_id=node_id)
