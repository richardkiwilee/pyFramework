"""App：主循环、渲染调度、Tab overlay 注入、场景栈动作分发。"""
from __future__ import annotations

import time
from typing import Any

from ..io.buffer import FrameBuffer
from ..io.display import Display
from ..io import input as input_mod
from ..io import theme
from ..io.widgets import draw_hints
from .keys import KeyResolver
from .scene import Scene, SceneStack, SceneResult
from . import overlay as overlay_mod
from .game_state import get_state

# 主循环无键时的休眠（秒），让出 CPU
IDLE_SLEEP = 0.015

SCREEN_W = 100
SCREEN_H = 30


class App:
    def __init__(self, resolver: KeyResolver | None = None,
                 display: Display | None = None) -> None:
        self.w = SCREEN_W
        self.h = SCREEN_H
        self.display = display or Display(self.w, self.h)
        self.resolver = resolver or KeyResolver()
        self.stack = SceneStack()
        self.running = False

    # ---- 生命周期 ----
    def startup(self) -> None:
        self.display.startup()

    def shutdown(self) -> None:
        self.display.cleanup()

    def run(self, root_scene: Scene, params: Any = None) -> None:
        self.stack.push(root_scene, params)
        self.running = True
        try:
            self.loop()
        finally:
            self.shutdown()

    # ---- 主循环 ----
    def loop(self) -> None:
        had_input = False
        while self.running and not self.stack.is_empty():
            top = self.stack.top()
            assert top is not None
            state = get_state()

            # 1. Tab overlay 轮询（模态）
            show_overlay = (top.allow_status_overlay and input_mod.poll_tab_held())

            # 1b. 推进场景内部定时状态（AI 动画等），不返回结果
            top.on_tick(time.time())

            # 2. 读一个按键（overlay 显示时不派发）
            had_input = False
            if not show_overlay:
                raw = input_mod.read_key()
                if raw is not None:
                    key_name, char = raw
                    event = self.resolver.resolve(key_name, char)
                    if event is not None:
                        result = top.handle_action(event)
                        self._apply_result(result)
                        had_input = True

            # 3. 渲染
            buf = self.display.begin_frame()
            top.render(buf)
            if show_overlay:
                overlay_mod.render(
                    buf, self.w, self.h,
                    scene_name=top.name,
                    stack_depth=len(self.stack),
                    state=state,
                    bindings_count=len(self.resolver.bindings),
                )
            # 底部键提示栏（overlay 显示时不画，避免干扰）
            if not show_overlay:
                draw_hints(buf, self.h - 1, self.w, top.get_hints())

            self.display.present()

            # 4. 无输入时轻休眠
            if not had_input and not show_overlay:
                time.sleep(IDLE_SLEEP)
            elif show_overlay:
                time.sleep(IDLE_SLEEP)

    # ---- 动作分发 ----
    def _apply_result(self, result: SceneResult) -> None:
        if result is None or result.kind == "none":
            return
        if result.kind == "push":
            if result.scene is not None:
                self.stack.push(result.scene, result.params)
        elif result.kind == "pop":
            ret = self.stack.pop()
            # 把返回值交给新的栈顶（若有）
            new_top = self.stack.top()
            if new_top is not None and hasattr(new_top, "on_return"):
                new_top.on_return(ret)  # type: ignore[attr-defined]
        elif result.kind == "quit":
            self.running = False
