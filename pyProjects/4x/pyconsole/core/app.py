"""App：主循环、渲染调度、Tab overlay 注入、场景栈动作分发。"""
from __future__ import annotations

import time
from typing import Any

from ..io.buffer import FrameBuffer
from ..io.display import Display
from ..io import input as input_mod
from ..io import theme
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
                        # 应用结果（PUSH/POP/连环 on_return）后栈顶可能已变：
                        # 本帧必须渲染新栈顶，否则会画旧场景（如招募成功 PUSH 聚贤庄
                        # 后仍画招募场景）。重新取栈顶。
                        new_top = self.stack.top()
                        if new_top is not None and new_top is not top:
                            top = new_top
                            # overlay 归属也随之重算（新栈顶可能不允许 overlay）
                            show_overlay = (top.allow_status_overlay and input_mod.poll_tab_held())

            # 3. 渲染
            buf = self.display.begin_frame()
            top.render(buf)
            if show_overlay:
                # 场景自定义 overlay 优先；返回 False 则用通用"状态总览"面板
                custom = top.render_overlay(buf, self.w, self.h)
                if not custom:
                    overlay_mod.render(
                        buf, self.w, self.h,
                        scene_name=top.name,
                        stack_depth=len(self.stack),
                        state=state,
                        bindings_count=len(self.resolver.bindings),
                    )
            # 键提示栏：场景用 hints_row 声明位置（"bottom"/"top"/int/None）。
            # App 在场景 render() 之后调用 render_hints() 在该行绘制；None 则跳过。
            if not show_overlay and top.hints_row is not None:
                y = (self.h - 1) if top.hints_row == "bottom" else (
                    0 if top.hints_row == "top" else int(top.hints_row))
                if 0 <= y < self.h:
                    top.render_hints(buf, y, self.w)

            self.display.present()

            # 4. 无输入时轻休眠
            if not had_input and not show_overlay:
                time.sleep(IDLE_SLEEP)
            elif show_overlay:
                time.sleep(IDLE_SLEEP)

    # ---- 动作分发 ----
    def _apply_result(self, result: SceneResult) -> None:
        """应用一个 SceneResult 到场景栈。

        POP 时先弹栈（on_exit 仅清理），再把 return_value 交给新栈顶 on_return；
        on_return 可返回 SceneResult 触发后续栈转换（如直接再 POP 自身回上层），
        此时递归应用，直到某层 on_return 返回 None/NONE（最多层数=栈深，自然终止）。
        """
        if result is None or result.kind == "none":
            return
        if result.kind == "push":
            if result.scene is not None:
                self.stack.push(result.scene, result.params)
        elif result.kind == "pop":
            self.stack.pop()
            ret = result.return_value
            new_top = self.stack.top()
            if new_top is not None:
                next_result = new_top.on_return(ret)
                if next_result is not None and next_result.kind != "none":
                    self._apply_result(next_result)  # 递归：连环返回
        elif result.kind == "quit":
            self.running = False
