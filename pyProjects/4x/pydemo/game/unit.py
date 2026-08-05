"""
单位与兵种词条。

兵种词条分两类,全部平级:必选大类(近战/远程/魔法,至少其一,可多选)
与枚举小类(人类/骑兵等,可多选)。词条是修正源与羁绊的输入。

单位属性:规模/生命值/行动点/魔力点/行动速度/物攻/魔攻/物防/魔防/
命中/闪避/格挡/暴击率/幸运/意志。

单位可装备至多 3 个神器。神器可附带词条(tag_grant),是修正源与羁绊来源。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

# 必选大类
MAJOR_TAGS = {"melee", "ranged", "magic"}
TAG_CN = {
    "melee": "近战", "ranged": "远程", "magic": "魔法",
    "human": "人类", "cavalry": "骑兵",
    "archer": "弓兵",
}

# 单位基础属性及其上下界(用于修正管道 clamp)
UNIT_ATTRS = [
    "size", "hp", "ap", "mana", "speed",
    "p_atk", "m_atk", "p_def", "m_def",
    "acc", "eva", "block", "crit", "luck", "will",
]
ATTR_BOUNDS: dict[str, tuple[float, float]] = {
    "hp": (0, 99999), "ap": (0, 99), "mana": (0, 99), "speed": (1, 999),
    "size": (1, 99), "p_atk": (0, 9999), "m_atk": (0, 9999),
    "p_def": (0, 9999), "m_def": (0, 9999),
    "acc": (0, 100), "eva": (0, 100), "block": (0, 100),
    "crit": (0, 100), "luck": (0, 100), "will": (0, 999),
    "mana_regen": (0, 999),
}
ATTR_CN = {
    "hp": "生命", "ap": "行动点", "mana": "魔力", "speed": "速度",
    "p_atk": "物攻", "m_atk": "魔攻", "p_def": "物防", "m_def": "魔防",
    "acc": "命中", "eva": "闪避", "block": "格挡", "crit": "暴击",
    "luck": "幸运", "will": "意志", "size": "规模", "mana_regen": "魔力恢复",
}


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
    desc: str = ""


def load_unit_types(d: dict) -> dict[str, UnitType]:
    out: dict[str, UnitType] = {}
    for uid, u in d.items():
        tags = set(u.get("tags", []))
        validate_tags(tags)
        out[uid] = UnitType(
            id=uid, name=u["name"], tags=tags,
            recruit_cost=u.get("recruit_cost", {}),
            base=u.get("base", {}), desc=u.get("desc", ""),
        )
    return out


@dataclass
class Artifact:
    """神器定义。可加属性或附带词条(tag_grant)。"""
    id: str
    name: str
    effects: list[dict] = field(default_factory=list)   # 同 skills 的 effect 原始 dict


def load_artifacts(d: dict) -> dict[str, Artifact]:
    out: dict[str, Artifact] = {}
    for aid, a in d.items():
        out[aid] = Artifact(id=aid, name=a["name"], effects=a.get("effects", []))
    return out


@dataclass
class Unit:
    """一个单位实例。"""
    id: str
    type_id: str
    name: str
    tags: set[str]                  # 含兵种词条 + 神器赋予的词条
    base: dict[str, float]          # 基础属性(招募时确定,不含修正)
    artifacts: list[str] = field(default_factory=list)   # 装备的神器 id,最多 3
    is_hero: bool = False
    skills: list[str] = field(default_factory=list)     # 技能 id(英雄)
    cur_hp: float = 0               # 当前生命
    army_id: str | None = None      # 所属部队
    # 战斗内临时状态
    cur_ap: float = 0
    cur_mana: float = 0
    atb: float = 0                  # 行动条(0..100)
    alive: bool = True
    # 当前所在结点
    node_id: str | None = None

    def __post_init__(self) -> None:
        if self.cur_hp <= 0:
            self.cur_hp = self.base.get("hp", 1)

    def grant_tags_from_artifacts(self, artifact_defs: dict[str, Artifact]) -> None:
        """神器附带词条(tag_grant)合并进单位词条集合。"""
        for aid in self.artifacts:
            art = artifact_defs.get(aid)
            if not art:
                continue
            for e in art.effects:
                if e.get("type") == "tag_grant":
                    self.tags.add(e["params"]["tag"])

    def describe(self) -> str:
        tagstr = "/".join(TAG_CN.get(t, t) for t in sorted(self.tags))
        return (f"{self.name}[{tagstr}] HP:{int(self.cur_hp)}/{int(self.base.get('hp', 1))} "
                f"速:{int(self.base.get('speed', 0))} 物攻:{int(self.base.get('p_atk', 0))}")
