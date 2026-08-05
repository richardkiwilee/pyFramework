"""全局 overlay 组件：按住 Tab 时显示的状态总览面板。

不入场景栈。主循环在场景渲染后、若 Tab 被按住，调用本组件在缓冲上叠加一个居中面板。
内容为"角色状态 + 框架调试信息"二合一。
"""
from __future__ import annotations

from ..io.buffer import FrameBuffer
from ..io import theme
from ..io.widgets import draw_box, fill_rect, put_centered, draw_bar
from .game_state import GameState


def render(buf: FrameBuffer, w: int, h: int,
           scene_name: str, stack_depth: int, state: GameState,
           bindings_count: int) -> None:
    """在 buf 上叠加一个居中的状态总览面板。"""
    pw, ph = 56, 18
    px = (w - pw) // 2
    py = (h - ph) // 2

    # 半透明背景：用 OVERLAY_BG 填充面板区域（含外边一圈）
    fill_rect(buf, px - 1, py - 1, pw + 2, ph + 2, " ", theme.FG, theme.OVERLAY_BG)
    draw_box(buf, px, py, pw, ph, title="状态总览 (按住 Tab)", fg=theme.OVERLAY_BORDER, bg=theme.OVERLAY_BG)

    cy = py + 2
    # ---- 上半：角色状态 ----
    buf.put_text(px + 2, cy, "角色状态", theme.HEADING, theme.OVERLAY_BG)
    cy += 1
    buf.put_text(px + 2, cy, f"姓名  {state.name}", theme.FG, theme.OVERLAY_BG)
    cy += 1
    buf.put_text(px + 2, cy, f"等级  Lv.{state.level}", theme.ACCENT, theme.OVERLAY_BG)
    cy += 1
    # HP 条
    buf.put_text(px + 2, cy, "HP", theme.DIM, theme.OVERLAY_BG)
    draw_bar(buf, px + 6, cy, 40, state.hp, state.max_hp, fill_fg=theme.HP, bg=theme.OVERLAY_BG)
    buf.put_text(px + 47, cy, f"{state.hp}/{state.max_hp}", theme.FG, theme.OVERLAY_BG)
    cy += 1
    # MP 条
    buf.put_text(px + 2, cy, "MP", theme.DIM, theme.OVERLAY_BG)
    draw_bar(buf, px + 6, cy, 40, state.mp, state.max_mp, fill_fg=theme.MP, bg=theme.OVERLAY_BG)
    buf.put_text(px + 47, cy, f"{state.mp}/{state.max_mp}", theme.FG, theme.OVERLAY_BG)
    cy += 1
    buf.put_text(px + 2, cy, f"金币  {state.gold} G", theme.GOLD, theme.OVERLAY_BG)
    cy += 1
    buf.put_text(px + 2, cy, f"位置  {state.location}", theme.FG, theme.OVERLAY_BG)
    cy += 1
    buf.put_text(px + 2, cy, f"背包  {state.inventory_count} 件物品", theme.FG, theme.OVERLAY_BG)
    cy += 1
    buf.put_text(px + 2, cy, f"任务  {state.quest_progress}", theme.ACCENT2, theme.OVERLAY_BG)

    # 分隔线
    cy += 1
    for cx in range(px + 2, px + pw - 2):
        buf.set_char(cx, cy, "─", theme.OVERLAY_BORDER, theme.OVERLAY_BG)
    cy += 1

    # ---- 下半：框架调试信息 ----
    buf.put_text(px + 2, cy, "框架调试", theme.HEADING, theme.OVERLAY_BG)
    cy += 1
    buf.put_text(px + 2, cy, f"当前场景   {scene_name}", theme.DIM, theme.OVERLAY_BG)
    cy += 1
    buf.put_text(px + 2, cy, f"场景栈深度 {stack_depth}", theme.DIM, theme.OVERLAY_BG)
    cy += 1
    buf.put_text(px + 2, cy, f"逻辑分辨率 {w}x{h}", theme.DIM, theme.OVERLAY_BG)
    cy += 1
    buf.put_text(px + 2, cy, f"键绑定数   {bindings_count}", theme.DIM, theme.OVERLAY_BG)
    cy += 1
    put_centered_in(buf, px, pw, py + ph - 2, "松开 Tab 关闭", theme.DIM, theme.OVERLAY_BG)


def put_centered_in(buf: FrameBuffer, px: int, pw: int, y: int, text: str,
                    fg: int, bg: int) -> None:
    tw = len(text)  # 纯 ASCII
    x = px + max(0, (pw - tw) // 2)
    buf.put_text(x, y, text, fg, bg)
