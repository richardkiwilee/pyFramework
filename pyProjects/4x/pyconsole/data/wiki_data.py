"""百科数据：加载 + 模糊搜索（纯函数，可单测）。

WikiEntry 是条目数据类；search() 做子串包含模糊搜索（大小写不敏感），
匹配 name+summary+category，结果按 name 升序。find_match_ranges() 供高亮使用。
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import Any


@dataclass
class WikiEntry:
    id: str
    name: str
    category: str
    summary: str
    detail: str
    attrs: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, d: dict) -> "WikiEntry":
        return cls(
            id=str(d.get("id", "")),
            name=str(d.get("name", "")),
            category=str(d.get("category", "")),
            summary=str(d.get("summary", "")),
            detail=str(d.get("detail", "")),
            attrs=d.get("attrs", {}) if isinstance(d.get("attrs"), dict) else {},
        )


# 参与搜索的字段（不含 detail，detail 太长会干扰）
SEARCH_FIELDS = ("name", "summary", "category")


def load_entries(path: str) -> list[WikiEntry]:
    """从 JSON 加载条目。文件缺失/损坏返回空列表（不抛异常）。"""
    if not path or not os.path.isfile(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return []
    if not isinstance(data, list):
        return []
    out = []
    for item in data:
        if isinstance(item, dict):
            out.append(WikiEntry.from_dict(item))
    return out


def find_match_ranges(text: str, query: str) -> list[tuple[int, int]]:
    """在 text 中找出所有与 query 匹配（大小写不敏感）的子串区间 [start, end)。

    逐次从上次匹配后继续搜索，覆盖所有出现位置。用于高亮。
    """
    if not query:
        return []
    tl = text.lower()
    ql = query.lower()
    ranges: list[tuple[int, int]] = []
    start = 0
    while True:
        idx = tl.find(ql, start)
        if idx == -1:
            break
        ranges.append((idx, idx + len(ql)))
        start = idx + len(ql)
    return ranges


@dataclass
class SearchHit:
    entry: WikiEntry
    matched_fields: list[str]  # 哪些字段命中了


def search(entries: list[WikiEntry], query: str) -> list[SearchHit]:
    """模糊搜索：子串包含（大小写不敏感），匹配 name+summary+category。

    - 空 query 返回空列表（由调用方决定空状态显示）。
    - 结果按 name 升序。
    """
    q = query.strip()
    if not q:
        return []
    ql = q.lower()
    hits: list[SearchHit] = []
    for e in entries:
        matched = []
        for fname in SEARCH_FIELDS:
            val = getattr(e, fname, "")
            if ql in val.lower():
                matched.append(fname)
        if matched:
            hits.append(SearchHit(entry=e, matched_fields=matched))
    hits.sort(key=lambda h: h.entry.name.lower())
    return hits
