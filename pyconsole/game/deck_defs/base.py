"""套牌<基础>：标准 13 张扑克牌，A=1|11 多值，其余无效果。"""
from ..cards import Suit, make_standard_card

SUIT_BASE = Suit(
    symbol="♠",
    name="基础",
    cards=tuple(make_standard_card(r, "♠") for r in range(1, 14)),
    archetype="点数套",
)
