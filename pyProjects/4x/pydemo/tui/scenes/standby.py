"""待命池场景:只读浏览阵营级待命单位(ADR-0005)。

待命池为阵营级、全兵种通用、无位置的候命池。分两态:
  - 可用(冷却 0):可派遣到己方据点内的部队 / 可训练
  - 不可用(冷却 >0):下场后 5 回合冷却中,暂不能上场

业务层 Faction.standby: {unit_id: cooldown}。冷却在 start_turn 推进。
本场景只读列出待命单位及其冷却;ESC 返回。召唤/上场走部队编辑界面的"上场"。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, NONE, POP
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box

from .. import controller as ctrl_mod
from .. import log
from pydemo.game.unit import ATTR_CN, TAG_CN


class StandbyScene(Scene):
    allow_status_overlay = True

    def __init__(self) -> None:
        super().__init__()
        self.focus = 0

    def on_enter(self, params: Any = None) -> None:
        self.params = params
        self.focus = 0

    # ---- 数据 ----
    def _entries(self) -> list[tuple[str, int]]:
        """standby: {unit_id: cooldown} -> [(unit_id, cooldown)]。"""
        player = ctrl_mod.ctrl.player()
        return [(uid, int(cd)) for uid, cd in player.standby.items()]

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        if a == actions.BACK:
            return POP()
        if a == actions.UP:
            self._move(-1)
            return NONE()
        if a == actions.DOWN:
            self._move(1)
            return NONE()
        return NONE()

    def _move(self, delta: int) -> None:
        entries = self._entries()
        if not entries:
            return
        self.focus = (self.focus + delta) % len(entries)

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="待命池")
        buf.put_text(2, 1, "阵营级候命池 · 可用可派遣到己方据点部队 / 不可用为下场冷却中",
                     theme.DIM, theme.BG)
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)

        entries = self._entries()
        if not entries:
            buf.put_text(2, 4, "待命池为空。", theme.DIM, theme.BG)
            buf.put_text(2, 6, "招募或下场单位后会出现在此。", theme.DIM, theme.BG)
            log.render_log_bar(buf, 0, h - 2, w)
            return

        # 表头 y=4
        buf.put_text(2, 4, "单位", theme.ACCENT, theme.BG)
        buf.put_text(28, 4, "词条", theme.ACCENT, theme.BG)
        buf.put_text(64, 4, "状态", theme.ACCENT, theme.BG)
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
            status_txt = f"不可用({cd}回合)" if cd > 0 else "可用"
            status_fg = theme.WARN if cd > 0 else theme.ACCENT2
            if i == self.focus:
                buf.fill_rect(1, ry, w - 2, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                buf.put_text(2, ry, "▶", theme.ACCENT2, theme.SELECTED_BG)
                buf.put_text(4, ry, name, theme.SELECTED_FG, theme.SELECTED_BG)
                buf.put_text(28, ry, tagstr, theme.SELECTED_FG, theme.SELECTED_BG)
                buf.put_text(64, ry, status_txt, theme.SELECTED_FG, theme.SELECTED_BG)
            else:
                buf.put_text(2, ry, "  ", theme.DIM, theme.BG)
                buf.put_text(4, ry, name, theme.HEADING, theme.BG)
                buf.put_text(28, ry, tagstr, theme.DIM, theme.BG)
                buf.put_text(64, ry, status_txt, status_fg, theme.BG)
            ry += 1

        # §6 底部日志栏 y=h-2（键提示由框架在 h-1 绘制；行尾操作提示并入 get_hints）
        log.render_log_bar(buf, 0, h - 2, w)

    def get_hints(self) -> list[str]:
        return ["↑↓ 切换", "ESC 返回", "上场请到部队编辑界面"]
