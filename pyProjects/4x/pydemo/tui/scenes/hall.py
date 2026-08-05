"""聚贤庄场景：只读展示玩家英雄厅（hall_of_worthies）。

按 操作逻辑.md：招募完后立刻进入聚贤庄。业务层无"召唤/登场/冷却推进"接口，
故本场景只读列出 hall_of_worthies 中的英雄及其冷却回合数，并标注占位说明。
ESC 返回；按"召唤"键给出占位警告（未来业务层扩展）。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, NONE, POP
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box, fill_rect
from pyconsole.io.width import text_width

from .. import controller as ctrl_mod
from .. import log
from pydemo.game.unit import ATTR_CN, TAG_CN


class HallScene(Scene):
    allow_status_overlay = True

    def __init__(self) -> None:
        super().__init__()
        self.focus = 0

    def on_enter(self, params: Any = None) -> None:
        self.params = params
        self.focus = 0

    # ---- 数据 ----
    def _entries(self) -> list[tuple[str, int]]:
        """hall_of_worthies: {hero_unit_id: cooldown} -> [(name, cooldown)]。"""
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()
        out: list[tuple[str, int]] = []
        for uid, cd in player.hall_of_worthies.items():
            u = g.unit_index.get(uid)
            name = u.name if u else uid
            out.append((uid, int(cd)))
        return out

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        if a == actions.BACK:
            return POP()
        if a in (actions.UP,):
            self._move(-1)
            return NONE()
        if a == actions.DOWN:
            self._move(1)
            return NONE()
        if a in (actions.CONFIRM, actions.SELECT):
            self._summon()
            return NONE()
        return NONE()

    def _move(self, delta: int) -> None:
        entries = self._entries()
        if not entries:
            return
        self.focus = (self.focus + delta) % len(entries)

    def _summon(self) -> None:
        entries = self._entries()
        if not entries:
            log.push("聚贤庄空空如也", warn=True)
            return
        uid, _cd = entries[self.focus]
        g = ctrl_mod.ctrl.g
        u = g.unit_index.get(uid)
        name = u.name if u else uid
        log.push(f"召唤 {name}：业务层暂未实现召唤/登场机制（占位）", warn=True)

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="聚贤庄")
        # 头部说明 y=1
        buf.put_text(2, 1, "招募 / 遣散的英雄在此休整（只读 · 召唤待业务层扩展）",
                     theme.DIM, theme.BG)
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)

        entries = self._entries()
        if not entries:
            buf.put_text(2, 4, "聚贤庄空空如也。", theme.DIM, theme.BG)
            buf.put_text(2, 6, "招募英雄后此处会显示其冷却剩余回合。", theme.DIM, theme.BG)
            buf.put_text(2, 28, "ESC 返回", theme.DIM, theme.BG)
            return

        # 表头 y=4
        buf.put_text(2, 4, "英雄", theme.ACCENT, theme.BG)
        buf.put_text(28, 4, "词条", theme.ACCENT, theme.BG)
        buf.put_text(70, 4, "冷却剩余", theme.ACCENT, theme.BG)
        for cx in range(1, w - 1):
            buf.set_char(cx, 5, "─", theme.BORDER, theme.BG)

        g = ctrl_mod.ctrl.g
        ry = 6
        for i, (uid, cd) in enumerate(entries):
            if ry >= h - 2:
                break
            u = g.unit_index.get(uid)
            name = u.name if u else uid
            tagstr = "/".join(TAG_CN.get(t, t) for t in sorted(u.tags)) if u else "—"
            cd_txt = f"{cd} 回合" if cd > 0 else "可召唤"
            cd_fg = theme.GOLD if cd > 0 else theme.ACCENT2
            if i == self.focus:
                buf.fill_rect(1, ry, w - 2, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                buf.put_text(2, ry, "▶", theme.ACCENT2, theme.SELECTED_BG)
                buf.put_text(4, ry, name, theme.SELECTED_FG, theme.SELECTED_BG)
                buf.put_text(28, ry, tagstr, theme.SELECTED_FG, theme.SELECTED_BG)
                buf.put_text(70, ry, cd_txt, theme.SELECTED_FG, theme.SELECTED_BG)
            else:
                buf.put_text(2, ry, "  ", theme.DIM, theme.BG)
                buf.put_text(4, ry, name, theme.HEADING, theme.BG)
                buf.put_text(28, ry, tagstr, theme.DIM, theme.BG)
                buf.put_text(70, ry, cd_txt, cd_fg, theme.BG)
            ry += 1

        buf.put_text(2, 28, "↑↓ 切换  回车 召唤(占位)  ESC 返回", theme.DIM, theme.BG)

    def get_hints(self) -> list[str]:
        return ["↑↓ 切换", "回车 召唤(占位)", "ESC 返回"]
