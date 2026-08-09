"""据点总览场景（键 V）：全据点表格 + 1234 筛选。

按 修正稿1.md §4：
- 一个表格。最左列=据点名称（颜色区分归属：我方绿/敌方红/中立白），
  其后是"标志建筑"列（显示据点标志性建筑的中文名），再后是槽位 1..5 共 5 列。
- 据点最多 5 个普通槽位（Stronghold.size 为 1..5 整数，ADR-0006）。
  · 已建造的槽位 → 显示建筑名；
  · 空槽位（i < size 且无建筑）→ 显示"空"；
  · 该据点没有的槽位（i >= size）→ 显示"X"。
- 1234 筛选：1=我方 / 2=敌方 / 3=中立 / 4=全部。
- ↑↓ 选择行；回车进入该据点的据点详情（委托 StrongholdScene，预选到该据点）；
  ESC 返回。

标志建筑为独立 Building 实例（Stronghold.landmark，专用槽、不计 size），
按档位（弱/中/强）给驻守部队 p_def 加成。本列展示其名称。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, PUSH, POP, NONE
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box
from pyconsole.io.width import text_width

from .. import controller as ctrl_mod
from .. import log
from .. import actions as g_actions

# 归属颜色（与 stronghold.py / map_scene.py 一致）
C_OWN = 41       # 绿
C_ENEMY = 196    # 红
C_NEUTRAL = 254  # 白

FILTER_LABELS = ["我方", "敌方", "中立", "全部"]

# 表格列定义（起点 x, 宽度）。外框 (0,0,100,30)，内部 x=1..98。
# 名称 | 标志性建筑 | 槽1 | 槽2 | 槽3 | 槽4 | 槽5
COL_NAME = (2, 14)
COL_LANDMARK = (17, 10)
COL_SLOTS = [(28, 13), (42, 13), (56, 13), (70, 13), (84, 14)]
SLOT_HEADER = ["槽1", "槽2", "槽3", "槽4", "槽5"]


def _owner_color(sh, player_id: str) -> int:
    if sh.owner == player_id:
        return C_OWN
    if sh.owner is None:
        return C_NEUTRAL
    return C_ENEMY


class StrongholdOverviewScene(Scene):
    allow_status_overlay = True

    def __init__(self) -> None:
        super().__init__()
        self.filter = 0          # 0=我方 1=敌方 2=中立 3=全部
        self.focus = 0           # 行焦点
        self.scroll = 0

    def on_enter(self, params: Any = None) -> None:
        self.params = params

    # ---- 数据 ----
    def _filtered_strongholds(self) -> list:
        g = ctrl_mod.ctrl.g
        pid = g.player_id
        shs = list(g.map.strongholds.values())
        if self.filter == 0:    # 我方
            return [s for s in shs if s.owner == pid]
        if self.filter == 1:    # 敌方
            return [s for s in shs if s.owner not in (None, pid)]
        if self.filter == 2:    # 中立
            return [s for s in shs if s.owner is None]
        return shs               # 全部

    def _safe_focus(self) -> list:
        shs = self._filtered_strongholds()
        if not shs:
            self.focus = 0
            return shs
        if self.focus >= len(shs):
            self.focus = len(shs) - 1
        return shs

    def _clamp_scroll(self, hh: int) -> None:
        visible = hh - 2
        if self.focus < self.scroll:
            self.scroll = self.focus
        elif self.focus >= self.scroll + visible:
            self.scroll = self.focus - visible + 1

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        if a == g_actions.FILTER_1:
            self.filter = 0; self.focus = 0; self.scroll = 0; return NONE()
        if a == g_actions.FILTER_2:
            self.filter = 1; self.focus = 0; self.scroll = 0; return NONE()
        if a == g_actions.FILTER_3:
            self.filter = 2; self.focus = 0; self.scroll = 0; return NONE()
        if a == g_actions.FILTER_4:
            self.filter = 3; self.focus = 0; self.scroll = 0; return NONE()
        if a == actions.BACK:
            return POP()
        if a in (actions.UP, actions.DOWN):
            shs = self._safe_focus()
            if shs:
                delta = -1 if a == actions.UP else 1
                self.focus = (self.focus + delta) % len(shs)
            return NONE()
        if a == actions.CONFIRM:
            return self._enter_detail()
        return NONE()

    def _enter_detail(self) -> SceneResult:
        shs = self._safe_focus()
        if not shs:
            return NONE()
        sh = shs[self.focus]
        from .stronghold import StrongholdScene
        return PUSH(StrongholdScene(), {"stronghold_id": sh.id})

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="据点总览")
        self._render_filter_row(buf, w)
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)
        # 表头 y=3，行 y=4..，日志栏 y=h-2
        self._render_header(buf, 3)
        self._render_rows(buf, 4, h - 2)
        log.render_log_bar(buf, 0, h - 2, w)

    def _render_filter_row(self, buf: FrameBuffer, w: int) -> None:
        x = 2
        for i, label in enumerate(FILTER_LABELS):
            tag = f"{i+1} {label}"
            fg = theme.ACCENT if i == self.filter else theme.DIM
            if i > 0:
                x = buf.put_text(x, 1, "   ", theme.DIM, theme.BG)
            x = buf.put_text(x, 1, tag, fg, theme.BG)

    def _render_header(self, buf: FrameBuffer, y: int) -> None:
        # 名称列
        x, ww = COL_NAME
        buf.put_text(x, y, "据点", theme.HEADING, theme.BG)
        # 标志性建筑列
        x, ww = COL_LANDMARK
        buf.put_text(x, y, "标志建筑", theme.HEADING, theme.BG)
        # 槽位列
        for i, (cx, _) in enumerate(COL_SLOTS):
            buf.put_text(cx, y, SLOT_HEADER[i], theme.HEADING, theme.BG)
        # 表头下分隔线
        for cx in range(1, buf.w - 1):
            buf.set_char(cx, y + 1, "─", theme.BORDER, theme.BG)

    def _render_rows(self, buf: FrameBuffer, y0: int, y_max: int) -> None:
        shs = self._safe_focus()
        if not shs:
            buf.put_text(2, y0, "（无据点）", theme.DIM, theme.BG)
            return
        hh = y_max - y0
        self._clamp_scroll(hh)
        pid = ctrl_mod.ctrl.g.player_id
        start = self.scroll
        end = min(len(shs), start + hh)
        for i in range(start, end):
            ry = y0 + (i - start)
            if ry >= y_max:
                break
            sh = shs[i]
            focused = (i == self.focus)
            self._render_row(buf, ry, sh, focused, pid)
        # 滚动指示
        if len(shs) > hh:
            buf.put_text(buf.w - 10, 1, f"({self.focus+1}/{len(shs)})",
                         theme.DIM, theme.BG)

    def _render_row(self, buf: FrameBuffer, y: int, sh, focused: bool, pid: str) -> None:
        # 选中行整行反色底
        if focused:
            buf.fill_rect(1, y, buf.w - 2, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
            buf.set_char(1, y, "▶", theme.ACCENT2, theme.SELECTED_BG)
        # 名称列（归属色；选中时用选中配色）
        x, ww = COL_NAME
        name_fg = _owner_color(sh, pid)
        name_txt = f"◆{sh.name}" + ("(都)" if sh.is_capital else "")
        if focused:
            buf.put_text(x, y, name_txt, theme.SELECTED_FG, theme.SELECTED_BG)
        else:
            buf.put_text(x, y, name_txt, name_fg, theme.BG)
        # 标志建筑列：显示 landmark 中文名（独立 Building，专用槽）
        x, ww = COL_LANDMARK
        lm_txt = sh.landmark.name if sh.landmark else "无"
        lm_fg = theme.SELECTED_FG if focused else theme.ACCENT2
        buf.put_text(x, y, lm_txt, lm_fg, theme.SELECTED_BG if focused else theme.BG)
        # 槽位 1..5
        for i, (cx, cww) in enumerate(COL_SLOTS):
            if i < sh.size:
                if i < len(sh.buildings):
                    txt = sh.buildings[i].name
                    fg = theme.SELECTED_FG if focused else theme.FG
                else:
                    txt = "空"
                    fg = theme.SELECTED_FG if focused else theme.DIM
            else:
                txt = "X"   # 该据点没有这个槽位
                fg = theme.WARN if not focused else theme.SELECTED_FG
            # 截断到列宽
            if text_width(txt) > cww - 1:
                txt = _truncate(txt, cww - 2)
            buf.put_text(cx, y, txt, fg, theme.SELECTED_BG if focused else theme.BG)

    def get_hints(self) -> list[str]:
        return ["1-4 筛选", "↑↓ 选据点", "回车 进据点详情", "ESC 返回"]


def _truncate(text: str, max_w: int) -> str:
    if text_width(text) <= max_w:
        return text
    out = ""; w = 0
    from pyconsole.io.width import char_width
    for ch in text:
        cw = char_width(ch)
        if w + cw > max_w - 1:
            break
        out += ch; w += cw
    return out + "…"
