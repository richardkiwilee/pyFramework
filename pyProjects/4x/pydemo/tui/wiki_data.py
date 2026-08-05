"""百科数据适配器：复用框架的纯搜索函数，加载本游戏的百科 JSON。

框架 pyconsole.data.wiki_data 的 load_entries/search/find_match_ranges/
WikiEntry/SearchHit 都是纯函数/数据类，直接复用。只把数据源指向本游戏
的 tui_wiki.json。
"""
from __future__ import annotations

import os

from pyconsole.data.wiki_data import (
    WikiEntry,
    SearchHit,
    load_entries,
    search,
    find_match_ranges,
)

# pydemo/data/tui_wiki.json （与 buildings.json/heroes.json 等游戏数据同目录）
WIKI_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "data", "tui_wiki.json",
)


def load_game_wiki() -> list[WikiEntry]:
    """加载本游戏百科条目；文件缺失返回空列表（load_entries 内部吞错）。"""
    return load_entries(os.path.abspath(WIKI_PATH))


__all__ = [
    "WikiEntry", "SearchHit", "search", "find_match_ranges",
    "load_game_wiki", "WIKI_PATH",
]
