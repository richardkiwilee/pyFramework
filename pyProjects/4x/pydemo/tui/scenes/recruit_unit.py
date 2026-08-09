"""招募普通兵场景（键 Q）：列出可招兵种，回车招募 → 待命·可用。

按 B1(用户细则):招募为全局——只要任一己方据点建有对应 recruit 建筑,即可在
任意己方据点招募,不必在建造据点。校验存在性(全局)+ 资源;招后进待命池
(cooldown=0),阵营级无位置(ADR-0005)。

交互(简化列表,参照 recruit.py 三窗口模式但改为单列):
- ↑↓ 选择兵种行。
- 回车招募焦点兵种:走 Game.action_recruit_unit(全局存在性 + 资源校验)。
  成功 → log + 留在本场景(可连招);失败 → log 警告。
- ESC 返回枢纽。

只列出"己方已建招募建筑解锁"的兵种(building def 的 recruits 含该 type_id,
且任一己方据点含该建筑);未解锁兵种不显示,避免列出永远招不了的项。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, POP, NONE
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box
from pyconsole.io.width import text_width

from .. import controller as ctrl_mod
from .. import log
from pydemo.game.economy import RESOURCE_CN
from pydemo.game.unit import ATTR_CN

# 列表窗口矩形(x, y, w, h)。外框 (0,0,100,30),y=3..27 给窗口。
LIST_RECT = (1, 3, 40, 25)
DETAIL_RECT = (42, 3, 57, 25)

# 详情展示的基础属性
DETAIL_ATTRS = ["hp", "p_atk", "m_atk", "p_def", "m_def", "speed",
                "acc", "eva", "block", "crit", "will", "occupy", "leadership"]


class RecruitUnitScene(Scene):
    allow_status_overlay = True

    def __init__(self) -> None:
        super().__init__()
        self.focus = 0
        self.list_scroll = 0

    def on_enter(self, params: Any = None) -> None:
        self.params = params
        self.focus = 0
        self.list_scroll = 0

    # ---- 数据 ----
    def _recruitable_types(self) -> list[tuple[str, str, str, bool]]:
        """可招兵种列表:(type_id, 中文名, 建筑名, 资源可负担)。

        只列出任一己方据点已建有对应 recruit 建筑的兵种(全局存在性已满足)。
        """
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()
        owned_type_ids = set()
        for sid in player.stronghold_ids:
            sh = g.map.strongholds.get(sid)
            if not sh:
                continue
            for b in sh.buildings:
                bdef = g.building_defs.get(b.type_id)
                if not bdef:
                    continue
                for tid in bdef.get("recruits", []):
                    owned_type_ids.add(tid)
        out = []
        for tid in sorted(owned_type_ids):
            ut = g.unit_type_defs.get(tid)
            if not ut:
                continue
            # 找到招募建筑名
            bname = tid
            for bid, bdef in g.building_defs.items():
                if tid in bdef.get("recruits", []):
                    bname = bdef.get("name", bid)
                    break
            ok = player.resources.can_afford(ut.recruit_cost)
            out.append((tid, ut.name, bname, ok))
        return out

    def _safe_list(self) -> list[tuple[str, str, str, bool]]:
        items = self._recruitable_types()
        if not items:
            return items
        if self.focus >= len(items):
            self.focus = len(items) - 1
        return items

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        if a == actions.BACK:
            return POP()
        items = self._safe_list()
        if a == actions.UP:
            if items:
                self.focus = (self.focus - 1) % len(items)
                self._clamp_scroll()
            return NONE()
        if a == actions.DOWN:
            if items:
                self.focus = (self.focus + 1) % len(items)
                self._clamp_scroll()
            return NONE()
        if a in (actions.CONFIRM, actions.SELECT):
            return self._recruit()
        if a == actions.SCROLL_UP:
            self.list_scroll = max(0, self.list_scroll - 1)
            return NONE()
        if a == actions.SCROLL_DOWN:
            self.list_scroll += 1
            self._clamp_scroll()
            return NONE()
        return NONE()

    def _clamp_scroll(self) -> None:
        _, _, _, lh = LIST_RECT
        visible = lh - 2
        if self.focus < self.list_scroll:
            self.list_scroll = self.focus
        elif self.focus >= self.list_scroll + visible:
            self.list_scroll = self.focus - visible + 1

    def _recruit(self) -> SceneResult:
        g = ctrl_mod.ctrl.g
        items = self._safe_list()
        if not items:
            log.push("无可招募兵种(需先建造招募建筑)", warn=True)
            return NONE()
        tid, name, _bname, _ok = items[self.focus]
        msg = g.action_recruit_unit(g.player_id, tid)
        ok = not msg.startswith("失败")
        log.push(msg, warn=not ok)
        return NONE()

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="招募普通兵")
        buf.put_text(2, 1, "↑↓ 选兵种  回车 招募(入待命·可用)  ESC 返回",
                     theme.DIM, theme.BG)
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)
        self._render_list(buf, LIST_RECT)
        self._render_detail(buf, DETAIL_RECT)
        log.render_log_bar(buf, 0, h - 2, w)

    def _render_list(self, buf: FrameBuffer, rect: tuple) -> None:
        x, y, ww, hh = rect
        draw_box(buf, x, y, ww, hh, title="可招兵种", fg=theme.BORDER)
        items = self._safe_list()
        if not items:
            buf.put_text(x + 1, y + 1, "（无可招募兵种）", theme.DIM, theme.BG)
            buf.put_text(x + 1, y + 3, "需先建造招募建筑", theme.DIM, theme.BG)
            buf.put_text(x + 1, y + 4, "（兵营/马厩/靶场/法师塔/寺院）", theme.DIM, theme.BG)
            return
        start = self.list_scroll
        visible = hh - 2
        end = min(len(items), start + visible)
        for i in range(start, end):
            row = i - start
            ry = y + 1 + row
            tid, name, _bname, ok = items[i]
            cost = ctrl_mod.ctrl.g.unit_type_defs[tid].recruit_cost
            cost_txt = " ".join(f"{RESOURCE_CN.get(k, k)}{v}" for k, v in cost.items()) or "免费"
            label = f"{name}  {cost_txt}"
            if i == self.focus:
                buf.fill_rect(x + 1, ry, ww - 2, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                buf.put_text(x + 1, ry, "▶", theme.ACCENT2, theme.SELECTED_BG)
                buf.put_text(x + 3, ry, label, theme.SELECTED_FG, theme.SELECTED_BG)
            else:
                fg = theme.FG if ok else theme.WARN
                buf.put_text(x + 1, ry, "  ", theme.DIM, theme.BG)
                buf.put_text(x + 3, ry, label, fg, theme.BG)
        if len(items) > visible:
            info = f"({self.focus + 1}/{len(items)})"
            buf.put_text(x + ww - text_width(info) - 1, y + 1, info, theme.DIM, theme.BG)

    def _render_detail(self, buf: FrameBuffer, rect: tuple) -> None:
        x, y, ww, hh = rect
        draw_box(buf, x, y, ww, hh, title="兵种详情", fg=theme.BORDER)
        items = self._safe_list()
        if not items or not (0 <= self.focus < len(items)):
            buf.put_text(x + 1, y + 1, "（请选择左侧兵种）", theme.DIM, theme.BG)
            return
        tid, name, bname, ok = items[self.focus]
        g = ctrl_mod.ctrl.g
        ut = g.unit_type_defs[tid]
        player = ctrl_mod.ctrl.player()
        ry = y + 1
        buf.put_text(x + 1, ry, f"名称: {ut.name}", theme.HEADING, theme.BG); ry += 1
        from pydemo.game.unit import TAG_CN
        tagstr = "/".join(TAG_CN.get(t, t) for t in sorted(ut.tags))
        buf.put_text(x + 1, ry, f"词条: {tagstr}", theme.DIM, theme.BG); ry += 1
        buf.put_text(x + 1, ry, f"招募建筑: {bname}", theme.DIM, theme.BG); ry += 2
        # 招募费用
        buf.put_text(x + 1, ry, "招募费用", theme.ACCENT, theme.BG); ry += 1
        if ut.recruit_cost:
            cost_txt = "  ".join(f"{RESOURCE_CN.get(k, k)}:{v}" for k, v in ut.recruit_cost.items())
        else:
            cost_txt = "免费"
        buf.put_text(x + 1, ry, cost_txt, theme.GOLD if ok else theme.WARN, theme.BG); ry += 2
        # 基础属性
        buf.put_text(x + 1, ry, "基础属性", theme.ACCENT, theme.BG); ry += 1
        for attr in DETAIL_ATTRS:
            if ry >= y + hh - 1:
                break
            val = ut.base.get(attr, 0)
            buf.put_text(x + 1, ry, f"{ATTR_CN.get(attr, attr)}: {int(val)}", theme.FG, theme.BG)
            ry += 1
        if ut.desc and ry < y + hh - 1:
            ry += 1
            buf.put_text(x + 1, ry, ut.desc, theme.DIM, theme.BG)

    def get_hints(self) -> list[str]:
        return ["↑↓ 选兵种", "回车 招募", "ESC 返回"]
