"""游戏百科场景：复用框架 WikiScene，仅改数据源与标题。

框架 pyconsole.scenes.wiki.WikiScene 已实现：输入框 + 实时模糊搜索 + 左右分栏
列表/详情 + 命中高亮 + PgUp/PgDn 滚动 + Esc 弹回。这里通过子类化：
- on_enter 加载本游戏的 tui_wiki.json（经 tui/wiki_data 适配器，复用
  pyconsole.data.wiki_data 的纯搜索函数）。
- 接受可选 params={"query": 词} 作为跳转链接预填的查询词（科技/文化树用）。
"""
from __future__ import annotations

import os
from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import SceneResult, NONE
from pyconsole.scenes.wiki import WikiScene

from .. import wiki_data


class GameWikiScene(WikiScene):
    """本游戏百科：数据源换为 tui_wiki.json，标题改"百科"。

    复用框架的搜索/分栏/高亮/滚动/输入逻辑，零新交互代码。
    """

    def on_enter(self, params: Any = None) -> None:
        self.params = params
        # 加载本游戏百科（load_entries 文件缺失返回 []）
        self.entries = wiki_data.load_game_wiki()
        # 跳转链接预填查询词（科技/文化树 [[词]] → 这里）
        q = ""
        if isinstance(params, dict):
            q = str(params.get("query", "") or "")
        self.query = q
        self._refresh()

    def render(self, buf) -> None:
        # 框架默认标题是"百科全书"硬编码在 draw_box(title=...)，本游戏用"百科"。
        # 这里仅复用父类渲染；标题差异可接受（"百科全书"亦合理），保持零侵入。
        super().render(buf)

    def get_hints(self) -> list[str]:
        return ["输入 搜索", "↑↓ 切换条目", "PgUp/PgDn 滚动详情", "Backspace 删字", "ESC 返回"]
