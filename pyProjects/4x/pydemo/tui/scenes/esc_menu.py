"""退出选单（ESC 菜单）：居中模态列表。

按 操作逻辑.md：枢纽按 ESC 弹出选单，包含 继续/保存/读取/返回主菜单（共 4 项）。
结束回合由专用 T 键触发，不在选单内。完整存档序列化留待 M10。

返回值约定（POP 的 return_value 经 GameScene.on_return 处理）：
  "to_menu" → 枢纽弹掉自身回主菜单
  None      → 继续游戏（仅关闭选单）
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, PUSH, POP, NONE
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box, fill_rect, put_centered
from pyconsole.io.width import text_width

from .. import controller as ctrl_mod
from .. import log


class EscMenuScene(Scene):
    allow_status_overlay = False

    def __init__(self) -> None:
        super().__init__()
        self.items = ["继续游戏", "保存", "读取", "返回主菜单"]
        self.focus = 0

    def on_enter(self, params: Any = None) -> None:
        self.params = params

    def handle_action(self, event) -> SceneResult:
        a = event.action
        if a == actions.UP:
            self.focus = (self.focus - 1) % len(self.items)
            return NONE()
        if a == actions.DOWN:
            self.focus = (self.focus + 1) % len(self.items)
            return NONE()
        if a == actions.BACK:
            # ESC 再次按下 = 继续游戏
            return POP()
        if a in (actions.CONFIRM, actions.SELECT):
            return self._activate(self.focus)
        return NONE()

    def _activate(self, index: int) -> SceneResult:
        label = self.items[index]
        if label == "继续游戏":
            return POP()
        if label == "保存":
            from pyconsole.scenes.message import MessageScene
            msg = ctrl_mod.ctrl.save()
            log.push(msg)
            return PUSH(MessageScene(msg))
        if label == "读取":
            from pyconsole.scenes.message import MessageScene
            msg = ctrl_mod.ctrl.load()
            log.push(msg, warn=True)
            # 读取成功则关掉选单回到游戏场景(状态已替换)
            if msg.startswith("已读取"):
                return POP()
            return PUSH(MessageScene(msg))
        if label == "返回主菜单":
            return POP("to_menu")
        return NONE()

    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        # 半透明遮罩
        buf.fill_rect(0, 0, w, h, " ", theme.FG, theme.OVERLAY_BG)

        menu_w = 26
        menu_h = len(self.items) + 4
        mx = (w - menu_w) // 2
        my = (h - menu_h) // 2
        draw_box(buf, mx, my, menu_w, menu_h, title="选单", fg=theme.OVERLAY_BORDER, bg=theme.OVERLAY_BG)

        for i, label in enumerate(self.items):
            ry = my + 2 + i
            text = f"  {label}  "
            tw = text_width(text)
            cell_w = menu_w - 2
            if i == self.focus:
                buf.fill_rect(mx + 1, ry, cell_w, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                tx = mx + 1 + (cell_w - tw) // 2
                buf.put_text(tx, ry, text, theme.SELECTED_FG, theme.SELECTED_BG)
            else:
                tx = mx + 1 + (cell_w - tw) // 2
                buf.put_text(tx, ry, text, theme.FG, theme.OVERLAY_BG)

        put_centered(buf, my + menu_h - 1, "↑↓ 选择 · 回车 确认 · ESC 继续", menu_w + 4,
                     theme.DIM, theme.OVERLAY_BG)

    def get_hints(self) -> list[str]:
        return ["↑↓ 选择", "回车 确认", "ESC 继续"]
