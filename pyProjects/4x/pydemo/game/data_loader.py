"""
数据定义加载与 mod 层叠覆盖。

基础定义从 data/ 下的 json 加载,mod 从 mods/ 下的 json 同名覆盖。
层叠顺序:基础 data -> mods 按目录名排序顺序加载,后者覆盖前者。

"同名覆盖"的粒度:每类定义以 dict[id, record] 组织;mod 文件中同 id 的 record
整体替换基础定义(不做字段级合并),这与"声明式数据 + 同名覆盖"设计一致。
新增内容 = mod 中放一个基础里没有的 id。
"""
from __future__ import annotations
import json
import os
from copy import deepcopy
from typing import Any

BASE_DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")
MODS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "mods")

# 所有受数据驱动 + mod 覆盖的定义文件名(不带 .json)
DEFINITION_FILES = [
    "resources",
    "buildings",
    "unit_types",
    "heroes",
    "skills",
    "events",
    "synergies",
    "terrain",
    "artifacts",
]


def _load_one(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    """同名 id 整体覆盖;新增 id 直接加入。"""
    result = deepcopy(base)
    for k, v in overlay.items():
        result[k] = deepcopy(v)
    return result


def load_definitions() -> dict[str, dict[str, Any]]:
    """
    返回 {file_name: {id: record}} 结构。
    先加载基础 data/,再按 mods/ 子目录排序依次覆盖。
    """
    defs: dict[str, dict[str, Any]] = {name: {} for name in DEFINITION_FILES}

    # 基础定义
    for name in DEFINITION_FILES:
        path = os.path.join(BASE_DATA_DIR, f"{name}.json")
        if os.path.isfile(path):
            defs[name] = _load_one(path)

    # mod 层叠覆盖:mods/ 下每个子目录是一个 mod,按目录名排序加载
    if os.path.isdir(MODS_DIR):
        mod_dirs = sorted(d for d in os.listdir(MODS_DIR)
                         if os.path.isdir(os.path.join(MODS_DIR, d)))
        for mod_dir in mod_dirs:
            mod_path = os.path.join(MODS_DIR, mod_dir)
            for name in DEFINITION_FILES:
                fpath = os.path.join(mod_path, f"{name}.json")
                if os.path.isfile(fpath):
                    overlay = _load_one(fpath)
                    defs[name] = _merge(defs[name], overlay)

    return defs
