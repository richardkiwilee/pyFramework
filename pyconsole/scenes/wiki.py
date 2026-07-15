"""百科场景：输入框 + 实时模糊搜索 + 左右分栏列表/详情。

布局（上输入 + 左右分栏）：
  顶: 标题
  第2行: 输入框
  左栏: 搜索结果列表（名称 + [分类]，命中高亮，可滚动）
  右栏: 选中条目详情（全字段，命中高亮，PgUp/PgDn 可滚动）
  底: 键提示栏

交互：
  可打印字符 → 追加到查询词（限长 30），空格不响应
  Backspace → 删末尾
  ↑↓ → 切换列表选中项（自动滚动）
  PgUp/PgDn → 滚动详情
  Esc → 退出回主菜单
"""
from __future__ import annotations

import os
from typing import Any

from ..core import actions
from ..core.scene import Scene, SceneResult, POP, NONE
from ..data.wiki_data import WikiEntry, load_entries, search, SearchHit, find_match_ranges
from ..io.buffer import FrameBuffer
from ..io import theme
from ..io.widgets import draw_box, fill_rect, draw_hints, draw_input_field, put_truncated
from ..io.width import text_width

MAX_QUERY = 30
WIKI_JSON = os.path.join(os.path.dirname(__file__), "..", "data", "wiki.json")


class WikiScene(Scene):
    allow_status_overlay = False

    def __init__(self) -> None:
        super().__init__()
        self.entries: list[WikiEntry] = []
        self.query = ""
        self.hits: list[SearchHit] = []
        self.selected = 0
        self.list_scroll = 0
        self.detail_scroll = 0
        # 布局缓存（render 时更新）
        self._list_rect = (0, 0, 0, 0)
        self._detail_rect = (0, 0, 0, 0)
        self._detail_text: list[str] = []

    def on_enter(self, params: Any = None) -> None:
        self.params = params
        self.entries = load_entries(os.path.abspath(WIKI_JSON))
        self._refresh()

    # ---- 搜索 ----
    def _refresh(self) -> None:
        self.hits = search(self.entries, self.query)
        self.selected = 0
        self.list_scroll = 0
        self.detail_scroll = 0

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        if a == actions.CHAR:
            ch = event.char
            if ch == " ":
                return NONE()  # 空格不响应
            if len(self.query) < MAX_QUERY and ch.isprintable():
                self.query += ch
                self._refresh()
            return NONE()
        if a == actions.BACKSPACE:
            if self.query:
                self.query = self.query[:-1]
                self._refresh()
            return NONE()
        if a == actions.BACK:
            # Esc：退出百科
            return POP()
        if a == actions.UP:
            if self.hits:
                self.selected = (self.selected - 1) % len(self.hits)
                self.detail_scroll = 0
                self._clamp_scroll()
            return NONE()
        if a == actions.DOWN:
            if self.hits:
                self.selected = (self.selected + 1) % len(self.hits)
                self.detail_scroll = 0
                self._clamp_scroll()
            return NONE()
        if a == actions.SCROLL_UP:
            self.detail_scroll = max(0, self.detail_scroll - 1)
            return NONE()
        if a == actions.SCROLL_DOWN:
            self.detail_scroll = min(max(0, len(self._detail_text) - 1), self.detail_scroll + 1)
            return NONE()
        return NONE()

    def _clamp_scroll(self) -> None:
        lx, ly, lw, lh = self._list_rect
        visible = lh
        if self.selected < self.list_scroll:
            self.list_scroll = self.selected
        elif self.selected >= self.list_scroll + visible:
            self.list_scroll = self.selected - visible + 1

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="百科全书")

        # 标题行
        buf.put_text(2, 1, "奇幻 RPG 图鉴", theme.HEADING, theme.BG)

        # 输入框行 (y=2)
        input_y = 2
        buf.put_text(2, input_y, "搜索:", theme.ACCENT, theme.BG)
        # 输入框从 x=9 到 w-3
        field_x = 9
        field_w = w - field_x - 2
        draw_input_field(buf, field_x, input_y, field_w, self.query, prompt="",
                        fg=theme.SELECTED_FG, bg=theme.SELECTED_BG)

        # 分隔线 y=3
        for cx in range(1, w - 1):
            buf.set_char(cx, 3, "─", theme.BORDER, theme.BG)

        # 左右分栏区域 y=4 .. h-3
        top = 4
        bottom = h - 2  # 留底部提示栏
        mid_x = w // 2
        list_rect = (1, top, mid_x - 1, bottom - top)
        detail_rect = (mid_x, top, w - mid_x - 1, bottom - top)
        self._list_rect = list_rect
        self._detail_rect = detail_rect

        # 中间竖线
        for cy in range(top, bottom):
            buf.set_char(mid_x, cy, "│", theme.BORDER, theme.BG)

        self._render_list(buf, list_rect)
        self._render_detail(buf, detail_rect)

        # 底部分隔线 + 提示栏
        for cx in range(1, w - 1):
            buf.set_char(cx, bottom, "─", theme.BORDER, theme.BG)
        draw_hints(buf, h - 1, w, self.get_hints())

    def _render_list(self, buf: FrameBuffer, rect: tuple[int, int, int, int]) -> None:
        x, y, w, h = rect
        lx, ly, lw, lh = self._list_rect
        visible = lh
        if visible <= 0:
            return
        # 空查询
        if not self.query:
            buf.put_text(x + 2, y + 1, "请输入关键字进行搜索", theme.DIM, theme.BG)
            buf.put_text(x + 2, y + 3, "提示: 试试 武器 / 药水 / 龙 / 火", theme.DIM, theme.BG)
            return
        if not self.hits:
            buf.put_text(x + 2, y + 1, f"未找到匹配 \"{self.query}\" 的条目", theme.WARN, theme.BG)
            return
        # 列表行
        start = self.list_scroll
        end = min(len(self.hits), start + visible)
        for i in range(start, end):
            row = i - start
            hit = self.hits[i]
            e = hit.entry
            label = f"{e.name} [{e.category}]"
            ry = y + row
            if i == self.selected:
                buf.fill_rect(x, ry, w, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                marker = "▶ "
                buf.put_text(x, ry, marker, theme.ACCENT2, theme.SELECTED_BG)
                self._highlight(buf, x + 2, ry, e.name, theme.SELECTED_FG, theme.SELECTED_BG)
                cat_text = f" [{e.category}]"
                cx = x + 2 + text_width(e.name)
                buf.put_text(cx, ry, cat_text, theme.DIM, theme.SELECTED_BG)
            else:
                marker = "  "
                buf.put_text(x, ry, marker, theme.DIM, theme.BG)
                self._highlight(buf, x + 2, ry, e.name, theme.FG, theme.BG)
                cat_text = f" [{e.category}]"
                cx = x + 2 + text_width(e.name)
                buf.put_text(cx, ry, cat_text, theme.DIM, theme.BG)
        # 滚动指示
        if len(self.hits) > visible:
            info = f"({self.selected + 1}/{len(self.hits)})"
            buf.put_text(x + w - text_width(info) - 1, y - 1 if y > 0 else 0, info, theme.DIM, theme.BG)

    def _highlight(self, buf: FrameBuffer, x: int, y: int, text: str,
                   base_fg: int, base_bg: int) -> int:
        """写文本并把命中 query 的子串高亮。"""
        from ..io.widgets import highlight_text
        return highlight_text(buf, x, y, text, self.query, base_fg, base_bg,
                              theme.HIGHLIGHT_FG, theme.HIGHLIGHT_BG)

    def _render_detail(self, buf: FrameBuffer, rect: tuple[int, int, int, int]) -> None:
        x, y, w, h = rect
        if not self.query or not self.hits:
            buf.put_text(x + 2, y + 1, "请输入关键字，然后选择条目查看详情", theme.DIM, theme.BG)
            return
        if self.selected >= len(self.hits):
            return
        e = self.hits[self.selected].entry

        # 组装详情文本行（每行是 (kind, content) 元组），用于滚动
        lines: list[tuple[str, str]] = []
        lines.append(("name", e.name))
        lines.append(("cat", f"分类: {e.category}"))
        lines.append(("sep", "─" * (w - 4)))
        lines.append(("sum_label", "摘要"))
        lines.append(("sum", e.summary))
        lines.append(("sep2", "─" * (w - 4)))
        lines.append(("attr_label", "属性"))
        for k, v in e.attrs.items():
            lines.append(("attr", f"  {k}: {v}"))
        lines.append(("sep3", "─" * (w - 4)))
        lines.append(("det_label", "详情"))
        # detail 按宽度折行
        for wl in self._wrap(e.detail, w - 4):
            lines.append(("det", wl))
        self._detail_text = [content for _, content in lines]
        detail_lines = lines  # 含类型标记

        # 渲染（带滚动）
        max_show = h - 1
        start = self.detail_scroll
        end = min(len(detail_lines), start + max_show)
        ry = y
        for i in range(start, end):
            kind, content = detail_lines[i]
            fg = theme.FG
            if kind in ("name",):
                fg = theme.HEADING
            elif kind in ("sum_label", "attr_label", "det_label"):
                fg = theme.ACCENT
            elif kind in ("cat",):
                fg = theme.DIM
            elif kind in ("sep", "sep2", "sep3"):
                fg = theme.BORDER
            if kind in ("name", "sum", "det"):
                self._highlight(buf, x + 2, ry, content, fg, theme.BG)
            else:
                buf.put_text(x + 2, ry, content, fg, theme.BG)
            ry += 1

        # 滚动指示
        if len(detail_lines) > max_show:
            scr = f"行 {start + 1}-{end}/{len(detail_lines)}"
            buf.put_text(x + w - text_width(scr) - 1, y + h, scr, theme.DIM, theme.BG)

    @staticmethod
    def _wrap(text: str, width: int) -> list[str]:
        """按显示宽度折行（处理双宽）。"""
        if width <= 0:
            return [text]
        from ..io.width import char_width
        lines: list[str] = []
        cur = ""
        cur_w = 0
        for ch in text:
            cw = char_width(ch)
            if ch == "\n":
                lines.append(cur)
                cur = ""
                cur_w = 0
                continue
            if cur_w + cw > width:
                lines.append(cur)
                cur = ch
                cur_w = cw
            else:
                cur += ch
                cur_w += cw
        if cur:
            lines.append(cur)
        return lines

    def get_hints(self) -> list[str]:
        return ["输入 搜索", "↑↓ 切换条目", "PgUp/PgDn 滚动详情", "Backspace 删字", "Esc 退出"]
