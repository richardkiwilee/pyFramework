"""隐写卡背单元测试：编码→解码可逆 + FrameBuffer 渲染不崩。"""
import unittest

from pyconsole.game import card_back
from pyconsole.game.card_back import (
    RANKS, SUITS, draw_card_back, decode_card_back, draw_card_back_buf,
    SUIT_TO_CODE,
)
from pyconsole.game.cards import Card, SUITS as CARD_SUITS, rank_label
from pyconsole.io.buffer import FrameBuffer


class TestRoundTrip(unittest.TestCase):
    def test_all_52_cards_round_trip(self):
        for rank in RANKS:
            for suit in SUITS:
                code = f"{rank}{suit}"
                art = draw_card_back(code, 19, 11)
                self.assertEqual(decode_card_back(art), code, f"{code} round-trip failed")

    def test_decoding_is_stable(self):
        # 同一张牌多次编码应完全一致
        a1 = draw_card_back("7S", 19, 11)
        a2 = draw_card_back("7S", 19, 11)
        self.assertEqual(a1, a2)

    def test_different_cards_different_art(self):
        # 不同牌面应产生不同图案
        self.assertNotEqual(draw_card_back("AS", 19, 11), draw_card_back("AH", 19, 11))
        self.assertNotEqual(draw_card_back("AS", 19, 11), draw_card_back("2S", 19, 11))

    def test_invalid_card_raises(self):
        with self.assertRaises(ValueError):
            card_back.parse_card("X9")  # 非法点数 + 非法花色


class TestCardIntegration(unittest.TestCase):
    def test_suit_mapping_covers_all_card_suits(self):
        # card_back 的编码表必须能覆盖 cards.py 的全部花色
        for s in CARD_SUITS:
            self.assertIn(s, SUIT_TO_CODE, f"花色 {s} 缺少编码映射")

    def test_suit_code_order_distinct_from_cards(self):
        # 隐写 SUITS 顺序故意与 cards.SUITS 不同（♦ ♣ 顺序交换），
        # 故不能用下标互转；这里仅断言两者确实不同，提醒用显式 dict。
        self.assertNotEqual(list(SUITS), list(CARD_SUITS))


class TestBufferRender(unittest.TestCase):
    def test_draw_card_back_buf_renders_without_error(self):
        buf = FrameBuffer(80, 30)
        draw_card_back_buf(buf, 5, 5, Card(1, "♠"))
        # 卡背区域不应全空白
        drew = False
        for y in range(5, 5 + 11):
            for x in range(5, 5 + 19):
                if buf.cells[y][x].char not in ("", " "):
                    drew = True
                    break
            if drew:
                break
        self.assertTrue(drew)

    def test_draw_card_back_buf_encodes_top_card(self):
        # 抽牌堆顶是 A♠ 时，overlay 左上角卡背应可被解码回 A♠
        buf = FrameBuffer(80, 30)
        draw_card_back_buf(buf, 0, 0, Card(1, "♠"), width=19, height=11)
        # 从缓冲读回 ASCII
        lines = []
        for y in range(11):
            lines.append("".join(buf.cells[y][x].char or " " for x in range(19)))
        art = "\n".join(lines)
        self.assertEqual(decode_card_back(art), "AS")

    def test_all_cards_render_and_decode_from_buf(self):
        # 每张牌画进缓冲后都能从缓冲读回并正确解码
        for r in range(1, 14):
            for s in CARD_SUITS:
                buf = FrameBuffer(25, 15)
                draw_card_back_buf(buf, 2, 2, Card(r, s), width=19, height=11)
                lines = []
                for y in range(2, 2 + 11):
                    lines.append("".join(buf.cells[y][x].char or " " for x in range(2, 2 + 19)))
                art = "\n".join(lines)
                expected = f"{rank_label(r)}{SUIT_TO_CODE[s]}"
                self.assertEqual(decode_card_back(art), expected,
                                 f"rank={r} suit={s} decode mismatch")


if __name__ == "__main__":
    unittest.main()
