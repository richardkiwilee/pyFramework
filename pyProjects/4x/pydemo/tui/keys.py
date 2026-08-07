"""键绑定：在框架默认绑定之上叠加游戏专属键。

构造 KeyResolver(bindings=...) 直接传入合并后的映射，绕过 load_bindings
对 actions.ALL_ACTIONS 的校验（见 pyconsole/core/keys.py:73）。
字母键的解析路径（keys.py:84-88）：可打印字符到达时 key_name=="char"，
resolver 查 char.lower() 是否在 bindings 中——所以 "k" 绑定到
OPEN_TECH 后，按 K 会产生 InputEvent("open_tech", "")。
"""
from __future__ import annotations

from pyconsole.core.keys import KeyResolver, DEFAULT_BINDINGS

from . import actions as A

# 在默认绑定（含 h→OPEN_WIKI、space→SELECT、方向/回车/esc/退格/PgUp/PgDn）之上叠加
BINDINGS: dict[str, str] = {
    **DEFAULT_BINDINGS,
    "k": A.OPEN_TECH,
    "w": A.OPEN_CULTURE,
    "j": A.OPEN_DIPLOMACY,
    "c": A.OPEN_STRONGHOLD,
    "a": A.OPEN_ARMY,
    "z": A.OPEN_RECRUIT,
    "m": A.OPEN_MAP,
    "x": A.OPEN_UNIT,
    "v": A.OPEN_STRONGHOLD_OVERVIEW,
    "n": A.NEW_ARMY,
    "t": A.END_TURN,
    "1": A.FILTER_1,
    "2": A.FILTER_2,
    "3": A.FILTER_3,
    "4": A.FILTER_4,
}

resolver = KeyResolver(bindings=BINDINGS)
