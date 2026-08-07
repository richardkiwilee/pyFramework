"""游戏专属动作常量。

这些字符串不需要在 pyconsole.core.actions.ALL_ACTIONS 中注册——
我们用 KeyResolver(bindings=...) 直接构造，绕过 load_bindings 的校验
（见 pyconsole/core/keys.py）。场景按 event.action 分支。

导航类动作（UP/DOWN/LEFT/RIGHT/SELECT/CONFIRM/BACK/BACKSPACE/OPEN_WIKI/
SCROLL_UP/SCROLL_DOWN/CHAR）复用 pyconsole.core.actions。
"""
from __future__ import annotations

# 主场景绑定按键 → 打开子场景
OPEN_TECH = "open_tech"            # K 科技树
OPEN_CULTURE = "open_culture"      # W 文化树
OPEN_DIPLOMACY = "open_diplomacy"  # J 外交
OPEN_STRONGHOLD = "open_stronghold"  # C 据点一览
OPEN_ARMY = "open_army"            # A 部队一栏
OPEN_RECRUIT = "open_recruit"       # Z 招募一览
OPEN_MAP = "open_map"              # M 地图一览
OPEN_UNIT = "open_unit"             # X 单位一览(§3)
OPEN_STRONGHOLD_OVERVIEW = "open_stronghold_overview"  # V 据点总览(§4)

# 部队场景：仅在最左侧窗口时可用
NEW_ARMY = "new_army"              # N 新建部队

# 主场景：结束本回合（AI 行动 + 时间推进）
END_TURN = "end_turn"              # T 下一回合

# 列表筛选（科技/文化树、部队一栏）
FILTER_1 = "filter_1"             # 1
FILTER_2 = "filter_2"             # 2
FILTER_3 = "filter_3"             # 3
FILTER_4 = "filter_4"             # 4
