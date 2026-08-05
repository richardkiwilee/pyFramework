"""测试后缓冲（put_text 双宽、截断等）。"""
import unittest

from pyconsole.io.buffer import FrameBuffer, Cell
from pyconsole.io import theme


class TestBuffer(unittest.TestCase):
    def test_put_text_ascii(self):
        b = FrameBuffer(10, 1)
        end = b.put_text(0, 0, "abc")
        self.assertEqual(end, 3)
        self.assertEqual(b.cells[0][0].char, "a")
        self.assertEqual(b.cells[0][2].char, "c")
        # 其余为空格
        self.assertEqual(b.cells[0][3].char, " ")

    def test_put_text_cjk_double_width(self):
        b = FrameBuffer(10, 1)
        end = b.put_text(0, 0, "中文")
        self.assertEqual(end, 4)
        self.assertEqual(b.cells[0][0].char, "中")
        # 第二格为占位（空字符串）
        self.assertEqual(b.cells[0][1].char, "")
        self.assertEqual(b.cells[0][2].char, "文")
        self.assertEqual(b.cells[0][3].char, "")

    def test_put_text_truncate_at_right(self):
        b = FrameBuffer(3, 1)
        b.put_text(0, 0, "abcde")
        # 只能写入 abc
        self.assertEqual(b.cells[0][0].char, "a")
        self.assertEqual(b.cells[0][2].char, "c")

    def test_put_text_double_width_does_not_fit(self):
        # 双宽字符放不下时整字跳过
        b = FrameBuffer(3, 1)
        # 写 "ab中" → a(0) b(1) 中需要 2-3 格但 3 是边界，cx=2, cx+1=3>=w(3) → 跳过
        b.put_text(0, 0, "ab中")
        self.assertEqual(b.cells[0][0].char, "a")
        self.assertEqual(b.cells[0][1].char, "b")
        self.assertEqual(b.cells[0][2].char, " ")  # 中未写入

    def test_put_text_double_width_fits_exactly(self):
        b = FrameBuffer(4, 1)
        b.put_text(0, 0, "ab中")  # a(0) b(1) 中(2-3) 刚好
        self.assertEqual(b.cells[0][0].char, "a")
        self.assertEqual(b.cells[0][1].char, "b")
        self.assertEqual(b.cells[0][2].char, "中")
        self.assertEqual(b.cells[0][3].char, "")

    def test_set_char_multichar_takes_first(self):
        b = FrameBuffer(5, 1)
        b.set_char(0, 0, "xyz")
        self.assertEqual(b.cells[0][0].char, "x")

    def test_clear(self):
        b = FrameBuffer(3, 2)
        b.put_text(0, 0, "abc")
        b.clear()
        self.assertEqual(b.cells[0][0].char, " ")
        self.assertEqual(b.cells[1][0].char, " ")

    def test_fill_rect(self):
        b = FrameBuffer(5, 5)
        b.fill_rect(1, 1, 2, 2, "X")
        self.assertEqual(b.cells[1][1].char, "X")
        self.assertEqual(b.cells[1][2].char, "X")
        self.assertEqual(b.cells[2][1].char, "X")
        self.assertEqual(b.cells[2][2].char, "X")
        self.assertEqual(b.cells[0][0].char, " ")  # 未填充

    def test_out_of_bounds_noop(self):
        b = FrameBuffer(3, 3)
        b.set_char(-1, 0, "a")
        b.set_char(0, 5, "b")
        b.put_text(-1, 0, "abc")
        # 不应崩溃，不应越界写入
        self.assertEqual(b.cells[0][0].char, " ")


class TestCellEquality(unittest.TestCase):
    def test_cell_eq(self):
        c1 = Cell("a", theme.FG, theme.BG)
        c2 = Cell("a", theme.FG, theme.BG)
        self.assertEqual(c1, c2)

    def test_cell_neq_color(self):
        c1 = Cell("a", theme.FG, theme.BG)
        c2 = Cell("a", theme.ACCENT, theme.BG)
        self.assertNotEqual(c1, c2)

    def test_cell_neq_char(self):
        c1 = Cell("a")
        c2 = Cell("b")
        self.assertNotEqual(c1, c2)


if __name__ == "__main__":
    unittest.main()
