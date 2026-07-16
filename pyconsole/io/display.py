"""显示层：双缓冲 diff 渲染 + 终端生命周期管理。

渲染流程：
  display.begin_frame()        # 清后缓冲
  ... 场景写后缓冲 ...
  display.present(front)      # 与上一帧 diff 后输出，返回新的 front 快照

首帧（front 为 None）或尺寸变化时整屏重画；否则只输出变化的单元格（单元格级 diff），
以最小化输出、避免闪烁。
"""
from __future__ import annotations

import ctypes
import sys
from ctypes import wintypes

from .buffer import Cell, FrameBuffer
from . import theme


# ---- Windows Console VT 启用 ----
ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
ENABLE_PROCESSED_OUTPUT = 0x0001
INVALID_HANDLE_VALUE = -1
STD_OUTPUT_HANDLE = -11


def _enable_vt() -> bool:
    """在 Windows 上启用 VT 处理，返回是否成功。失败返回 False（fallback）。"""
    if sys.platform != "win32":
        return False
    try:
        kernel32 = ctypes.windll.kernel32
        kernel32.GetStdHandle.restype = wintypes.HANDLE
        handle = kernel32.GetStdHandle(wintypes.DWORD(STD_OUTPUT_HANDLE))
        if not handle or handle == wintypes.HANDLE(INVALID_HANDLE_VALUE):
            return False
        mode = wintypes.DWORD(0)
        if not kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            return False
        new_mode = mode.value | ENABLE_VIRTUAL_TERMINAL_PROCESSING | ENABLE_PROCESSED_OUTPUT
        if not kernel32.SetConsoleMode(handle, wintypes.DWORD(new_mode)):
            return False
        return True
    except Exception:
        return False


def _ensure_utf8() -> bool:
    """把 stdout 切到 UTF-8，返回是否成功。"""
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        return True
    except Exception:
        return False


class Display:
    """管理后缓冲、diff 输出与终端状态。"""

    def __init__(self, w: int, h: int) -> None:
        self.w = w
        self.h = h
        self.buf = FrameBuffer(w, h)
        self._front: FrameBuffer | None = None  # 上一帧（前缓冲快照）
        self.vt_ok = False
        self.utf8_ok = False

    # ---- 终端生命周期 ----
    def startup(self) -> None:
        self.vt_ok = _enable_vt()
        self.utf8_ok = _ensure_utf8()
        # 切换到备用屏幕缓冲，避免污染用户历史输出（可选但更干净）
        sys.stdout.write("\x1b[?1049h")
        self.hide_cursor()

    def cleanup(self) -> None:
        """恢复终端状态：重置颜色、显示光标、清屏、切回主缓冲。

        先清屏再切回主缓冲：在不支持备用屏幕缓冲的终端（conhost 传统模式）上，
        ``?1049l`` 会被忽略，渲染内容会残留在主缓冲，故显式清一次屏（等效 cls）。
        """
        try:
            sys.stdout.write(theme.RESET)
            self.show_cursor()
            sys.stdout.write("\x1b[2J\x1b[H")  # 清屏 + 光标归位（等效 cls）
            sys.stdout.write("\x1b[?1049l")    # 切回主缓冲
            sys.stdout.flush()
        except Exception:
            pass

    def hide_cursor(self) -> None:
        sys.stdout.write("\x1b[?25l")

    def show_cursor(self) -> None:
        sys.stdout.write("\x1b[?25h")

    # ---- 帧缓冲 ----
    def begin_frame(self) -> FrameBuffer:
        """清空后缓冲，返回它供场景绘制。"""
        self.buf.clear()
        return self.buf

    def present(self) -> None:
        """把后缓冲 diff 输出到终端。"""
        back = self.buf
        front = self._front
        out: list[str] = []
        if front is None or front.w != back.w or front.h != back.h:
            # 首帧 / 尺寸变化：整屏重画
            out.append("\x1b[H")  # 光标归位
            for y in range(back.h):
                row = back.cells[y]
                cur_fg = cur_bg = -1
                for x in range(back.w):
                    cell = row[x]
                    if cell.char == "":
                        continue  # 占位格跳过
                    if cell.fg != cur_fg or cell.bg != cur_bg:
                        out.append(f"\x1b[{theme.sgr(cell.fg, cell.bg)}m")
                        cur_fg, cur_bg = cell.fg, cell.bg
                    out.append(cell.char)
                if y < back.h - 1:
                    out.append("\r\n")
            out.append(theme.RESET)
        else:
            # 单元格级 diff：只输出变化格
            for y in range(back.h):
                brow = back.cells[y]
                frow = front.cells[y]
                for x in range(back.w):
                    bcell = brow[x]
                    if bcell == frow[x]:
                        continue
                    if bcell.char == "":
                        continue  # 占位格不单独输出
                    out.append(f"\x1b[{y + 1};{x + 1}H")
                    out.append(f"\x1b[{theme.sgr(bcell.fg, bcell.bg)}m")
                    out.append(bcell.char)
            out.append(theme.RESET)
        data = "".join(out)
        sys.stdout.write(data)
        sys.stdout.flush()
        # 后缓冲 → front 快照
        self._front = self._snapshot(back)

    def _snapshot(self, src: FrameBuffer) -> FrameBuffer:
        """深拷贝一帧作为下一次 diff 的前缓冲。"""
        snap = FrameBuffer(src.w, src.h)
        for y in range(src.h):
            srow = src.cells[y]
            drow = snap.cells[y]
            for x in range(src.w):
                c = srow[x]
                drow[x] = Cell(c.char, c.fg, c.bg)
        return snap
