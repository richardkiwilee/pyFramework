"""21 点扑克牌纯逻辑（无 IO 依赖，可单测）。

- Card(rank, suit)：rank 1=A,2-10 面值,11=J,12=Q,13=K；suit ∈ ♠♥♦♣
- new_deck()：52 张（无大小王）
- shuffle(deck, rng)：原地洗牌（可注入 random.Random 便于测试）
- hand_score(cards)：返回 (score, busted)，A 取 1/11 最优、JQK=10、爆牌=score>21
- rank_label(rank)：1→"A" 等
- suit_color(suit)：花色对应 256 色码（红/黑）
"""
from __future__ import annotations

import random
from dataclasses import dataclass

from ..io import theme

SUITS = ("♠", "♥", "♦", "♣")
RED_SUITS = ("♥", "♦")


@dataclass(frozen=True)
class Card:
    rank: int   # 1..13
    suit: str   # ♠♥♦♣

    def __str__(self) -> str:
        return f"{rank_label(self.rank)}{self.suit}"


def rank_label(rank: int) -> str:
    """1→A,11→J,12→Q,13→K,其余→str(rank)。"""
    if rank == 1:
        return "A"
    if rank == 11:
        return "J"
    if rank == 12:
        return "Q"
    if rank == 13:
        return "K"
    return str(rank)


def new_deck() -> list[Card]:
    """返回 52 张新牌（无大小王），未洗牌。"""
    return [Card(r, s) for s in SUITS for r in range(1, 14)]


def shuffle(deck: list[Card], rng: random.Random | None = None) -> None:
    """原地洗牌。rng 可注入便于测试。"""
    r = rng if rng is not None else random
    r.shuffle(deck)


def hand_score(cards: list[Card]) -> tuple[int, bool]:
    """计算 21 点点数，返回 (score, busted)。

    A 先按 11 算；若总数 > 21，逐张把 A 改回 1（减 10）直到不爆或没有 A 可减。
    busted = score > 21。
    """
    total = 0
    aces = 0
    for c in cards:
        if c.rank == 1:
            total += 11
            aces += 1
        elif c.rank >= 11:   # J/Q/K
            total += 10
        else:
            total += c.rank
    # 把 A 从 11 降回 1 直到不爆或没有 A 可降
    while total > 21 and aces > 0:
        total -= 10
        aces -= 1
    return total, total > 21


def suit_color(suit: str) -> int:
    """花色对应 256 色码：红♥♦ 用 WARN(橙红)，黑♠♣ 用 FG。"""
    return theme.WARN if suit in RED_SUITS else theme.FG
