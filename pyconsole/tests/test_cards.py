"""21 点扑克牌纯逻辑单元测试。"""
import random
import unittest

from pyconsole.game.cards import (
    Card, SUITS, hand_score, new_deck, rank_label, shuffle, suit_color,
)
from pyconsole.io import theme


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


class TestNewDeck(unittest.TestCase):
    def test_has_52_cards(self):
        d = new_deck()
        self.assertEqual(len(d), 52)

    def test_four_suits_thirteen_ranks(self):
        d = new_deck()
        for s in SUITS:
            ranks = sorted(c.rank for c in d if c.suit == s)
            self.assertEqual(ranks, list(range(1, 14)))

    def test_no_jokers(self):
        d = new_deck()
        for c in d:
            self.assertTrue(1 <= c.rank <= 13)
            self.assertIn(c.suit, SUITS)

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
    def _c(self, rank, suit="♠"):
        return Card(rank, suit)

    def test_empty_hand(self):
        self.assertEqual(hand_score([]), (0, False))

    def test_number_cards(self):
        self.assertEqual(hand_score([self._c(5), self._c(7)]), (12, False))

    def test_face_cards_are_ten(self):
        self.assertEqual(hand_score([self._c(11), self._c(12), self._c(13)]), (30, True))

    def test_ace_as_eleven(self):
        # A + 10 = 21（A 取 11）
        self.assertEqual(hand_score([self._c(1), self._c(10)]), (21, False))

    def test_ace_downgrade_to_one(self):
        # A + A + 9 = 21（一张 A 取 11，另一张取 1）
        self.assertEqual(hand_score([self._c(1), self._c(1), self._c(9)]), (21, False))

    def test_multiple_aces(self):
        # 4 个 A = 14（一张 11 + 三张 1）
        self.assertEqual(hand_score([self._c(1), self._c(1), self._c(1), self._c(1)]), (14, False))

    def test_bust(self):
        self.assertEqual(hand_score([self._c(10), self._c(9), self._c(5)]), (24, True))

    def test_ace_prevents_bust(self):
        # A + 6 + 8 = 15（A 取 1，否则 25 爆）
        self.assertEqual(hand_score([self._c(1), self._c(6), self._c(8)]), (15, False))

    def test_ace_cannot_prevent_bust(self):
        # A + 10 + 9 + 5 = 25（A 取 1 后仍爆）
        self.assertEqual(hand_score([self._c(1), self._c(10), self._c(9), self._c(5)]), (25, True))

    def test_blackjack(self):
        self.assertEqual(hand_score([self._c(1), self._c(13)]), (21, False))


class TestSuitColor(unittest.TestCase):
    def test_red_suits(self):
        self.assertEqual(suit_color("♥"), theme.WARN)
        self.assertEqual(suit_color("♦"), theme.WARN)

    def test_black_suits(self):
        self.assertEqual(suit_color("♠"), theme.FG)
        self.assertEqual(suit_color("♣"), theme.FG)


if __name__ == "__main__":
    unittest.main()
