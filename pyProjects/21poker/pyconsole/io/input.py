"""输入层：从 msvcrt 读原始按键 + Tab 按住状态轮询。

Windows 专属（msvcrt）。方向键 / 功能键在 msvcrt 下是两字节序列：
  0xe0 或 0x00 前缀 + 第二字节码。本模块只把字节流解析成可读的 key_name，
不映射成 Action（留给 core.keys.KeyResolver）。
"""
from __future__ import annotations

import ctypes
import msvcrt

# ---- GetAsyncKeyState 用于 Tab 按住检测 ----
VK_TAB = 0x09
_user32 = ctypes.windll.user32


def poll_tab_held() -> bool:
    """返回 Tab 是否正被物理按住（最高位为 1）。"""
    try:
        state = _user32.GetAsyncKeyState(VK_TAB)
        return bool(state & 0x8000)
    except Exception:
        return False


# 方向键 / 功能键第二字节码 → 可读名
_SPECIAL = {
    "H": "up", "P": "down", "K": "left", "M": "right",
    "I": "page_up", "Q": "page_down",
    "G": "home", "O": "end",
    "R": "insert", "S": "delete",
    ";": "f1", "<": "f2", "=": "f3", ">": "f4",
}

# 单字节按键 → 可读名
_SINGLE = {
    " ": "space",
    "\r": "enter",
    "\n": "enter",
    "\x1b": "escape",
    "\x08": "backspace",
    "\t": "tab",
}


def read_key() -> tuple[str, str] | None:
    """阻塞读一个按键，返回 (key_name, char)。

    - 普通可打印字符：("char", ch)
    - 控制键：("space"/"enter"/...)，char 为 ""
    - 无按键（配合 kbhit 调用）：返回 None
    """
    if not msvcrt.kbhit():
        return None
    b = msvcrt.getch()
    if b in (b"\x00", b"\xe0"):
        # 功能键序列
        if not msvcrt.kbhit():
            return None
        b2 = msvcrt.getch()
        name = _SPECIAL.get(chr(b2[0]), f"unknown_{b2[0]}")
        return (name, "")
    ch = chr(b[0])
    name = _SINGLE.get(ch)
    if name:
        return (name, ch)
    if 0x20 <= b[0] < 0x7F:
        # 可打印 ASCII
        return ("char", ch)
    return (f"unknown_{b[0]}", "")


def peek_key() -> tuple[str, str] | None:
    """非阻塞读一个按键（无键返回 None）。等价于 read_key（read_key 已非阻塞）。"""
    return read_key()
