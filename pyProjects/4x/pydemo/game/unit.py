"""
单位与兵种词条。

兵种词条分两类,全部平级:必选大类(近战/远程/魔法,至少其一,可多选)
与枚举小类(人类/骑兵等,可多选)。词条是修正源与羁绊的输入。

单位属性:占用/生命值/行动点/被动点/魔力点/行动速度/物攻/魔攻/物防/魔防/
命中/闪避/格挡/暴击率/幸运/意志/领导力。
战斗三项资源:HP(跨场累积)、AP/PP(每场开打回满)、Mana(跨场累积,仅按月相恢复,见 ADR-0008)。

单位可装备至多 4 件装备(槽位 0..3,ADR-0009)。装备按定义 def_id 以库存计数存储,
可附带词条(tag_grant)与赋予技能(skill_grant),是修正源与羁绊来源。
单位等级 1~99,升级烘进 base(永久成长);属性底层 double,每阶段 floor。
"""
from __future__ import annotations
from dataclasses import dataclass, field
import math
from typing import Any

# 必选大类
MAJOR_TAGS = {"melee", "ranged", "magic"}
TAG_CN = {
    "melee": "近战", "ranged": "远程", "magic": "魔法",
    "human": "人类", "cavalry": "骑兵",
    "archer": "弓兵",
}

# 单位基础属性及其上下界(用于修正管道 clamp)
# occupy 不进修正管道(恒定,不随等级增长),但仍列于此以便统一展示
UNIT_ATTRS = [
    "occupy", "hp", "ap", "pp", "mana", "speed",
    "p_atk", "m_atk", "p_def", "m_def",
    "acc", "eva", "block", "crit", "luck", "will", "leadership",
]
ATTR_BOUNDS: dict[str, tuple[float, float]] = {
    "hp": (0, 99999), "ap": (0, 99), "pp": (0, 99), "mana": (0, 99), "speed": (1, 999),
    "occupy": (0, 99999), "p_atk": (0, 9999), "m_atk": (0, 9999),
    "p_def": (0, 9999), "m_def": (0, 9999),
    "acc": (0, 100), "eva": (0, 100), "block": (0, 100),
    "crit": (0, 100), "luck": (0, 100), "will": (0, 999), "leadership": (0, 99999),
    "mana_regen": (0, 999),
}
ATTR_CN = {
    "hp": "生命", "ap": "行动点", "pp": "被动点", "mana": "魔力", "speed": "速度",
    "p_atk": "物攻", "m_atk": "魔攻", "p_def": "物防", "m_def": "魔防",
    "acc": "命中", "eva": "闪避", "block": "格挡", "crit": "暴击",
    "luck": "幸运", "will": "意志", "occupy": "占用", "leadership": "领导力",
    "mana_regen": "魔力恢复",
}

LEVEL_CAP = 99


def xp_to_next(level: int) -> int:
    """从 level 升到 level+1 所需经验。公差 5 的等差数列:1->2 需 5,2->3 需 10..."""
    return 5 * level


def validate_tags(tags: set[str]) -> None:
    """必选大类至少一个。"""
    if not (tags & MAJOR_TAGS):
        raise ValueError(f"单位词条缺少必选大类(近战/远程/魔法):{tags}")


@dataclass
class UnitType:
    """兵种定义(data/unit_types.json)。"""
    id: str
    name: str
    tags: set[str]
    recruit_cost: dict[str, int]   # 招募消耗资源
    base: dict[str, float]         # 基础属性
    growth: dict[str, float] = field(default_factory=dict)   # 各属性增长率(每级 += growth[attr])
    maintenance: dict[str, int] = field(default_factory=dict)   # 每回合维护费;缺省走原型默认
    train_cost: dict[str, int] = field(default_factory=dict)    # 训练消耗;缺省走原型默认(gold=招募价/2 + 5 食物,魔法系加魔石)
    desc: str = ""


def load_unit_types(d: dict) -> dict[str, UnitType]:
    out: dict[str, UnitType] = {}
    for uid, u in d.items():
        tags = set(u.get("tags", []))
        validate_tags(tags)
        out[uid] = UnitType(
            id=uid, name=u["name"], tags=tags,
            recruit_cost=u.get("recruit_cost", {}),
            base=u.get("base", {}),
            growth=u.get("growth", {}),
            maintenance=u.get("maintenance", {}),
            train_cost=u.get("train_cost", {}),
            desc=u.get("desc", ""),
        )
    return out


@dataclass
class Artifact:
    """装备定义。可加属性、附带词条(tag_grant)或赋予技能(skill_grant)。"""
    id: str
    name: str
    effects: list[dict] = field(default_factory=list)   # 同 skills 的 effect 原始 dict


def load_artifacts(d: dict) -> dict[str, Artifact]:
    out: dict[str, Artifact] = {}
    for aid, a in d.items():
        out[aid] = Artifact(id=aid, name=a["name"], effects=a.get("effects", []))
    return out


# 装备按 def_id 以库存计数存储(ADR-0009,取代 ADR-0007 实例模型)。
# 不再有件级实例、200 件上限与卸下冷却;已装备数量由所有己方单位的 artifacts 反查。


@dataclass
class Unit:
    """一个单位实例。"""
    id: str
    type_id: str
    name: str
    tags: set[str]                  # 含兵种词条 + 装备赋予的词条
    base: dict[str, float]          # 基础属性(招募时确定 + 等级成长烘进;不含情境修正)
    artifacts: list[str] = field(default_factory=list)   # 装备定义 def_id 列表,最多 4(槽位 0..3,ADR-0009)
    is_hero: bool = False
    skills: list[str] = field(default_factory=list)     # 习得技能 id 列表(英雄)
    granted_skills: list[str] = field(default_factory=list)  # 装备赋予技能 id 列表(装/卸时重算,ADR-0008)
    cur_hp: float = 0               # 当前生命(跨战斗累积,不每场回满)
    army_id: str | None = None      # 所属部队
    # 战斗内临时状态
    cur_ap: float = 0               # 行动点(主动技能资源,每场开打回满,ADR-0008)
    cur_pp: float = 0               # 被动点(被动技能资源,每场开打回满,ADR-0008)
    cur_mana: float = 0             # 魔力(高级资源,跨场累积,进场只 clamp 上限,ADR-0008)
    atb: float = 0                  # 行动条(0..100)
    alive: bool = True
    # 状态(离散标签,消费模型无 tick 计时,ADR-0010)
    statuses: dict[str, int] = field(default_factory=dict)  # status_type -> 剩余层数(0 即将解除;由 triggers.STATUS_META 定消费方式)
    # 当前所在结点
    node_id: str | None = None
    # 成长
    level: int = 1
    xp: int = 0
    # 成长率快照(从 UnitType 复制,供升级时使用;可被事件 perk 等改写)
    growth: dict[str, float] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.cur_hp <= 0:
            self.cur_hp = self.base.get("hp", 1)

    # 技能上限为 8 条策略槽(主动+被动合计 ≤8,主动/被动各按行序,ADR-0011)。本期不接引擎逻辑。
    ARTIFACT_SLOTS = 4   # 装备槽 0..3(ADR-0009)

    def effective_skills(self) -> list[str]:
        """单位当前可用技能 = 习得技能 + 装备赋予技能(ADR-0008)。

        习得技能随定义常驻;装备赋予技能由 granted_skills 承载,装/卸装备时重算。
        """
        return list(self.skills) + list(self.granted_skills)

    def grant_tags_from_artifacts(self, artifact_defs: dict[str, Artifact]) -> None:
        """装备附带词条(tag_grant)合并进单位词条集合(ADR-0009)。

        装备按 def_id 以库存计数存储:self.artifacts 存 def_id 列表(槽位 0..3),
        直接按 def_id 查 artifact_defs。def_id 缺失时跳过(脏数据容忍)。
        """
        for def_id in self.artifacts:
            art = artifact_defs.get(def_id)
            if not art:
                continue
            for e in art.effects:
                if e.get("type") == "tag_grant":
                    self.tags.add(e["params"]["tag"])

    def occupy(self) -> int:
        """编入部队消耗的领导力点数。恒定,不随等级增长。"""
        return int(self.base.get("occupy", 1))

    def leadership(self) -> int:
        """队长属性,决定部队可承载的占用总和。普通单位为 0。"""
        return int(self.base.get("leadership", 0))

    def gain_xp(self, amount: int) -> int:
        """获得经验并升级,把成长烘进 base。返回升了几级。

        XP 纯整数守恒:溢出的 XP 原样保留到下一级(3/5 +5 -> 升级扣5 -> 3/10)。
        升级时 HP 按比例保留(不回满):cur_hp = floor(new_max * cur_hp / old_max),
        即升级提升血量上限但保留当前伤势比例。
        """
        if self.level >= LEVEL_CAP:
            return 0
        self.xp += amount
        levels_gained = 0
        while self.level < LEVEL_CAP and self.xp >= xp_to_next(self.level):
            self.xp -= xp_to_next(self.level)
            self.level += 1
            self._apply_growth()
            levels_gained += 1
        return levels_gained

    def _apply_growth(self) -> None:
        """升一级:按增长率把成长烘进 base,每属性 floor。
        occupy 不增长(从 growth 中跳过);其余属性按 growth 值累加后 floor。
        HP 按比例保留(不回满):升级提升血量上限,但保留当前伤势比例。"""
        old_max = self.base.get("hp", 1)
        old_cur = self.cur_hp
        for attr, rate in self.growth.items():
            if attr == "occupy" or rate == 0:
                continue
            old_val = self.base.get(attr, 0.0)
            new_val = math.floor(old_val + rate)
            self.base[attr] = float(new_val)
        # HP 按比例保留(纯整数运算,无中间小数)
        new_max = self.base.get("hp", old_max)
        if new_max > 0 and old_max > 0:
            self.cur_hp = float(math.floor(new_max * old_cur / old_max))
        else:
            self.cur_hp = new_max

    def describe(self) -> str:
        tagstr = "/".join(TAG_CN.get(t, t) for t in sorted(self.tags))
        return (f"{self.name}[{tagstr}] HP:{int(self.cur_hp)}/{int(self.base.get('hp', 1))} "
                f"速:{int(self.base.get('speed', 0))} 物攻:{int(self.base.get('p_atk', 0))} "
                f"Lv{self.level}")
