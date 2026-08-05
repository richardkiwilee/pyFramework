"""场景架构：Scene 基类 + 场景栈。

场景栈支持参数进栈 / 回值出栈，只渲染栈顶。每个场景自己定义 BACK（Esc）语义。
回值通道与清理分离：POP(return_value) 携带的回值由 App 交付给新栈顶的
on_return()；on_exit() 仅做出栈清理，不再承担回值职责。
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

    #: 是否允许按住 Tab 显示 overlay。栈顶为 False 时 Tab 无效（不读取也不渲染）。
    allow_status_overlay: bool = False

    #: 键提示栏位置。由 App 在渲染后于该行调用 render_hints() 绘制：
    #:   "bottom"  → 第 h-1 行（默认，兼容既有场景）
    #:   "top"     → 第 0 行
    #:   int       → 该绝对行
    #:   None      → App 不绘制提示栏（场景完全自管 chrome）
    hints_row: int | str | None = "bottom"

    def __init__(self) -> None:
        self.ctx: Any = None  # 由 App 在 on_enter 时注入

    def on_enter(self, params: Any = None) -> None:
        """进栈时调用。params 为上层传入的参数。"""
        self.params = params

    def on_exit(self) -> None:
        """出栈时调用，仅做清理（释放资源、复位状态）。

        本钩子不参与"返回值传递"——子场景向上层回传的值由 POP(return_value)
        显式携带，由 App 交付给上层 on_return()。on_exit 永远不应承担回值职责。
        """
        return None

    def on_return(self, value: Any) -> "SceneResult | None":
        """子场景 POP 后、本场景重回栈顶时调用。

        value 为子场景 POP(return_value) 显式携带的回值（无则为 None）。
        本钩子用于改本场景状态，但**可返回一个 SceneResult** 让 App 立即继续
        栈转换——例如直接 ``POP()`` 弹出自身回上层，或 ``PUSH(...)`` 推入一个
        消息框——从而避免"先存待决标志、再按一次键中转"的写法。返回 ``NONE()``
        或 ``None`` 表示本次不再产生栈动作。

        返回的 SceneResult 由 App 经 ``_apply_result`` 应用：若为 POP，会再
        次弹出本场景并把回值交给上层 on_return，递归直到某层返回 None。故用
        POP 连环返回多层是合法的；注意不要构成无限递归。
        """
        return None

    def handle_action(self, event: InputEvent) -> SceneResult:
        return NONE()

    def on_tick(self, now: float) -> None:
        """每帧调用一次（now 为 time.time()），用于场景内部定时推进。

        默认空实现。子类可在此驱动 AI 动画/定时任务，只改内部状态，不返回结果。
        """
        return None

    def render(self, buf: FrameBuffer) -> None:
        pass

    def render_overlay(self, buf: FrameBuffer, w: int, h: int) -> bool:
        """按住 Tab 时在场景画面之上叠加的内容（仅当 allow_status_overlay=True）。

        返回 True 表示场景已自行绘制 overlay（App 跳过通用"状态总览"面板）；
        返回 False / None 则 App 回退到通用面板。子类（如 21 点）可重写以画
        自己的 Tab 视图（牌堆总览 + 隐写卡背等）。
        """
        return False

    def render_hints(self, buf: FrameBuffer, y: int, w: int) -> None:
        """在 hints_row 指定行绘制键提示栏（由 App 在 render() 之后调用）。

        默认实现用 draw_hints 把 get_hints() 横排画出。子类可重写以自定义格式
        （例如键名与说明分色）；重写后 get_hints() 可不再用于渲染。
        """
        from ..io.widgets import draw_hints
        draw_hints(buf, y, w, self.get_hints())

    def get_hints(self) -> list[str]:
        return []

    @property
    def name(self) -> str:
        return self.__class__.__name__


class SceneStack:
    """场景栈。

    push 进栈时调用 scene.on_enter(params)；pop 出栈时调用 scene.on_exit()。
    场景之间的返回值不经 SceneStack 传递——POP(return_value) 携带的值由 App
    从 SceneResult 取出，直接交给新栈顶的 on_return()。
    """

    def __init__(self) -> None:
        self._stack: list[Scene] = []

    def push(self, scene: Scene, params: Any = None) -> None:
        scene.on_enter(params)
        self._stack.append(scene)

    def pop(self) -> Scene | None:
        """弹出栈顶并调用其 on_exit()（仅做清理）。返回被弹出的场景，供调用方
        在需要时引用；不承担任何返回值传递职责。"""
        if not self._stack:
            return None
        scene = self._stack.pop()
        scene.on_exit()
        return scene

    def top(self) -> Scene | None:
        return self._stack[-1] if self._stack else None

    def __len__(self) -> int:
        return len(self._stack)

    def is_empty(self) -> bool:
        return not self._stack
