"""动作（Action）抽象：把原始按键抽象成语义动作。

场景只认 Action，不认原始键码。加新键 = 加一条绑定，不改场景。
CHAR 动作携带一个可打印字符（用于百科输入框）。
"""
from __future__ import annotations

from dataclasses import dataclass


# 用常量字符串作为动作标识，便于 json 序列化与比较
UP = "up"
DOWN = "down"
LEFT = "left"
RIGHT = "right"
SELECT = "select"        # 空格：选中/反选
CONFIRM = "confirm"      # 回车：确认/执行
BACK = "back"            # Esc：退出当前场景
BACKSPACE = "backspace"  # 退格：删字符（输入框用）
OPEN_WIKI = "open_wiki"  # H：进入百科
SCROLL_UP = "scroll_up"   # PgUp
SCROLL_DOWN = "scroll_down"  # PgDn
CHAR = "char"            # 可打印字符输入（携带 .char）

ALL_ACTIONS = (
    UP, DOWN, LEFT, RIGHT, SELECT, CONFIRM, BACK, BACKSPACE,
    OPEN_WIKI, SCROLL_UP, SCROLL_DOWN, CHAR,
)


@dataclass(frozen=True)
class InputEvent:
    """一个输入事件：动作 + 可选字符（仅 CHAR 动作有 char）。"""
    action: str
    char: str = ""

    @property
    def is_char(self) -> bool:
        return self.action == CHAR
