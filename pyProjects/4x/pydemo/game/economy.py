"""
资源与信念。

11 种全局资源:金币、食物、木材、石材、铁矿、魔石、科技、文化、信仰、奢侈品、政令。
信念:阵营多维属性,原型 3 维(道德/功利/自由),每维 [-100, +100],以 0 为中心。
维度独立、互不制约。

资源定义来自 data/resources.json;信念维度固定为 3 维(代码常量)。

§2 资源面板:每种资源为一个 Resource 对象(自带 output 方法 + 变动细项),
由 Resources 容器持有。add 渐进式签名 add(k,v,source=None,stronghold=None,building=None):
老调用不传来源记"未知",新调用显式传来源逐步迁移。net() 给出本回合净变动(+1/-1),
output() 渲染"现存(净变动)"形式如"20(+1)";增量 >0 绿色、≤0 红色由调用方据 net 决策色。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

# 资源来源类型枚举(用于 delta 细项溯源)
SOURCE_BUILD = "build"           # 建造产出
SOURCE_MAINT = "maint"           # 维护扣除
SOURCE_EVENT = "event"           # 事件
SOURCE_RECRUIT = "recruit"       # 招募
SOURCE_TRAIN = "train"           # 训练
SOURCE_SUPPLY = "supply"         # 补给补充/消耗
SOURCE_INIT = "init"            # 初始/事件结算
SOURCE_UNKNOWN = "unknown"

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
class DeltaItem:
    """一条资源变动细项(§2)。Python 原型不展示,godot 迁移以悬停弹窗呈现。"""
    source: str = SOURCE_UNKNOWN   # 来源类型
    value: int = 0                 # ±N
    stronghold: str | None = None  # 来源据点 id
    building: str | None = None    # 来源建筑名(建筑级溯源)


@dataclass
class Resource:
    """单个全局资源对象(§2):存量 + 本回合变动细项。

    output() 渲染"现存(净变动)"形式,如"20(+1)";括号内为本回合已结算净变动。
    net() 返回本回合净变动(所有 delta 之和)。
    每回合开始前应 reset_turn() 清空 delta(存量保留),供下回合重新累计。
    display_net() = net() + 投影(建造/拆除后立刻可见的下回合预估产出,操作逻辑.md §2.1):
    用于资源面板的"下回合变化"实时刷新——建造农场后立刻从 (-3) 变 (+2)。
    投影由 add_projected() 写入,reset_turn() 一并清空(下回合真实产出由 tick_economy 记 delta,不重复)。
    """
    kind: str = "gold"
    amount: int = 0
    deltas: list[DeltaItem] = field(default_factory=list)
    _projected: int = 0   # 投影预估(操作逻辑.md §2.1):建造/拆除后立刻可见的下回合产出

    def add(self, v: int, source: str = SOURCE_UNKNOWN,
            stronghold: str | None = None, building: str | None = None) -> None:
        self.amount += v
        self.deltas.append(DeltaItem(source=source, value=v,
                                     stronghold=stronghold, building=building))

    def add_projected(self, v: int) -> None:
        """累加投影预估(操作逻辑.md §2.1)。正负皆可(建造 +产出 / 拆除 -产出)。"""
        self._projected += v

    def clear_projected(self) -> None:
        self._projected = 0

    def net(self) -> int:
        return sum(d.value for d in self.deltas)

    def display_net(self) -> int:
        """面板用净变动 = 本回合已结算净变动 + 下回合投影预估。"""
        return self.net() + self._projected

    def reset_turn(self) -> None:
        """回合开始清空 delta 与投影(存量保留),供下回合重新累计。"""
        self.deltas.clear()
        self._projected = 0

    def output(self) -> str:
        """渲染 现存(净变动) 形式,如 20(+1)。用 display_net(含投影)。"""
        n = self.display_net()
        sign = "+" if n >= 0 else ""   # 负数自带 -
        return f"{self.amount}({sign}{n})"


@dataclass
class Resources:
    """阵营持有的全局资源(§2):每种资源一个 Resource 对象 + 兼容旧 amounts 视图。

    老代码经 amounts 视图(get/add/can_afford/pay/describe)透明工作;
    新代码经 add(k,v,source,stronghold,building) 记 delta 细项。
    """
    amounts: dict[str, int] = field(default_factory=lambda: {k: 0 for k in RESOURCE_TYPES})
    # §2 资源对象视图:按 kind 懒建
    _resources: dict[str, Resource] = field(default_factory=dict)

    def _res(self, k: str) -> Resource:
        if k not in self._resources:
            self._resources[k] = Resource(kind=k, amount=self.amounts.get(k, 0))
        else:
            # 与 amounts 视图同步:若 amounts 被直接改过(如 scenario 初始化),刷新存量
            self._resources[k].amount = self.amounts.get(k, 0)
        return self._resources[k]

    def get(self, k: str) -> int:
        return self.amounts.get(k, 0)

    def add(self, k: str, v: int, source: str = SOURCE_UNKNOWN,
            stronghold: str | None = None, building: str | None = None) -> None:
        """加资源。渐进式签名:老调用不传 source 记 unknown,新调用显式传来源。"""
        self.amounts[k] = self.amounts.get(k, 0) + v
        # 同时记入资源对象(§2 delta 细项)
        self._res(k).add(v, source=source, stronghold=stronghold, building=building)

    def can_afford(self, costs: dict[str, int]) -> bool:
        return all(self.get(k) >= v for k, v in costs.items())

    def pay(self, costs: dict[str, int], source: str = SOURCE_UNKNOWN,
            stronghold: str | None = None, building: str | None = None) -> bool:
        """扣资源。新签名可传 source 记 delta(如 build/recruit/train);老调用透明。"""
        if not self.can_afford(costs):
            return False
        for k, v in costs.items():
            self.add(k, -v, source=source, stronghold=stronghold, building=building)
        return True

    def reset_turn(self) -> None:
        """回合开始:清空所有资源对象的 delta(存量保留),供下回合累计(§2)。"""
        for k in list(self._resources.keys()):
            self._resources[k].reset_turn()

    def resource(self, k: str) -> Resource:
        """取某资源的对象视图(§2 output/net/deltas)。"""
        return self._res(k)

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
