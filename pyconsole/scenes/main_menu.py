"""主菜单场景：ASCII 标题 + 3 项菜单 + 选中/反选 + 回车确认。

- ↑↓ 切换焦点
- 空格 选中/反选当前项（多选高亮 [x]/[ ]）
- 回车 对焦点项执行（开始游戏→提示 / 百科→百科 / 退出→退出）
- H 进入百科（与"百科全书"等效）
- Tab 按住可显示状态总览 overlay
- Esc 不响应（主菜单是栈底）
"""
from __future__ import annotations

from typing import Any

from ..core import actions
from ..core.scene import Scene, SceneResult, PUSH, POP, QUIT, NONE
from ..io.buffer import FrameBuffer
from ..io import theme
from ..io.widgets import draw_box, put_centered, draw_hints

# ASCII 标题
TITLE = r"""
  ___                  _                                 ___
 | _ \___ _ _ _ __  __| |_ __  ___ _ _ ___ _ __  ___    | _ \_  _
 |  _/ _ \ '_| '  \/ _` | '  \/ -_) '_/ _ \ '  \ -_)   |  _/ || |
 |_| \___/_| |_|_|_\__,_|_|_|_\___|_| \___/_|_|_\___|   |_|  \_, |
                                                             |__/
"""

SUBTITLE = "控制台游戏框架 · 双缓冲渲染演示"


class MainMenuScene(Scene):
    allow_status_overlay = True

    def __init__(self) -> None:
        super().__init__()
        self.items = ["开始游戏", "百科全书", "退出游戏"]
        self.focus = 0
        self.selected: set[int] = set()

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
        if a == actions.SELECT:
            # 空格：选中/反选当前项
            if self.focus in self.selected:
                self.selected.remove(self.focus)
            else:
                self.selected.add(self.focus)
            return NONE()
        if a == actions.CONFIRM:
            return self._activate(self.focus)
        if a == actions.OPEN_WIKI:
            from .wiki import WikiScene
            return PUSH(WikiScene())
        if a == actions.BACK:
            # 主菜单是栈底，Esc 不响应
            return NONE()
        return NONE()

    def _activate(self, index: int) -> SceneResult:
        label = self.items[index]
        if label == "开始游戏":
            from .message import MessageScene
            return PUSH(MessageScene("游戏主循环尚未实现\n\n这是框架原型：双缓冲渲染、场景栈、\n键绑定、百科模糊搜索均已就绪。\n真正的游戏内容由你接入。"))
        if label == "百科全书":
            from .wiki import WikiScene
            return PUSH(WikiScene())
        if label == "退出游戏":
            return QUIT()
        return NONE()

    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        # 外框
        draw_box(buf, 0, 0, w, h, title="PyConsole Framework")
        # 标题
        ty = 3
        for i, line in enumerate(TITLE.strip("\n").split("\n")):
            put_centered(buf, ty + i, line, w, theme.HEADING, theme.BG)
        put_centered(buf, ty + 7, SUBTITLE, w, theme.DIM, theme.BG)

        # 菜单
        menu_y = ty + 11
        menu_w = 24
        mx = (w - menu_w) // 2
        for i, label in enumerate(self.items):
            y = menu_y + i
            checked = "x" if i in self.selected else " "
            marker = ">" if i == self.focus else " "
            if i == self.focus:
                # 焦点项：反色背景
                text = f" {marker} [{checked}] {label} "
                pad = menu_w - len(text) * 0  # 中文双宽，用 put_text 居中
                buf.fill_rect(mx, y, menu_w, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                tx = mx + (menu_w - self._disp_width(text)) // 2
                buf.put_text(tx, y, text, theme.SELECTED_FG, theme.SELECTED_BG)
            else:
                text = f" {marker} [{checked}] {label}"
                tx = mx + (menu_w - self._disp_width(text)) // 2
                buf.put_text(tx, y, text, theme.FG, theme.BG)

        # 说明
        note_y = menu_y + len(self.items) + 2
        put_centered(buf, note_y, "空格 选中/反选 · 回车 确认 · H 百科 · 按住 Tab 状态总览", w, theme.DIM, theme.BG)

    @staticmethod
    def _disp_width(s: str) -> int:
        from ..io.width import text_width
        return text_width(s)

    def get_hints(self) -> list[str]:
        return ["↑↓ 移动", "空格 选中/反选", "回车 确认", "H 百科", "Tab 状态总览", "Esc 不响应"]
