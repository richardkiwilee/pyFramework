"""测试键绑定加载与解析。"""
import json
import os
import tempfile
import unittest

from pyconsole.core import actions
from pyconsole.core.keys import DEFAULT_BINDINGS, load_bindings, KeyResolver


class TestDefaultBindings(unittest.TestCase):
    def test_defaults_present(self):
        self.assertEqual(DEFAULT_BINDINGS["space"], actions.SELECT)
        self.assertEqual(DEFAULT_BINDINGS["enter"], actions.CONFIRM)
        self.assertEqual(DEFAULT_BINDINGS["escape"], actions.BACK)
        self.assertEqual(DEFAULT_BINDINGS["h"], actions.OPEN_WIKI)
        self.assertEqual(DEFAULT_BINDINGS["up"], actions.UP)
        self.assertEqual(DEFAULT_BINDINGS["backspace"], actions.BACKSPACE)

    def test_tab_not_bound(self):
        self.assertNotIn("tab", DEFAULT_BINDINGS)


class TestLoadBindings(unittest.TestCase):
    def test_missing_file_returns_default(self):
        b = load_bindings("nonexistent_path_xyz.json")
        self.assertEqual(b["space"], actions.SELECT)

    def test_none_path_returns_default(self):
        b = load_bindings(None)
        self.assertEqual(b["enter"], actions.CONFIRM)

    def test_valid_override(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
            json.dump({"space": "confirm", "h": "select"}, f)
            path = f.name
        try:
            b = load_bindings(path)
            self.assertEqual(b["space"], actions.CONFIRM)  # 覆盖
            self.assertEqual(b["h"], actions.SELECT)        # 覆盖
            self.assertEqual(b["enter"], actions.CONFIRM)  # 未覆盖保持默认
        finally:
            os.unlink(path)

    def test_invalid_json_returns_default(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
            f.write("{ not valid json")
            path = f.name
        try:
            b = load_bindings(path)
            self.assertEqual(b["space"], actions.SELECT)  # 默认
        finally:
            os.unlink(path)

    def test_invalid_action_ignored(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
            json.dump({"space": "totally_invalid_action"}, f)
            path = f.name
        try:
            b = load_bindings(path)
            self.assertEqual(b["space"], actions.SELECT)  # 非法值被忽略，保持默认
        finally:
            os.unlink(path)


class TestKeyResolver(unittest.TestCase):
    def setUp(self):
        self.r = KeyResolver()

    def test_bound_key(self):
        ev = self.r.resolve("space", "")
        self.assertIsNotNone(ev)
        self.assertEqual(ev.action, actions.SELECT)

    def test_direction_keys(self):
        self.assertEqual(self.r.resolve("up", "").action, actions.UP)
        self.assertEqual(self.r.resolve("down", "").action, actions.DOWN)

    def test_char_key(self):
        ev = self.r.resolve("char", "x")
        self.assertIsNotNone(ev)
        self.assertEqual(ev.action, actions.CHAR)
        self.assertEqual(ev.char, "x")

    def test_h_is_open_wiki_not_char(self):
        # h 被绑定为 OPEN_WIKI，不应产生 CHAR
        ev = self.r.resolve("char", "h")
        self.assertIsNotNone(ev)
        self.assertEqual(ev.action, actions.OPEN_WIKI)
        self.assertEqual(ev.char, "")

    def test_unknown_key(self):
        self.assertIsNone(self.r.resolve("unknown_99", ""))

    def test_backspace(self):
        ev = self.r.resolve("backspace", "")
        self.assertEqual(ev.action, actions.BACKSPACE)


if __name__ == "__main__":
    unittest.main()
