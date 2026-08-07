"""
事件系统:回合开始随机触发的选择支。

事件定义来自 data/events.json。每个事件有若干选项,选项效果调整信念或资源。
原型 2 个示例事件:流民 / 商队。
"""
from __future__ import annotations
import random
from dataclasses import dataclass, field
from typing import Any

from .economy import Resources, Belief, BELIEF_CN, RESOURCE_CN, SOURCE_EVENT


@dataclass
class EventOption:
    label: str
    effects: dict[str, Any]  # {belief: {dim: delta}, resources: {k: v}}


@dataclass
class GameEvent:
    id: str
    title: str
    text: str
    options: list[EventOption]


def load_events(event_defs: dict) -> list[GameEvent]:
    events: list[GameEvent] = []
    for eid, d in event_defs.items():
        opts = [EventOption(label=o["label"], effects=o.get("effects", {}))
                for o in d.get("options", [])]
        events.append(GameEvent(id=eid, title=d["title"], text=d["text"], options=opts))
    return events


def apply_option(opt: EventOption, resources: Resources, belief: Belief) -> str:
    """应用选项效果,返回结果描述。"""
    parts: list[str] = []
    eff = opt.effects
    for dim, delta in eff.get("belief", {}).items():
        belief.change(dim, int(delta))
        parts.append(f"{BELIEF_CN.get(dim, dim)} {delta:+d}")
    for k, v in eff.get("resources", {}).items():
        # §2 delta:事件结算记来源 event
        resources.add(k, int(v), source=SOURCE_EVENT)
        parts.append(f"{RESOURCE_CN.get(k, k)} {int(v):+d}")
    return "、".join(parts) if parts else "无变化"


def random_event(events: list[GameEvent]) -> GameEvent | None:
    if not events:
        return None
    return random.choice(events)
