"""测试百科模糊搜索。"""
import unittest

from pyconsole.data.wiki_data import WikiEntry, search, find_match_ranges


def make_entries():
    return [
        WikiEntry("1", "铁剑", "武器", "铁制长剑", "详细描述铁剑", {"伤害": "8"}),
        WikiEntry("2", "寒霜之刃", "武器", "冰霜魔法剑", "详细描述寒霜", {}),
        WikiEntry("3", "生命药水", "消耗品", "恢复生命", "详细描述药水", {}),
        WikiEntry("4", "哥布林", "怪物", "绿皮生物", "详细描述哥布林", {}),
        WikiEntry("5", "Fireball", "技能", "fire ball spell", "detail", {}),
    ]


class TestSearch(unittest.TestCase):
    def test_empty_query_no_results(self):
        self.assertEqual(search(make_entries(), ""), [])
        self.assertEqual(search(make_entries(), "   "), [])

    def test_substring_match_name(self):
        hits = search(make_entries(), "铁剑")
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0].entry.name, "铁剑")

    def test_case_insensitive(self):
        hits = search(make_entries(), "fireball")
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0].entry.name, "Fireball")
        hits2 = search(make_entries(), "FIREBALL")
        self.assertEqual(len(hits2), 1)

    def test_match_summary(self):
        hits = search(make_entries(), "恢复生命")
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0].entry.name, "生命药水")

    def test_match_category(self):
        hits = search(make_entries(), "怪物")
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0].entry.name, "哥布林")

    def test_multiple_match_sorted_by_name(self):
        hits = search(make_entries(), "武器")
        self.assertEqual(len(hits), 2)
        # 按 name 升序：寒霜之刃 < 铁剑
        self.assertEqual([h.entry.name for h in hits], ["寒霜之刃", "铁剑"])

    def test_no_match(self):
        hits = search(make_entries(), "不存在的关键字xyz")
        self.assertEqual(hits, [])

    def test_matched_fields(self):
        hits = search(make_entries(), "铁")
        self.assertEqual(len(hits), 1)
        self.assertIn("name", hits[0].matched_fields)


class TestMatchRanges(unittest.TestCase):
    def test_no_query(self):
        self.assertEqual(find_match_ranges("abc", ""), [])

    def test_single_match(self):
        self.assertEqual(find_match_ranges("hello world", "world"), [(6, 11)])

    def test_multiple_matches(self):
        self.assertEqual(find_match_ranges("ab ab ab", "ab"), [(0, 2), (3, 5), (6, 8)])

    def test_case_insensitive(self):
        self.assertEqual(find_match_ranges("Hello HELLO", "hello"), [(0, 5), (6, 11)])

    def test_no_match(self):
        self.assertEqual(find_match_ranges("abc", "xyz"), [])

    def test_cjk(self):
        # "铁剑" in "铁剑与寒霜之刃" → 匹配中文子串
        self.assertEqual(find_match_ranges("铁剑与寒霜之刃", "铁剑"), [(0, 2)])


if __name__ == "__main__":
    unittest.main()
