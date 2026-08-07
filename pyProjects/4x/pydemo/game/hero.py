"""
英雄单位:精心设计的特殊单位,有被动/技能。

招募消耗资源 + 信念门槛(某维信念 >= 某值)。
每个据点独立刷新可招募英雄池,每 14 天(一个月相周期)刷新一次,每次 3 个。
"""
from __future__ import annotations
import random
from dataclasses import dataclass, field
from typing import Any

from .unit import Unit
from .economy import Belief, BELIEF_CN


@dataclass
class HeroDef:
    """英雄定义(data/heroes.json)。"""
    id: str
    name: str
    tags: set[str]
    base: dict[str, float]
    skills: list[str]               # 技能 id 列表
    recruit_cost: dict[str, int]    # 招募资源消耗
    belief_req: dict[str, int]      # 信念门槛 {dim: threshold}
    growth: dict[str, float] = field(default_factory=dict)   # 各属性增长率
    maintenance: dict[str, int] = field(default_factory=dict)   # 每回合维护费;缺省走原型默认(英雄 4 倍)
    train_cost: dict[str, int] = field(default_factory=dict)    # 训练消耗;缺省走原型默认(按其定义)
    desc: str = ""


def load_hero_defs(d: dict) -> dict[str, HeroDef]:
    out: dict[str, HeroDef] = {}
    for hid, h in d.items():
        out[hid] = HeroDef(
            id=hid, name=h["name"], tags=set(h.get("tags", ["melee", "human"])),
            base=h.get("base", {}), growth=h.get("growth", {}),
            skills=h.get("skills", []),
            recruit_cost=h.get("recruit_cost", {}),
            belief_req=h.get("belief_req", {}),
            maintenance=h.get("maintenance", {}),
            train_cost=h.get("train_cost", {}),
            desc=h.get("desc", ""),
        )
    return out


def make_hero_unit(hero_def: HeroDef) -> Unit:
    """从英雄定义构造一个英雄单位实例。"""
    return Unit(
        id=f"{hero_def.id}_{random.randint(1000, 9999)}",
        type_id=hero_def.id,
        name=hero_def.name,
        tags=set(hero_def.tags),
        base=dict(hero_def.base),
        growth=dict(hero_def.growth),
        is_hero=True,
        skills=list(hero_def.skills),
    )


def meets_belief_req(belief: Belief, req: dict[str, int]) -> bool:
    return all(belief.get(dim) >= thr for dim, thr in req.items())


def describe_req(req: dict[str, int]) -> str:
    return "、".join(f"{BELIEF_CN.get(d, d)}>={v}" for d, v in req.items()) if req else "无"


@dataclass
class RecruitmentPool:
    """某据点的可招募英雄池。

    offerings 为**固定 3 槽**列表：每个槽位要么是 hero_def id，要么是 None
    （已被招募/未刷新出的空位）。招募把对应槽位置 None，**不压缩**其余英雄，
    故三窗口与槽位一一对应，被招募的窗口才空，其余英雄原位保留。每 14 天
    refresh 重新随机填满 3 槽。
    """
    stronghold_id: str
    offerings: list[str] = field(default_factory=list)   # 固定 3 槽：hero_def id 或 None
    refresh_day: int = 1            # 下次刷新的天数

    def refresh(self, all_hero_ids: list[str], current_day: int, calendar_period: int = 14) -> None:
        """刷新为 3 个固定槽位。不足 3 个英雄定义时用 None 占位补足。"""
        ids = list(all_hero_ids)
        n = min(3, len(ids))
        # random.sample(k=0) 合法返回 []；此处始终产出长度恰为 3 的列表
        self.offerings = random.sample(ids, n) + [None] * (3 - n)
        self.refresh_day = current_day + calendar_period
