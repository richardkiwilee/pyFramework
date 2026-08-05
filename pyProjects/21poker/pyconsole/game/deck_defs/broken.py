"""套牌<损坏>：点数分布同基础，6/7/8/9 带「终局效果:损坏」。

损坏机制：轮末（终局效果阶段）从活跃牌池移除该牌。
注意：损坏牌若藏入袖子则不触发（不在卡槽上）。
"""
from ..cards import Card, rank_label, _standard_points, Suit
from ..effects import Effect, BROKEN

_BROKEN = Effect(kind=BROKEN, level=0)


def _make(rank: int, suit: str) -> Card:
    on_end = _BROKEN if rank in (6, 7, 8, 9) else None
    return Card(suit=suit, tag=rank_label(rank), points=_standard_points(rank),
                rank=rank, on_end=on_end)


SUIT_BROKEN = Suit(
    symbol="♦",
    name="损坏",
    cards=tuple(_make(r, "♦") for r in range(1, 14)),
    archetype="终局套",
)
