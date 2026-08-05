"""键绑定：原始键名 → 动作的映射，支持 keybindings.json 覆盖默认。

- DEFAULT_BINDINGS：代码内置默认（key_name → action）。
- load_bindings(path)：读 json 覆盖默认；文件缺失或损坏返回默认。
- KeyResolver：把 (key_name, char) 解析成 InputEvent。
"""
from __future__ import annotations

import json
import os

from . import actions
from .actions import InputEvent


# 默认键绑定：key_name -> action
DEFAULT_BINDINGS: dict[str, str] = {
    "up": actions.UP,
    "down": actions.DOWN,
    "left": actions.LEFT,
    "right": actions.RIGHT,
    "space": actions.SELECT,
    "enter": actions.CONFIRM,
    "escape": actions.BACK,
    "backspace": actions.BACKSPACE,
    "h": actions.OPEN_WIKI,
    "page_up": actions.SCROLL_UP,
    "page_down": actions.SCROLL_DOWN,
    # tab 不在这里绑定：Tab 由 overlay 直接消费（GetAsyncKeyState 轮询）
}

# 可映射成 CHAR 的键名（未在 DEFAULT_BINDINGS 中显式绑定的可打印字符）
_CHAR_KEYS = set("abcdefghijklmnopqrstuvwxyz0123456789"
                 "ABCDEFGHIJKLMNOPQRSTUVWXYZ,./;'[]\\-=`")

# 这些键名即使没绑定也绝不产生 CHAR（避免把控制键当输入）
_NON_CHAR_KEYS = {
    "space", "enter", "escape", "backspace", "tab",
    "up", "down", "left", "right",
    "page_up", "page_down", "home", "end",
    "insert", "delete",
}


def load_bindings(path: str | None = None) -> dict[str, str]:
    """加载键绑定：默认 + json 覆盖。

    json 格式：{"up": "down", "space": "confirm", ...}（key_name -> action）。
    文件不存在 / 解析失败 / 值非法 → 回退默认，不抛异常。
    """
    bindings = dict(DEFAULT_BINDINGS)
    if not path or not os.path.isfile(path):
        return bindings
    try:
        with open(path, "r", encoding="utf-8") as f:
            override = json.load(f)
        if not isinstance(override, dict):
            return bindings
        for k, v in override.items():
            if not isinstance(k, str) or not isinstance(v, str):
                continue
            if v not in actions.ALL_ACTIONS:
                continue
            bindings[k] = v
    except (OSError, json.JSONDecodeError):
        pass
    return bindings


class KeyResolver:
    """把 (key_name, char) 解析成 InputEvent。"""

    def __init__(self, bindings: dict[str, str] | None = None) -> None:
        self.bindings = bindings if bindings is not None else dict(DEFAULT_BINDINGS)

    def resolve(self, key_name: str, char: str) -> InputEvent | None:
        # 1. 显式绑定优先
        if key_name in self.bindings:
            action = self.bindings[key_name]
            if action == actions.CHAR and char:
                return InputEvent(actions.CHAR, char)
            return InputEvent(action, "")
        # 2. 可打印字符且未被列为非字符键 → CHAR
        if key_name == "char" and char:
            # 字符本身可能被绑定（如 'h'）；查小写形式
            lower = char.lower()
            if lower in self.bindings:
                return InputEvent(self.bindings[lower], "")
            if lower in _CHAR_KEYS:
                return InputEvent(actions.CHAR, char)
        # 3. 其他未识别按键
        return None
