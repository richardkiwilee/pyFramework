"""底部日志栏：环形缓冲，存最近若干条消息。

场景执行动作后把结果字符串 push 进来；主场景底部日志栏渲染 recent()。
warn=True 的条目（通常是 "失败:..."）用警告色显示。

§6 日志全球化：日志栏不应只在大地图界面出现，应任何时候都出现，便于玩家在某界面
执行操作无反应时立刻看到原因。render_log_bar() 提供共享渲染：在任意场景的 render()
末尾调用，把最近 3 条日志画进一行（与 game_scene._render_log 同口径）。
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


def render_log_bar(buf, x: int, y: int, w: int) -> None:
    """在 (x, y) 起的一行画日志栏（§6 共享渲染）。最近 3 条，warn 用警告色。

    与 game_scene._render_log 同口径，供各子场景在自身 render() 末尾调用，
    使日志在任意界面都可见。
    """
    from pyconsole.io import theme
    from pyconsole.io.width import text_width
    from pyconsole.io.widgets import put_truncated
    buf.fill_rect(x, y, w, 1, " ", theme.DIM, theme.BG)
    buf.put_text(x, y, "日志", theme.ACCENT, theme.BG)
    msgs = recent(3)
    if not msgs:
        buf.put_text(x + 4, y, "（无）", theme.DIM, theme.BG)
        return
    cx = x + 4
    for i, (text, warn) in enumerate(msgs):
        if i > 0:
            if cx + text_width(" │ ") >= x + w:
                break
            cx = buf.put_text(cx, y, " │ ", theme.DIM, theme.BG)
        fg = theme.WARN if warn else theme.DIM
        trunc = (x + w) - cx
        if trunc <= 1:
            break
        cx = put_truncated(buf, cx, y, text, trunc, fg, theme.BG)
