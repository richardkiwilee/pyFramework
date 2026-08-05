"""字符宽度计算 —— 处理 CJK 全角/半角，保证双宽字符占两格。

所有写文本到缓冲的操作都必须经过本模块的宽度判定，否则中文会导致边框错位、
光标定位偏差。这是控制台中文渲染的关键不变量。
"""
from __future__ import annotations

import unicodedata


def char_width(ch: str) -> int:
    """返回单个字符在终端中的显示宽度。

    - 全角字符（CJK、全角标点等）返回 2
    - 半角字符（ASCII、半角符号）返回 1
    - 控制字符 / 零宽字符返回 0
    - 多字符字符串只看第一个字符（调用方应保证传入单字符；空串返回 0）
    """
    if not ch:
        return 0
    if len(ch) > 1:
        ch = ch[0]
    cp = ord(ch)
    # 控制字符不计宽
    if cp < 0x20 or cp == 0x7F:
        return 0
    if cp == 0:
        return 0
    # 组合用记号、零宽空格等
    if unicodedata.category(ch) in ("Mn", "Me", "Cf"):
        return 0
    eaw = unicodedata.east_asian_width(ch)
    if eaw in ("W", "F"):
        return 2
    return 1


def text_width(s: str) -> int:
    """返回字符串在终端中的总显示宽度（按字符宽度累加）。"""
    return sum(char_width(ch) for ch in s)
