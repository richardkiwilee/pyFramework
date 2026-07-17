"""21 点扑克牌纯逻辑单元测试（阶段 7：多值泛化 + 套牌）。"""
import random
import unittest

from pyconsole.game.cards import (
    Card, SUITS, hand_score, new_deck, make_standard_card, rank_label,
    shuffle, suit_color, Suit, DeckDef,
)
from pyconsole.game.effects import Effect
from pyconsole.io import theme


def _c(rank, suit="♠"):
    """标准牌工厂（替代旧 Card(rank, suit) 位置构造）。"""
    return make_standard_card(rank, suit)


class TestRankLabel(unittest.TestCase):
    def test_face_cards(self):
        self.assertEqual(rank_label(1), "A")
        self.assertEqual(rank_label(11), "J")
        self.assertEqual(rank_label(12), "Q")
        self.assertEqual(rank_label(13), "K")

    def test_numbers(self):
        self.assertEqual(rank_label(2), "2")
        self.assertEqual(rank_label(10), "10")
        self.assertEqual(rank_label(7), "7")


class TestMakeStandardCard(unittest.TestCase):
    def test_ace_is_multi_value(self):
        a = make_standard_card(1, "♠")
        self.assertEqual(a.points, (1, 11))
        self.assertEqual(a.tag, "A")
        self.assertEqual(a.rank, 1)

    def test_face_cards_ten(self):
        for r in (11, 12, 13):
            self.assertEqual(make_standard_card(r, "♠").points, (10,))

    def test_number_cards_face_value(self):
        self.assertEqual(make_standard_card(7, "♠").points, (7,))
        self.assertEqual(make_standard_card(10, "♠").points, (10,))

    def test_no_effects_by_default(self):
        c = make_standard_card(5, "♥")
        self.assertIsNone(c.on_play)
        self.assertIsNone(c.on_activate)
        self.assertIsNone(c.on_end)


class TestNewDeck(unittest.TestCase):
    def test_has_52_cards(self):
        d = new_deck()
        self.assertEqual(len(d), 52)

    def test_four_suits_thirteen_ranks(self):
        d = new_deck()
        for s in SUITS:
            ranks = sorted(c.rank for c in d if c.suit == s)
            self.assertEqual(ranks, list(range(1, 14)))

    def test_cards_unique(self):
        d = new_deck()
        self.assertEqual(len({(c.rank, c.suit) for c in d}), 52)

    def test_shuffle_changes_order_but_not_contents(self):
        d1 = new_deck()
        d2 = list(d1)
        shuffle(d2, random.Random(123))
        key = lambda c: (c.rank, c.suit)
        self.assertEqual(sorted(d1, key=key), sorted(d2, key=key))  # 内容不变
        self.assertNotEqual(d1, d2)                                # 顺序改变


class TestHandScore(unittest.TestCase):
    def test_empty_hand(self):
        self.assertEqual(hand_score([]), (0, False))

    def test_number_cards(self):
        self.assertEqual(hand_score([_c(5), _c(7)]), (12, False))

    def test_face_cards_are_ten(self):
        self.assertEqual(hand_score([_c(11), _c(12), _c(13)]), (30, True))

    def test_ace_as_eleven(self):
        # A + 10 = 21（A 取 11）
        self.assertEqual(hand_score([_c(1), _c(10)]), (21, False))

    def test_ace_downgrade_to_one(self):
        # A + A + 9 = 21（一张 A 取 11，另一张取 1）
        self.assertEqual(hand_score([_c(1), _c(1), _c(9)]), (21, False))

    def test_multiple_aces(self):
        # 4 个 A = 14（一张 11 + 三张 1）
        self.assertEqual(hand_score([_c(1), _c(1), _c(1), _c(1)]), (14, False))

    def test_bust(self):
        self.assertEqual(hand_score([_c(10), _c(9), _c(5)]), (24, True))

    def test_ace_prevents_bust(self):
        # A + 6 + 8 = 15（A 取 1，否则 25 爆）
        self.assertEqual(hand_score([_c(1), _c(6), _c(8)]), (15, False))

    def test_ace_cannot_prevent_bust(self):
        # A + 10 + 9 + 5 = 25（A 取 1 后仍爆）
        self.assertEqual(hand_score([_c(1), _c(10), _c(9), _c(5)]), (25, True))

    def test_blackjack(self):
        self.assertEqual(hand_score([_c(1), _c(13)]), (21, False))

    def test_multi_value_picks_optimal_not_bust(self):
        # 怪牌 8|0 + 9 = 17（取 8），而非 0+9=9
        eight_or_zero = Card(suit="★", tag="8|0", points=(8, 0))
        nine = _c(9)
        self.assertEqual(hand_score([eight_or_zero, nine]), (17, False))

    def test_multi_value_picks_lower_to_avoid_bust(self):
        # 8|0 + 10 + 5：取 8→23 爆；取 0→15 不爆 → 15
        eight_or_zero = Card(suit="★", tag="8|0", points=(8, 0))
        self.assertEqual(hand_score([eight_or_zero, _c(10), _c(5)]), (15, False))

    def test_multi_value_all_bust_picks_min(self):
        # 三张 8|0：8+8+8=24 爆，0+0+0=0；应取最小 0（busted 仅当 >21）
        # 但 0 不爆，所以 feasible 含 0/8/16 的组合 → max feasible
        # 8+8+0=16, 8+0+0=8, 0+0+0=0, 8+8+8=24(爆) → max feasible=16
        e = Card(suit="★", tag="8|0", points=(8, 0))
        self.assertEqual(hand_score([e, e, e]), (16, False))

    def test_negative_points(self):
        # 非正点数套牌：负点数牌
        neg = Card(suit="☾", tag="-3", points=(-3,))
        self.assertEqual(hand_score([neg, _c(10)]), (7, False))
        self.assertEqual(hand_score([neg]), (-3, False))


class TestSuitColor(unittest.TestCase):
    def test_red_suits(self):
        self.assertEqual(suit_color("♥"), theme.WARN)
        self.assertEqual(suit_color("♦"), theme.WARN)

    def test_black_suits(self):
        self.assertEqual(suit_color("♠"), theme.FG)
        self.assertEqual(suit_color("♣"), theme.FG)


class TestDeckDef(unittest.TestCase):
    def setUp(self):
        from pyconsole.game.deck_defs import DECK_DEF
        self.dd = DECK_DEF

    def test_sample_size_equals_players_times_13(self):
        # 每套 13 张，抽 N 套 → 13*N
        d2 = self.dd.sample_for(2, random.Random(1))
        self.assertEqual(len(d2), 26)
        d3 = self.dd.sample_for(3, random.Random(1))
        self.assertEqual(len(d3), 39)

    def test_sample_chooses_distinct_suits_when_enough(self):
        # 3 套抽 2：选中的 2 套花色应不同（基础♠/剥削♥/损坏♦）
        d = self.dd.sample_for(2, random.Random(1))
        suits = {c.suit for c in d}
        self.assertEqual(len(suits), 2)

    def test_sample_too_many_players_uses_all(self):
        # 5 玩家但只有 3 套 → 用全部 3 套 = 39 张
        d = self.dd.sample_for(5, random.Random(1))
        self.assertEqual(len(d), 39)

    def test_exploit_cards_have_effect(self):
        from pyconsole.game.effects import EXPLOIT
        from pyconsole.game.deck_defs.exploit import SUIT_EXPLOIT
        # 2/3/4/5 带 on_play=剥削1
        for r in (2, 3, 4, 5):
            c = next(c for c in SUIT_EXPLOIT.cards if c.rank == r)
            self.assertIsNotNone(c.on_play)
            self.assertEqual(c.on_play.kind, EXPLOIT)
            self.assertEqual(c.on_play.level, 1)
        # 其余无效果
        for r in (1, 6, 13):
            c = next(c for c in SUIT_EXPLOIT.cards if c.rank == r)
            self.assertIsNone(c.on_play)

    def test_broken_cards_have_effect(self):
        from pyconsole.game.effects import BROKEN
        from pyconsole.game.deck_defs.broken import SUIT_BROKEN
        for r in (6, 7, 8, 9):
            c = next(c for c in SUIT_BROKEN.cards if c.rank == r)
            self.assertIsNotNone(c.on_end)
            self.assertEqual(c.on_end.kind, BROKEN)
        for r in (1, 5, 13):
            c = next(c for c in SUIT_BROKEN.cards if c.rank == r)
            self.assertIsNone(c.on_end)


if __name__ == "__main__":
    unittest.main()
