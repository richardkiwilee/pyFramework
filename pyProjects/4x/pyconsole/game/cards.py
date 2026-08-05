"""扑克牌纯逻辑（无 IO 依赖，可单测）。

阶段 7 泛化：点数脱离 rank 成为显式属性，支持多值牌（如 A=1|11、怪牌 8|0）。
套牌（Suit）/ 牌组定义（DeckDef）支持非标准点数与效果。

- Card(suit, tag, points, rank?, on_play?, on_activate?, on_end?)
- make_standard_card(rank, suit)：标准 13 张工厂（A=1|11 多值、JQK=10）
- Suit / DeckDef：套牌与共享牌组采样
- new_deck()：标准 52 张便捷工厂（基础套牌内部用）
- shuffle(deck, rng)：原地洗牌
- hand_score(cards)：泛化为多值选优——枚举候选乘积，≤21 取最大，否则取最小（busted）
- rank_label(rank)：1→"A" 等
- suit_color(suit)：花色对应 256 色码（红/黑）
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field
from itertools import product
from typing import TYPE_CHECKING

from ..io import theme

if TYPE_CHECKING:
    from .effects import Effect

SUITS = ("♠", "♥", "♦", "♣")
RED_SUITS = ("♥", "♦")


@dataclass(frozen=True)
class Card:
    suit: str                                   # 花色（标识所属套牌）
    tag: str                                    # 显示标签 "A"/"10"/"8|0"
    points: tuple[int, ...]                     # 多值候选；单值 (v,)；A=(1,11)
    rank: int | None = None                     # 标准套 1..13；怪套可为 None
    on_play: Effect | None = None
    on_activate: Effect | None = None
    on_end: Effect | None = None

    def __str__(self) -> str:
        return f"{self.tag}{self.suit}"


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


def _standard_points(rank: int) -> tuple[int, ...]:
    """标准扑克点数映射：A=(1,11)，JQK=(10,)，其余按面值。"""
    if rank == 1:
        return (1, 11)
    if rank >= 11:
        return (10,)
    return (rank,)


def make_standard_card(rank: int, suit: str) -> Card:
    """标准 13 张牌工厂：tag=rank_label，points 标准映射，无效果。"""
    return Card(suit=suit, tag=rank_label(rank), points=_standard_points(rank), rank=rank)


@dataclass(frozen=True)
class Suit:
    """一套牌定义：一种花色 + 自带一组牌（点数/标签可非标准）。"""
    symbol: str
    name: str
    cards: tuple[Card, ...]
    archetype: str = ""


@dataclass(frozen=True)
class DeckDef:
    """全部已定义套牌。sample_for 抽 n_players 套合并成单一共享牌组。"""
    suits: tuple[Suit, ...]

    def sample_for(self, n_players: int, rng: random.Random | None = None) -> list[Card]:
        """抽 n_players 套（不足则全用），合并洗牌成单一共享牌组。"""
        r = rng if rng is not None else random
        chosen = list(self.suits)
        r.shuffle(chosen)
        if len(chosen) > n_players:
            chosen = chosen[:n_players]
        deck: list[Card] = []
        for s in chosen:
            deck.extend(s.cards)
        r.shuffle(deck)
        return deck


def new_deck() -> list[Card]:
    """返回标准 52 张新牌（无大小王），未洗牌。基础套牌内部用。"""
    return [make_standard_card(r, s) for s in SUITS for r in range(1, 14)]


def shuffle(deck: list[Card], rng: random.Random | None = None) -> None:
    """原地洗牌。rng 可注入便于测试。"""
    r = rng if rng is not None else random
    r.shuffle(deck)


def hand_score(cards: list[Card]) -> tuple[int, bool]:
    """计算 21 点点数，返回 (score, busted)。

    多值泛化：枚举每张牌 points 候选的笛卡尔积，取所有组合的得分。
    - 存在 ≤21 的组合 → 取其中最大值，busted=False。
    - 全部 >21 → 取最小值，busted=True。
    空手 → (0, False)。
    """
    if not cards:
        return 0, False
    combos = [sum(combo) for combo in product(*(c.points for c in cards))]
    feasible = [s for s in combos if s <= 21]
    if feasible:
        return max(feasible), False
    return min(combos), True


def suit_color(suit: str) -> int:
    """花色对应 256 色码：红♥♦ 用 WARN(橙红)，黑♠♣ 用 FG。"""
    return theme.WARN if suit in RED_SUITS else theme.FG
