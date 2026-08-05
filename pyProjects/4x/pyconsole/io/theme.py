"""主题：256 色 ANSI 颜色常量集中定义。

改色只需改本文件。颜色用 256 色码（0-255），输出时映射为
SGR 序列 `38;5;N`（前景）/ `48;5;N`（背景）。
"""
from __future__ import annotations

from dataclasses import dataclass


# ---- 256 色码 ----
# 深色背景（接近 #1e1e2e）
BG = 235
# 主前景（接近 #cdd6f4）
FG = 254
# 暗色/次要文字
DIM = 245
# 强调色（青）
ACCENT = 81
# 强调色2（紫）
ACCENT2 = 141
# 标题
HEADING = 213
# 选中项背景
SELECTED_BG = 24
# 选中项前景
SELECTED_FG = 231
# 命中高亮
HIGHLIGHT_FG = 0
HIGHLIGHT_BG = 220
# 边框
BORDER = 60
# overlay 半透明背景
OVERLAY_BG = 237
OVERLAY_BORDER = 111
# 状态条颜色
HP = 124
MP = 27
GOLD = 221
# 错误/提示
WARN = 209


@dataclass(frozen=True)
class Color:
    """一对前后景色。"""
    fg: int = FG
    bg: int = BG


# 常用配色对
NORMAL = Color(FG, BG)
DIM_C = Color(DIM, BG)
ACCENT_C = Color(ACCENT, BG)
SELECTED = Color(SELECTED_FG, SELECTED_BG)
BORDER_C = Color(BORDER, BG)
HEADING_C = Color(HEADING, BG)
HIGHLIGHT = Color(HIGHLIGHT_FG, HIGHLIGHT_BG)
OVERLAY = Color(FG, OVERLAY_BG)


def sgr(fg: int, bg: int) -> str:
    """生成设置前后景色的 SGR 序列（不含 ESC 前缀）。"""
    return f"38;5;{fg};48;5;{bg}"


def sgr_fg(fg: int) -> str:
    return f"38;5;{fg}"


RESET = "\x1b[0m"
