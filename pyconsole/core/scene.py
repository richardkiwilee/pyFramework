"""场景架构：Scene 基类 + 场景栈。

场景栈支持参数进栈 / 返回值出栈，只渲染栈顶。每个场景自己定义 BACK（Esc）语义。
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from ..io.buffer import FrameBuffer
from .actions import InputEvent


@dataclass
class SceneResult:
    """handle_action 的返回值，指示主循环如何操作场景栈。"""
    kind: str = "none"          # none / push / pop / quit
    scene: "Scene | None" = None
    params: Any = None
    return_value: Any = None


# 结果工厂
def NONE() -> SceneResult:
    return SceneResult(kind="none")


def PUSH(scene: "Scene", params: Any = None) -> SceneResult:
    return SceneResult(kind="push", scene=scene, params=params)


def POP(return_value: Any = None) -> SceneResult:
    return SceneResult(kind="pop", return_value=return_value)


def QUIT() -> SceneResult:
    return SceneResult(kind="quit")


class Scene:
    """场景基类。子类重写钩子方法。"""

    #: 是否允许按住 Tab 显示状态总览 overlay
    allow_status_overlay: bool = False

    def __init__(self) -> None:
        self.ctx: Any = None  # 由 App 在 on_enter 时注入

    def on_enter(self, params: Any = None) -> None:
        """进栈时调用。params 为上层传入的参数。"""
        self.params = params

    def on_exit(self) -> Any:
        """出栈时调用，返回值会传给上层场景。"""
        return None

    def handle_action(self, event: InputEvent) -> SceneResult:
        return NONE()

    def render(self, buf: FrameBuffer) -> None:
        pass

    def get_hints(self) -> list[str]:
        return []

    @property
    def name(self) -> str:
        return self.__class__.__name__


class SceneStack:
    """场景栈。"""

    def __init__(self) -> None:
        self._stack: list[Scene] = []

    def push(self, scene: Scene, params: Any = None) -> None:
        scene.on_enter(params)
        self._stack.append(scene)

    def pop(self) -> Any:
        if not self._stack:
            return None
        scene = self._stack.pop()
        return scene.on_exit()

    def top(self) -> Scene | None:
        return self._stack[-1] if self._stack else None

    def __len__(self) -> int:
        return len(self._stack)

    def is_empty(self) -> bool:
        return not self._stack
