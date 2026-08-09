"""B5 存档读档单元测试。

覆盖:
- snapshot/restore round-trip:新建 game→snapshot→restore→逐字段比对。
- set↔list 还原:tags/tech_learned/culture_learned 经序列化后还原为 set。
- 改变状态后存档:学习科技、推进天数、扣资源后 restore 反映变化。
- restore 后可继续跑(start_turn 不抛错)。
- 控制器 save/load:写 save001.dat → 读回 → 状态一致;无存档返回提示。
- 单位 cur_hp<=0(阵亡)状态可被保留(不被 __post_init__ 重置)。
"""
import json
import os
import unittest

from pydemo.cli.scenario import build_scenario
from pydemo.game.game import Game
from pydemo.game.time_system import Calendar
from pydemo.tui import controller as ctrl_mod


class TestSaveLoad(unittest.TestCase):
    def setUp(self):
        self.game = build_scenario()

    def test_roundtrip_basic_fields(self):
        d = self.game.snapshot()
        g2 = Game.restore(d)
        self.assertEqual(g2.calendar.day, self.game.calendar.day)
        self.assertEqual(g2.player_id, self.game.player_id)
        self.assertEqual(g2.winner, self.game.winner)
        self.assertEqual(set(g2.factions.keys()), set(self.game.factions.keys()))
        self.assertEqual(set(g2.armies.keys()), set(self.game.armies.keys()))
        self.assertEqual(len(g2.unit_index), len(self.game.unit_index))
        self.assertEqual(set(g2.map.strongholds.keys()),
                         set(self.game.map.strongholds.keys()))
        self.assertEqual(set(g2.map.minors.keys()),
                         set(self.game.map.minors.keys()))
        self.assertEqual(g2.map.adj, self.game.map.adj)

    def test_roundtrip_faction_fields(self):
        d = self.game.snapshot()
        g2 = Game.restore(d)
        p1 = self.game.factions["player"]
        p2 = g2.factions["player"]
        self.assertEqual(p2.id, p1.id)
        self.assertEqual(p2.is_ai, p1.is_ai)
        self.assertEqual(p2.resources.amounts, p1.resources.amounts)
        self.assertEqual(p2.belief.values, p1.belief.values)
        self.assertEqual(p2.capital_id, p1.capital_id)
        self.assertEqual(p2.army_ids, p1.army_ids)
        self.assertEqual(p2.hero_ids, p1.hero_ids)
        self.assertEqual(p2.stronghold_ids, p1.stronghold_ids)
        self.assertEqual(p2.standby, p1.standby)
        self.assertEqual(p2.inventory, p1.inventory)
        self.assertEqual(p2.alive, p1.alive)

    def test_set_list_roundtrip(self):
        # tags 是 set;tech_learned/culture_learned 是 set
        self.game.action_learn_tech("player", "martial_tradition")
        self.game.action_learn_culture("player", "folk_epic")
        d = self.game.snapshot()
        # 确认序列化成 list
        self.assertIsInstance(d["factions"]["player"]["tech_learned"], list)
        self.assertIsInstance(d["factions"]["player"]["culture_learned"], list)
        for uid, ud in d["units"].items():
            self.assertIsInstance(ud["tags"], list)
        g2 = Game.restore(d)
        # 还原为 set
        self.assertIsInstance(g2.factions["player"].tech_learned, set)
        self.assertIsInstance(g2.factions["player"].culture_learned, set)
        self.assertEqual(g2.factions["player"].tech_learned,
                         self.game.factions["player"].tech_learned)
        self.assertEqual(g2.factions["player"].culture_learned,
                         self.game.factions["player"].culture_learned)
        # 单位 tags 还原为 set
        for uid in g2.unit_index:
            self.assertIsInstance(g2.unit_index[uid].tags, set)

    def test_changed_state_persisted(self):
        # 改状态:学科技、推进天数、改资源
        self.game.factions["player"].resources.amounts["tech"] = 50
        self.game.action_learn_tech("player", "martial_tradition")
        self.game.calendar = Calendar(day=7)
        self.game.factions["player"].resources.amounts["gold"] = 123
        d = self.game.snapshot()
        g2 = Game.restore(d)
        self.assertEqual(g2.calendar.day, 7)
        self.assertIn("martial_tradition", g2.factions["player"].tech_learned)
        self.assertEqual(g2.factions["player"].resources.amounts["gold"], 123)

    def test_restore_then_continue_play(self):
        # restore 后能继续 start_turn(经济结算/建筑事件 dispatch 不抛错)
        d = self.game.snapshot()
        g2 = Game.restore(d)
        g2.start_turn(g2.factions["player"])
        g2.end_turn_advance()
        self.assertGreater(g2.calendar.day, self.game.calendar.day)

    def test_dead_unit_cur_hp_preserved(self):
        # 制造一个阵亡单位(cur_hp<=0),restore 后应保留(不被 __post_init__ 重置)
        u = list(self.game.unit_index.values())[0]
        u.cur_hp = 0
        u.alive = False
        d = self.game.snapshot()
        g2 = Game.restore(d)
        u2 = g2.unit_index[u.id]
        self.assertEqual(u2.cur_hp, 0)
        self.assertFalse(u2.alive)

    def test_controller_save_load_roundtrip(self):
        # 用控制器 save/load 写文件再读回
        ctrl_mod.ctrl.game = self.game
        save_path = ctrl_mod.ctrl._save_path()
        if os.path.isfile(save_path):
            os.remove(save_path)
        msg = ctrl_mod.ctrl.save()
        self.assertTrue(msg.startswith("已保存"))
        self.assertTrue(os.path.isfile(save_path))
        # 读回
        msg2 = ctrl_mod.ctrl.load()
        self.assertTrue(msg2.startswith("已读取"))
        self.assertEqual(ctrl_mod.ctrl.g.calendar.day, self.game.calendar.day)
        # 清理
        os.remove(save_path)

    def test_controller_load_no_save(self):
        save_path = ctrl_mod.ctrl._save_path()
        if os.path.isfile(save_path):
            os.remove(save_path)
        msg = ctrl_mod.ctrl.load()
        self.assertIn("无存档", msg)

    def test_save_file_is_save001_dat(self):
        # 始终操作 save001.dat
        ctrl_mod.ctrl.game = self.game
        save_path = ctrl_mod.ctrl._save_path()
        if os.path.isfile(save_path):
            os.remove(save_path)
        ctrl_mod.ctrl.save()
        self.assertTrue(save_path.endswith("save001.dat"))
        # 文件是合法 JSON
        with open(save_path, encoding="utf-8") as f:
            data = json.load(f)
        self.assertIn("day", data)
        os.remove(save_path)

    def test_landmark_persisted(self):
        # landmark Building 实例独立槽,restore 后应保留
        d = self.game.snapshot()
        g2 = Game.restore(d)
        p1 = self.game.map.strongholds["p_cap"]
        p2 = g2.map.strongholds["p_cap"]
        self.assertIsNotNone(p2.landmark)
        self.assertEqual(p2.landmark.name, p1.landmark.name)
        self.assertEqual(p2.landmark.tier, p1.landmark.tier)
        # landmark 不在 buildings 列表
        self.assertNotIn(p2.landmark, p2.buildings)

    def test_recruitment_pool_persisted(self):
        d = self.game.snapshot()
        g2 = Game.restore(d)
        p1 = self.game.factions["player"].recruitment_pools
        p2 = g2.factions["player"].recruitment_pools
        self.assertEqual(set(p2.keys()), set(p1.keys()))
        for sid in p1:
            self.assertEqual(p2[sid].offerings, p1[sid].offerings)
            self.assertEqual(p2[sid].refresh_day, p1[sid].refresh_day)


if __name__ == "__main__":
    unittest.main()
