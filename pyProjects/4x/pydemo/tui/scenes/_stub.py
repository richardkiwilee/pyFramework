"""共享占位场景基类。

M2 阶段枢纽已能打开 K/W/H/J/C/A/Z/M 各子场景，但完整实现排在 M3-M9。
为让枢纽可跑、按键不崩，这里提供一个最小占位场景：画框 + 居中提示 + ESC 弹回。
后续里程碑会用真正的场景子类替换各文件里的 StubScene 派生。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, NONE, POP
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box, put_centered


class StubScene(Scene):
    allow_status_overlay = True

    def __init__(self, title: str = "建设中", message: str = "该场景尚在建设中") -> None:
        super().__init__()
        self._title = title
        self._message = message

    def on_enter(self, params: Any = None) -> None:
        self.params = params

    def handle_action(self, event) -> SceneResult:
        if event.action == actions.BACK:
            return POP()
        return NONE()

    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title=self._title)
        put_centered(buf, h // 2, self._message, w, theme.DIM, theme.BG)
        put_centered(buf, h // 2 + 2, "ESC 返回", w, theme.ACCENT, theme.BG)

    def get_hints(self) -> list[str]:
        return ["ESC 返回"]
