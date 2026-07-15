"""测试 CJK 双宽计算。"""
import unittest

from pyconsole.io.width import char_width, text_width


class TestWidth(unittest.TestCase):
    def test_ascii_single(self):
        self.assertEqual(char_width("a"), 1)
        self.assertEqual(char_width("A"), 1)
        self.assertEqual(char_width("1"), 1)
        self.assertEqual(char_width(" "), 1)
        self.assertEqual(char_width("!"), 1)

    def test_cjk_double(self):
        self.assertEqual(char_width("中"), 2)
        self.assertEqual(char_width("文"), 2)
        self.assertEqual(char_width("剑"), 2)
        self.assertEqual(char_width("壹"), 2)

    def test_kana_double(self):
        self.assertEqual(char_width("あ"), 2)
        self.assertEqual(char_width("カ"), 2)

    def test_control_zero(self):
        self.assertEqual(char_width("\x00"), 0)
        self.assertEqual(char_width("\x1b"), 0)  # ESC
        self.assertEqual(char_width("\x08"), 0)  # backspace
        self.assertEqual(char_width("\r"), 0)
        self.assertEqual(char_width("\n"), 0)
        self.assertEqual(char_width("\t"), 0)

    def test_empty(self):
        self.assertEqual(char_width(""), 0)

    def test_multichar_takes_first(self):
        self.assertEqual(char_width("ab"), 1)
        self.assertEqual(char_width("中文"), 2)

    def test_text_width_mixed(self):
        self.assertEqual(text_width("abc"), 3)
        self.assertEqual(text_width("中文"), 4)
        self.assertEqual(text_width("a中b文"), 6)  # 1+2+1+2
        self.assertEqual(text_width(""), 0)
        self.assertEqual(text_width("铁剑 [武器]"), 11)  # 2+2+1+1+2+1+1 = 10? 重算

    def test_text_width_label(self):
        # "铁剑 [武器]" = 铁(2) 剑(2) (1) [(1) 武(2) 器(2) ](1) = 11
        self.assertEqual(text_width("铁剑 [武器]"), 11)


if __name__ == "__main__":
    unittest.main()
