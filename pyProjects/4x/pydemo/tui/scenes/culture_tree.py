"""文化树场景：与科技树同构，数据源换成 cultures.json，学习记录用
ctrl.culture_learned。

复用 TreeScene 的全部交互/渲染逻辑，仅覆盖 TITLE / DATA_PATH / _learned_set。
"""
from __future__ import annotations

import os

from .. import controller as ctrl_mod
from .tech_tree import TreeScene


class CultureTreeScene(TreeScene):
    TITLE = "文化树"
    DATA_PATH = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
        "data", "cultures.json",
    )

    def _learned_set(self) -> set[str]:
        return ctrl_mod.ctrl.culture_learned
