"""主菜单场景：logo + 继续/开始/退出。

按 操作逻辑.md：主界面 ESC 无效、Tab 无效，仅可用上下键和回车。
故 handle_action 吞掉 BACK 与 SELECT，只响应 UP/DOWN/CONFIRM。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, PUSH, POP, QUIT, NONE
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box, put_centered
from pyconsole.io.width import text_width

from .. import controller as ctrl_mod

# ASCII logo（保持 ≤ 60 显示宽）
LOGO = [
    r"  _____           _                      _____                            ",
    r" |_   _|__ _ __ _| |_ ___ _ __  ___    __|_   _|__  ___  ___  ___ ___    ",
    r"   | |/ _ \ '_(_-<  _/ _ \ '  \/ -_)   / _|| |/ _ \/ _ \/ -_|_-<(_-<   ",
    r"   |_|\___/_| \__/\__\___/_|_|_\___|   \__|_|\___/\___/\___/__/__/   ",
]
SUBTITLE = "4X 回合制策略 · TUI 演示"


class MainMenuScene(Scene):
    allow_status_overlay = False  # 主菜单：ESC/Tab 无效

    def __init__(self) -> None:
        super().__init__()
        self.items = ["继续游戏", "开始游戏", "退出游戏"]
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
        if a in (actions.SELECT, actions.BACK):
            # spec：主界面 ESC 无效；空格也不作选择
            return NONE()
        if a == actions.CONFIRM:
            return self._activate(self.focus)
        return NONE()

    def _activate(self, index: int) -> SceneResult:
        label = self.items[index]
        if label == "继续游戏":
            import os
            from .. import controller as ctrl_mod
            # 有存档才进入游戏;无存档提示并留主菜单
            if os.path.isfile(ctrl_mod.ctrl._save_path()):
                msg = ctrl_mod.ctrl.load()
                from pyconsole.scenes.message import MessageScene
                # 读取成功则进入游戏场景
                if msg.startswith("已读取"):
                    from .game_scene import GameScene
                    return PUSH(GameScene())
                return PUSH(MessageScene(msg))
            from pyconsole.scenes.message import MessageScene
            return PUSH(MessageScene("无存档（开始新游戏）"))
        if label == "开始游戏":
            ctrl_mod.ctrl.new_game()
            from .game_scene import GameScene
            return PUSH(GameScene())
        if label == "退出游戏":
            return QUIT()
        return NONE()

    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="The Great Conquest")
        ty = 3
        for i, line in enumerate(LOGO):
            put_centered(buf, ty + i, line, w, theme.HEADING, theme.BG)
        put_centered(buf, ty + len(LOGO) + 1, SUBTITLE, w, theme.DIM, theme.BG)

        menu_y = ty + len(LOGO) + 4
        menu_w = 22
        mx = (w - menu_w) // 2
        for i, label in enumerate(self.items):
            y = menu_y + i
            if i == self.focus:
                text = f"  >  {label}  "
                buf.fill_rect(mx, y, menu_w, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                tx = mx + (menu_w - text_width(text)) // 2
                buf.put_text(tx, y, text, theme.SELECTED_FG, theme.SELECTED_BG)
            else:
                text = f"     {label}    "
                tx = mx + (menu_w - text_width(text)) // 2
                buf.put_text(tx, y, text, theme.FG, theme.BG)

        note_y = menu_y + len(self.items) + 2
        put_centered(buf, note_y, "↑↓ 移动 · 回车 选择 · 仅本菜单可用", w, theme.DIM, theme.BG)

    def get_hints(self) -> list[str]:
        return ["↑↓ 移动", "回车 选择"]
