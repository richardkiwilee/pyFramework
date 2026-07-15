"""示例游戏状态，供 Tab 状态总览 overlay 显示。

这是框架为"游戏"预留的状态对象；真实游戏会扩展更多字段。这里用样例值填充，
演示框架能渲染 HP/MP 条、金币、位置等状态型 UI。
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class GameState:
    name: str = "艾尔登·旅人"
    level: int = 12
    hp: int = 86
    max_hp: int = 120
    mp: int = 34
    max_mp: int = 60
    gold: int = 1540
    location: str = "幽暗森林 · 残碑营地"
    inventory_count: int = 18
    quest_progress: str = "主线 3/8 · 寻找三块命运碎片"


# 全局单例（demo 用；真实游戏应由 App 持有）
_state = GameState()


def get_state() -> GameState:
    return _state
