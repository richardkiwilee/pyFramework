"""底部日志栏：环形缓冲，存最近若干条消息。

场景执行动作后把结果字符串 push 进来；主场景底部日志栏渲染 recent()。
warn=True 的条目（通常是 "失败:..."）用警告色显示。
"""
from __future__ import annotations

_MAX = 50
_messages: list[tuple[str, bool]] = []


def push(msg: str, warn: bool = False) -> None:
    """追加一条日志。warn=True 表示错误/警告（如动作返回的"失败:..."）。"""
    if not msg:
        return
    _messages.append((msg, warn))
    if len(_messages) > _MAX:
        del _messages[: len(_messages) - _MAX]


def recent(n: int = 3) -> list[tuple[str, bool]]:
    """最近 n 条 (text, warn)。"""
    return _messages[-n:] if n > 0 else []


def clear() -> None:
    _messages.clear()


def all_messages() -> list[tuple[str, bool]]:
    return list(_messages)
