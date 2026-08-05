"""后缓冲：单元格 + 帧缓冲。

双缓冲的核心：所有场景渲染先写进 FrameBuffer（后缓冲），再由 Display 与上一帧
diff 后输出到终端。本模块只管"画进缓冲"，不管输出。
"""
from __future__ import annotations

from dataclasses import dataclass, field

from . import theme
from .width import char_width, text_width


@dataclass
class Cell:
    """一个终端单元格：字符 + 前景 + 背景。

    双宽字符占两个 Cell：第一个存字符，第二个 char 设为 ""（占位，不渲染字符）。
    diff 时按位置比较三字段。
    """
    char: str = " "
    fg: int = theme.FG
    bg: int = theme.BG

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Cell):
            return NotImplemented
        return self.char == other.char and self.fg == other.fg and self.bg == other.bg

    def __hash__(self) -> int:  # 仅为消除 dataclass(eq=True) 警告
        return hash((self.char, self.fg, self.bg))


class FrameBuffer:
    """后缓冲：w x h 的单元格矩阵。原点 (0,0) 在左上角。"""

    def __init__(self, w: int, h: int) -> None:
        self.w = w
        self.h = h
        self.cells: list[list[Cell]] = self._blank()

    def _blank(self) -> list[list[Cell]]:
        return [[Cell() for _ in range(self.w)] for _ in range(self.h)]

    def clear(self, ch: str = " ", fg: int = theme.FG, bg: int = theme.BG) -> None:
        """清空整个缓冲为指定字符/颜色。"""
        for y in range(self.h):
            row = self.cells[y]
            for x in range(self.w):
                row[x] = Cell(ch, fg, bg)

    def in_bounds(self, x: int, y: int) -> bool:
        return 0 <= x < self.w and 0 <= y < self.h

    def set_char(self, x: int, y: int, ch: str, fg: int = theme.FG, bg: int = theme.BG) -> None:
        """在 (x,y) 写一个字符。双宽字符的占位格需调用方处理（put_text 已处理）。"""
        if not self.in_bounds(x, y):
            return
        # 只取第一个字符，防止误写多字符
        if len(ch) > 1:
            ch = ch[0]
        self.cells[y][x] = Cell(ch, fg, bg)

    def put_text(self, x: int, y: int, text: str, fg: int = theme.FG, bg: int = theme.BG) -> int:
        """从 (x,y) 起写一段文本，自动处理双宽字符。

        双宽字符写入后，其右侧一格用占位 Cell（char=""）标记，避免被后续覆盖。
        超出右边界的字符被截断（双宽字符若无法完整放下则整字跳过）。
        返回写完后的下一个 x 坐标。
        """
        if not self.in_bounds(x, y) or y < 0 or y >= self.h:
            return x
        row = self.cells[y]
        cx = x
        for ch in text:
            w = char_width(ch)
            if w == 0:
                continue  # 零宽字符跳过
            if cx >= self.w:
                break  # 超出右边界
            if w == 2:
                # 双宽字符需占两格；若只剩一格放不下，整字跳过
                if cx + 1 >= self.w:
                    break
                row[cx] = Cell(ch, fg, bg)
                row[cx + 1] = Cell("", fg, bg)  # 占位
                cx += 2
            else:
                row[cx] = Cell(ch, fg, bg)
                cx += 1
        return cx

    def fill_rect(self, x: int, y: int, w: int, h: int, ch: str = " ",
                  fg: int = theme.FG, bg: int = theme.BG) -> None:
        """填充矩形区域。"""
        for ry in range(y, y + h):
            if ry < 0 or ry >= self.h:
                continue
            for rx in range(x, x + w):
                if rx < 0 or rx >= self.w:
                    continue
                self.cells[ry][rx] = Cell(ch, fg, bg)

    def get(self, x: int, y: int) -> Cell | None:
        if not self.in_bounds(x, y):
            return None
        return self.cells[y][x]
