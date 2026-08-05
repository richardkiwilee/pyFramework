"""
羁绊(Synergy):部队中凑齐复数个相同兵种词条触发。

两种形态:
  - tag_flat: 拥有该词条的兵种每人 +flat 属性(同词条凑数即给所有拥有者)
  - tier_bonus: 按词条数量分档,触发档位奖励只给本人
原型定义来自 data/synergies.json。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

from .modifier import Modifier, ModifierSource
from .unit import Unit


@dataclass
class SynergyDef:
    id: str
    tag: str                 # 触发词条
    kind: str                # tag_flat | tier_bonus
    attr: str = ""
    per_unit_value: float = 0.0   # tag_flat: 每单位加成
    tiers: list[dict] = field(default_factory=list)  # tier_bonus: [{count, attr, value, op}]


def load_synergies(d: dict) -> dict[str, SynergyDef]:
    out: dict[str, SynergyDef] = {}
    for sid, s in d.items():
        out[sid] = SynergyDef(
            id=sid, tag=s["tag"], kind=s.get("kind", "tag_flat"),
            attr=s.get("attr", ""), per_unit_value=float(s.get("per_unit_value", 0)),
            tiers=s.get("tiers", []),
        )
    return out


def collect_synergy_mods(
    army_tags_count: dict[str, int],
    army_units: list[Unit],
    synergy_defs: dict[str, SynergyDef],
) -> list[Modifier]:
    """
    根据部队中各词条数量,生成作用于每个单位的修正。
    tag_flat: 凡拥有该词条的单位,获得 per_unit_value(可随数量放大,原型简化为每多1个+value)
    tier_bonus: 按数量达到的档位,奖励只给本人(原型:给所有拥有该词条的单位,作为简化)
    """
    mods: list[Modifier] = []
    for syn in synergy_defs.values():
        count = army_tags_count.get(syn.tag, 0)
        if count < 2:    # 凑齐复数个(>=2)才触发
            continue
        holders = [u for u in army_units if syn.tag in u.tags]
        if syn.kind == "tag_flat":
            # 每个拥有者获得 per_unit_value * (count-1)(随凑数放大)
            val = syn.per_unit_value * (count - 1)
            for u in holders:
                mods.append(Modifier(ModifierSource.SYNERGY, syn.id, u.id,
                                     syn.attr, val, op="flat"))
        elif syn.kind == "tier_bonus":
            # 找到 count 达到的最高档位
            best = None
            for t in syn.tiers:
                if count >= t["count"]:
                    best = t
            if best:
                for u in holders:
                    mods.append(Modifier(ModifierSource.SYNERGY, syn.id, u.id,
                                         best["attr"], float(best["value"]),
                                         op=best.get("op", "flat")))
    return mods
