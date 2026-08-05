"""科技/文化树共享场景基类。

按 操作逻辑.md（科技树与文化树同构）：
- 左右分割：左侧项目名称列表，右侧详细说明（文字 / 解锁项 / 花费 / 跳转词条）。
- 数字键 1234 筛选左侧：全部 / 已学习 / 未学习 / 可学习。
- 颜色：绿色=已学习，白色=可学习(前置满足且资源足够)，红色=未学习且前置不满足，
  黄色=可学习(前置满足但资源不足)。
- 焦点在左侧时回车=学习；空格(SELECT)切换焦点进右侧；右侧 ↑↓ 切换跳转词条，
  回车打开百科并预填该词；右侧 ESC 回到左侧，左侧 ESC 退出本场景。

业务层没有科技/文化系统，故学习记录保存在控制器（ctrl.tech_learned /
ctrl.culture_learned），资源从玩家阵营扣除（TUI 侧，不影响战斗/经济）。
desc 中的 [[词]] 标记为跳转词条，渲染时去掉方括号以强调色显示。
"""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, PUSH, POP, NONE
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box, fill_rect
from pyconsole.io.width import text_width

from .. import controller as ctrl_mod
from .. import log
from .. import actions as g_actions

# 模块局部颜色（theme.py 冻结，树场景专用）
C_LEARNED = 41      # 绿
C_READY = 254       # 白
C_LOCKED = 196      # 红
C_POOR = 221        # 黄

FILTER_LABELS = ["全部", "已学习", "未学习", "可学习"]


@dataclass
class TreeItem:
    id: str
    name: str
    category: str = ""
    desc: str = ""
    cost: dict = field(default_factory=dict)
    prereqs: list = field(default_factory=list)
    unlocks: list = field(default_factory=list)
    wiki_link: str = ""

    @classmethod
    def from_dict(cls, d: dict) -> "TreeItem":
        return cls(
            id=str(d.get("id", "")),
            name=str(d.get("name", "")),
            category=str(d.get("category", "")),
            desc=str(d.get("desc", "")),
            cost=d.get("cost", {}) if isinstance(d.get("cost"), dict) else {},
            prereqs=list(d.get("prereqs", [])) if isinstance(d.get("prereqs"), list) else [],
            unlocks=list(d.get("unlocks", [])) if isinstance(d.get("unlocks"), list) else [],
            wiki_link=str(d.get("wiki_link", "") or ""),
        )


def load_tree(path: str) -> list[TreeItem]:
    if not path or not os.path.isfile(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return []
    if not isinstance(data, list):
        return []
    return [TreeItem.from_dict(d) for d in data if isinstance(d, dict)]


_LINK_RE = re.compile(r"\[\[(.+?)\]\]")


def parse_links(text: str) -> list[str]:
    """提取 desc 中所有 [[词]] 的词（去方括号），保持出现顺序、去重。"""
    seen: list[str] = []
    sset = set()
    for m in _LINK_RE.finditer(text):
        term = m.group(1).strip()
        if term and term not in sset:
            seen.append(term)
            sset.add(term)
    return seen


def strip_links(text: str) -> str:
    """把 [[词]] 渲染为 词（去方括号）。"""
    return _LINK_RE.sub(lambda m: m.group(1), text)


class TreeScene(Scene):
    """科技树/文化树共享基类。子类设置 TITLE / DATA_PATH 并实现 _learned_set。"""

    allow_status_overlay = True
    TITLE = "科技树"
    DATA_PATH = ""   # 子类覆盖

    def __init__(self) -> None:
        super().__init__()
        self.items: list[TreeItem] = []
        self.filter = 0          # 0..3
        self.focus = 0           # 左侧列表焦点（在过滤后列表中的下标）
        self.list_scroll = 0
        self.in_detail = False   # False=左侧列表有焦点，True=右侧详情有焦点
        self.detail_scroll = 0
        self.link_focus = 0      # 右侧跳转词条焦点
        self._links: list[str] = []
        self._list_rect = (0, 0, 0, 0)
        self._detail_rect = (0, 0, 0, 0)

    # ---- 子类钩子 ----
    def _learned_set(self) -> set[str]:
        return ctrl_mod.ctrl.tech_learned

    # ---- 生命周期 ----
    def on_enter(self, params: Any = None) -> None:
        self.params = params
        self.items = load_tree(os.path.abspath(self.DATA_PATH))
        self._refresh_links()

    def _filtered(self) -> list[TreeItem]:
        learned = self._learned_set()
        if self.filter == 0:   # 全部
            return self.items
        if self.filter == 1:   # 已学习
            return [it for it in self.items if it.id in learned]
        if self.filter == 2:   # 未学习
            return [it for it in self.items if it.id not in learned]
        # 可学习：前置满足且未学习
        out = []
        for it in self.items:
            if it.id in learned:
                continue
            if all(p in learned for p in it.prereqs):
                out.append(it)
        return out

    def _state(self, it: TreeItem) -> int:
        """返回颜色码。"""
        if it.id in self._learned_set():
            return C_LEARNED
        if not all(p in self._learned_set() for p in it.prereqs):
            return C_LOCKED
        res = ctrl_mod.ctrl.player().resources
        return C_READY if res.can_afford(it.cost) else C_POOR

    def _refresh_links(self) -> None:
        filtered = self._filtered()
        if 0 <= self.focus < len(filtered):
            self._links = parse_links(filtered[self.focus].desc)
        else:
            self._links = []
        if self.link_focus >= len(self._links):
            self.link_focus = 0

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        # 筛选（任何时候）
        if a == g_actions.FILTER_1:
            self.filter = 0; self.focus = 0; self.list_scroll = 0; self._refresh_links()
            return NONE()
        if a == g_actions.FILTER_2:
            self.filter = 1; self.focus = 0; self.list_scroll = 0; self._refresh_links()
            return NONE()
        if a == g_actions.FILTER_3:
            self.filter = 2; self.focus = 0; self.list_scroll = 0; self._refresh_links()
            return NONE()
        if a == g_actions.FILTER_4:
            self.filter = 3; self.focus = 0; self.list_scroll = 0; self._refresh_links()
            return NONE()

        if a == actions.SELECT:  # 空格：左右焦点切换（替代 alt）
            self.in_detail = not self.in_detail
            if self.in_detail:
                self.link_focus = 0
            return NONE()

        if a == actions.BACK:
            if self.in_detail:
                self.in_detail = False
                return NONE()
            return POP()

        if self.in_detail:
            # 右侧：↑↓ 切跳转词条，回车跳百科，PgUp/PgDn 滚详情
            if a == actions.UP:
                if self._links:
                    self.link_focus = (self.link_focus - 1) % len(self._links)
                return NONE()
            if a == actions.DOWN:
                if self._links:
                    self.link_focus = (self.link_focus + 1) % len(self._links)
                return NONE()
            if a == actions.CONFIRM:
                if self._links:
                    term = self._links[self.link_focus]
                    from .wiki import GameWikiScene
                    return PUSH(GameWikiScene(), {"query": term})
                return NONE()
            if a == actions.SCROLL_UP:
                self.detail_scroll = max(0, self.detail_scroll - 1)
                return NONE()
            if a == actions.SCROLL_DOWN:
                self.detail_scroll += 1
                return NONE()
            return NONE()

        # 左侧：↑↓ 移焦点，回车学习
        if a in (actions.UP, actions.DOWN):
            filtered = self._filtered()
            if not filtered:
                return NONE()
            if a == actions.UP:
                self.focus = (self.focus - 1) % len(filtered)
            else:
                self.focus = (self.focus + 1) % len(filtered)
            self.detail_scroll = 0
            self._clamp_scroll()
            self._refresh_links()
            return NONE()
        if a == actions.CONFIRM:
            self._try_learn()
            return NONE()
        if a == actions.SCROLL_UP:
            self.list_scroll = max(0, self.list_scroll - 1)
            return NONE()
        if a == actions.SCROLL_DOWN:
            self.list_scroll += 1
            self._clamp_scroll()
            return NONE()
        return NONE()

    def _clamp_scroll(self) -> None:
        _, _, _, lh = self._list_rect
        visible = lh
        if self.focus < self.list_scroll:
            self.list_scroll = self.focus
        elif self.focus >= self.list_scroll + visible:
            self.list_scroll = self.focus - visible + 1

    def _try_learn(self) -> None:
        filtered = self._filtered()
        if not (0 <= self.focus < len(filtered)):
            return
        it = filtered[self.focus]
        learned = self._learned_set()
        if it.id in learned:
            log.push(f"已学习过：{it.name}")
            return
        if not all(p in learned for p in it.prereqs):
            missing = [p for p in it.prereqs if p not in learned]
            log.push(f"前置未满足：{it.name}（缺 {', '.join(missing)}）", warn=True)
            return
        res = ctrl_mod.ctrl.player().resources
        if not res.can_afford(it.cost):
            log.push(f"资源不足，无法学习 {it.name}", warn=True)
            return
        res.pay(it.cost)
        learned.add(it.id)
        log.push(f"学习了 {it.name}")
        self._refresh_links()

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title=self.TITLE)
        self._render_filter_row(buf, w)
        # 分隔线 y=2
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)
        top = 3
        bottom = h - 2
        mid_x = w // 2
        list_rect = (1, top, mid_x - 1, bottom - top)
        detail_rect = (mid_x, top, w - mid_x - 1, bottom - top)
        self._list_rect = list_rect
        self._detail_rect = detail_rect
        for cy in range(top, bottom):
            buf.set_char(mid_x, cy, "│", theme.BORDER, theme.BG)
        self._render_list(buf, list_rect)
        self._render_detail(buf, detail_rect)
        for cx in range(1, w - 1):
            buf.set_char(cx, bottom, "─", theme.BORDER, theme.BG)

    def _render_filter_row(self, buf: FrameBuffer, w: int) -> None:
        parts = []
        for i, label in enumerate(FILTER_LABELS):
            tag = f"{i+1} {label}"
            if i == self.filter:
                parts.append((tag, theme.ACCENT, theme.BG))
            else:
                parts.append((tag, theme.DIM, theme.BG))
        x = 2
        y = 1
        for i, (tag, fg, bg) in enumerate(parts):
            if i > 0:
                x = buf.put_text(x, y, "   ", theme.DIM, bg)
            x = buf.put_text(x, y, tag, fg, bg)

    def _render_list(self, buf: FrameBuffer, rect: tuple[int, int, int, int]) -> None:
        x, y, w, h = rect
        filtered = self._filtered()
        if not filtered:
            buf.put_text(x + 1, y + 1, "（无项目）", theme.DIM, theme.BG)
            return
        start = self.list_scroll
        end = min(len(filtered), start + h)
        for i in range(start, end):
            row = i - start
            it = filtered[i]
            ry = y + row
            color = self._state(it)
            marker = "▶ " if (i == self.focus and not self.in_detail) else ("  " if i == self.focus else "  ")
            if i == self.focus and not self.in_detail:
                buf.fill_rect(x, ry, w, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                buf.put_text(x, ry, marker, theme.ACCENT2, theme.SELECTED_BG)
                buf.put_text(x + 2, ry, it.name, theme.SELECTED_FG, theme.SELECTED_BG)
            else:
                buf.put_text(x, ry, marker, theme.DIM, theme.BG)
                buf.put_text(x + 2, ry, it.name, color, theme.BG)
        if len(filtered) > h:
            info = f"({self.focus + 1}/{len(filtered)})"
            buf.put_text(x + w - text_width(info) - 1, y - 1 if y > 0 else 0, info, theme.DIM, theme.BG)

    def _render_detail(self, buf: FrameBuffer, rect: tuple[int, int, int, int]) -> None:
        x, y, w, h = rect
        filtered = self._filtered()
        if not filtered or not (0 <= self.focus < len(filtered)):
            buf.put_text(x + 1, y + 1, "（请选择左侧项目）", theme.DIM, theme.BG)
            return
        it = filtered[self.focus]
        from pydemo.game.economy import RESOURCE_CN
        lines: list[tuple[str, str, int]] = []  # (kind, content, fg)
        lines.append(("name", it.name, theme.HEADING))
        lines.append(("cat", f"分类: {it.category}", theme.DIM))
        lines.append(("sep", "─" * (w - 4), theme.BORDER))
        lines.append(("label", "说明", theme.ACCENT))
        for wl in self._wrap(strip_links(it.desc), w - 4):
            lines.append(("desc", wl, theme.FG))
        lines.append(("sep", "─" * (w - 4), theme.BORDER))
        lines.append(("label", "解锁", theme.ACCENT))
        if it.unlocks:
            for u in it.unlocks:
                lines.append(("unlock", f"  · {u}", theme.FG))
        else:
            lines.append(("unlock", "  （无）", theme.DIM))
        lines.append(("sep", "─" * (w - 4), theme.BORDER))
        lines.append(("label", "花费", theme.ACCENT))
        if it.cost:
            cost_txt = "  ".join(f"{RESOURCE_CN.get(k, k)}:{v}" for k, v in it.cost.items())
            res = ctrl_mod.ctrl.player().resources
            c_fg = theme.GOLD if res.can_afford(it.cost) else theme.WARN
            lines.append(("cost", cost_txt, c_fg))
        else:
            lines.append(("cost", "  （无）", theme.DIM))
        lines.append(("sep", "─" * (w - 4), theme.BORDER))
        lines.append(("label", "跳转", theme.ACCENT))
        if self._links:
            link_txt = "  ".join(self._links)
            lines.append(("links", link_txt, theme.ACCENT2))
        else:
            lines.append(("links", "  （无跳转词条）", theme.DIM))

        self._detail_text_len = len(lines)
        max_show = h - 1
        start = min(self.detail_scroll, max(0, len(lines) - max_show))
        end = min(len(lines), start + max_show)
        ry = y
        for i in range(start, end):
            kind, content, fg = lines[i]
            if kind == "links" and self.in_detail and self._links:
                self._render_links_line(buf, x + 2, ry, w - 4, fg)
            else:
                buf.put_text(x + 2, ry, content, fg, theme.BG)
            ry += 1
        if len(lines) > max_show:
            scr = f"行 {start + 1}-{end}/{len(lines)}"
            buf.put_text(x + w - text_width(scr) - 1, y + h, scr, theme.DIM, theme.BG)

    def _render_links_line(self, buf: FrameBuffer, x: int, y: int, max_w: int, base_fg: int) -> None:
        """渲染跳转词条行：当前焦点词条用高亮，其余用强调色。"""
        cx = x
        for i, term in enumerate(self._links):
            seg = term + "  "
            if cx + text_width(seg) > x + max_w:
                buf.put_text(cx, y, "…", theme.DIM, theme.BG)
                return
            if i == self.link_focus and self.in_detail:
                cx = buf.put_text(cx, y, term, theme.HIGHLIGHT_FG, theme.HIGHLIGHT_BG)
                cx = buf.put_text(cx, y, "  ", theme.HIGHLIGHT_FG, theme.HIGHLIGHT_BG)
            else:
                cx = buf.put_text(cx, y, seg, base_fg, theme.BG)

    @staticmethod
    def _wrap(text: str, width: int) -> list[str]:
        if width <= 0:
            return [text]
        from pyconsole.io.width import char_width
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
        if self.in_detail:
            base = ["↑↓ 切换词条", "回车 跳百科", "空格 回左侧", "PgUp/PgDn 滚动"]
        else:
            base = ["↑↓ 选项目", "回车 学习", "空格 进详情", "1-4 筛选"]
        base.append("ESC 返回")
        return base


class TechTreeScene(TreeScene):
    TITLE = "科技树"
    DATA_PATH = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
        "data", "techs.json",
    )

    def _learned_set(self) -> set[str]:
        return ctrl_mod.ctrl.tech_learned
