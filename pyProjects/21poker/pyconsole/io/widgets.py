"""渲染小部件：边框、文本、列表、输入框、进度条、底部提示栏等。

所有小部件都画进传入的 FrameBuffer，不直接输出。统一处理双宽对齐。
"""
from __future__ import annotations

from ..io.buffer import FrameBuffer
from ..io import theme
from ..io.width import text_width


def draw_box(buf: FrameBuffer, x: int, y: int, w: int, h: int,
             title: str = "", fg: int = theme.BORDER, bg: int = theme.BG) -> None:
    """画一个 box-drawing 边框矩形，可选标题（嵌入顶边）。"""
    if w < 2 or h < 2:
        return
    x2 = x + w - 1
    y2 = y + h - 1
    # 四角
    buf.set_char(x, y, "┌", fg, bg)
    buf.set_char(x2, y, "┐", fg, bg)
    buf.set_char(x, y2, "└", fg, bg)
    buf.set_char(x2, y2, "┘", fg, bg)
    # 水平边
    for cx in range(x + 1, x2):
        buf.set_char(cx, y, "─", fg, bg)
        buf.set_char(cx, y2, "─", fg, bg)
    # 垂直边
    for cy in range(y + 1, y2):
        buf.set_char(x, cy, "│", fg, bg)
        buf.set_char(x2, cy, "│", fg, bg)
    # 标题嵌入顶边
    if title:
        label = f" {title} "
        tx = x + 2
        buf.put_text(tx, y, label, theme.HEADING, bg)


def fill_rect(buf: FrameBuffer, x: int, y: int, w: int, h: int,
              ch: str = " ", fg: int = theme.FG, bg: int = theme.BG) -> None:
    buf.fill_rect(x, y, w, h, ch, fg, bg)


def put_centered(buf: FrameBuffer, y: int, text: str, w: int,
                  fg: int = theme.FG, bg: int = theme.BG) -> None:
    """在宽度 w 的区域里把 text 居中放在第 y 行。"""
    tw = text_width(text)
    x = max(0, (w - tw) // 2)
    buf.put_text(x, y, text, fg, bg)


def put_truncated(buf: FrameBuffer, x: int, y: int, text: str, max_w: int,
                  fg: int = theme.FG, bg: int = theme.BG) -> int:
    """从 (x,y) 写文本，超出 max_w 宽度则截断并加省略号。返回结束 x。"""
    if text_width(text) <= max_w:
        return buf.put_text(x, y, text, fg, bg)
    # 逐步写入直到放不下
    ell = "…"
    ell_w = 1
    limit = max_w - ell_w
    cx = x
    written = 0
    for ch in text:
        from ..io.width import char_width
        cw = char_width(ch)
        if written + cw > limit:
            break
        buf.put_text(cx, y, ch, fg, bg)
        cx += cw
        written += cw
    buf.put_text(cx, y, ell, theme.DIM, bg)
    return cx + ell_w


def draw_bar(buf: FrameBuffer, x: int, y: int, w: int, value: int, maximum: int,
             fill_fg: int = theme.ACCENT, bg: int = theme.BG) -> None:
    """画一个 [####----] 风格的进度条。"""
    buf.put_text(x, y, "[", theme.DIM, bg)
    buf.put_text(x + w - 1, y, "]", theme.DIM, bg)
    inner = w - 2
    if maximum <= 0:
        ratio = 0.0
    else:
        ratio = max(0.0, min(1.0, value / maximum))
    filled = int(round(inner * ratio))
    for i in range(inner):
        if i < filled:
            buf.set_char(x + 1 + i, y, "█", fill_fg, bg)
        else:
            buf.set_char(x + 1 + i, y, "·", theme.DIM, bg)


def draw_hints(buf: FrameBuffer, y: int, w: int, hints: list[str]) -> None:
    """在底部第 y 行画键提示栏（横排，用 · 分隔）。"""
    fill_rect(buf, 0, y, w, 1, " ", theme.DIM, theme.BG)
    text = "  " + "  ·  ".join(hints)
    buf.put_text(0, y, text, theme.DIM, theme.BG)


def draw_input_field(buf: FrameBuffer, x: int, y: int, w: int, value: str,
                     prompt: str = "", fg: int = theme.FG, bg: int = theme.BG) -> None:
    """画一个输入框：[prompt][value____]，末尾用反色块示意光标位置。"""
    px = x
    if prompt:
        px = buf.put_text(x, y, prompt, theme.ACCENT, bg)
    # value 区背景
    inner_x = px
    inner_w = w - (px - x)
    fill_rect(buf, inner_x, y, inner_w, 1, " ", fg, theme.SELECTED_BG)
    end = buf.put_text(inner_x, y, value, theme.SELECTED_FG, theme.SELECTED_BG)
    # 末尾追加式光标：反色块
    if end < inner_x + inner_w:
        buf.set_char(end, y, "▏", theme.ACCENT2, theme.SELECTED_BG)


def highlight_text(buf: FrameBuffer, x: int, y: int, text: str, query: str,
                   base_fg: int, base_bg: int,
                   hl_fg: int = theme.HIGHLIGHT_FG, hl_bg: int = theme.HIGHLIGHT_BG) -> int:
    """写文本，把与 query（大小写不敏感）匹配的子串高亮。返回结束 x。"""
    if not query:
        return buf.put_text(x, y, text, base_fg, base_bg)
    from ..data.wiki_data import find_match_ranges
    ranges = find_match_ranges(text, query)
    if not ranges:
        return buf.put_text(x, y, text, base_fg, base_bg)
    cx = x
    i = 0
    n = len(text)
    while i < n:
        # 找到从 i 开始的匹配
        hit = None
        for (s, e) in ranges:
            if s == i:
                hit = (s, e)
                break
        if hit:
            s, e = hit
            seg = text[s:e]
            cx = buf.put_text(cx, y, seg, hl_fg, hl_bg)
            i = e
        else:
            cx = buf.put_text(cx, y, text[i], base_fg, base_bg)
            i += 1
    return cx
