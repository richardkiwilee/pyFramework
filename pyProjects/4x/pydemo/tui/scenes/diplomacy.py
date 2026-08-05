"""外交场景（M9 将作为占位/后续扩展）。

按 操作逻辑.md：外交为占位。M2 这里用 StubScene 让枢纽 J 键可打开。
"""
from __future__ import annotations

from ._stub import StubScene


class DiplomacyScene(StubScene):
    def __init__(self) -> None:
        super().__init__(title="外交", message="外交系统尚在建设中")
