"""B1 招募普通兵单元测试。

覆盖:
- 无招募建筑 → 招募失败。
- 有招募建筑(全局存在性) + 资源够 → 成功,单位入待命池 cooldown=0。
- 资源不够 → 失败。
- 全局存在性:在据点 A 建建筑,可在据点 B 招募(不必在建造据点)。
"""
import unittest

from pydemo.cli.scenario import build_scenario
from pydemo.game.map_system import Building


class TestRecruitUnit(unittest.TestCase):
    def setUp(self):
        self.game = build_scenario()
        self.player = self.game.factions["player"]
        # 给足资源 + 学前置科技,以便能建兵营
        self.player.resources.amounts["tech"] = 50
        self.player.resources.amounts["wood"] = 200
        self.player.resources.amounts["gold"] = 200
        self.game.action_learn_tech("player", "martial_tradition")

    def _build_barracks(self, sid="p_cap"):
        # 重新补资源(学习消耗了资源)再建兵营
        self.player.resources.amounts["wood"] = 200
        self.player.resources.amounts["gold"] = 200
        msg = self.game.action_build("player", sid, "barracks")
        self.assertIn("建造", msg)

    def test_recruit_no_building_fails(self):
        msg = self.game.action_recruit_unit("player", "infantry")
        self.assertIn("失败", msg)
        # 场景开局已塞 2 预备兵到待命池,故不强制断空池;只断未新增。
        before = len(self.player.standby)
        self.game.action_recruit_unit("player", "infantry")
        self.assertEqual(len(self.player.standby), before)

    def test_recruit_with_building_success(self):
        self._build_barracks()
        # 给足招兵资源(infantry cost gold:10)
        self.player.resources.amounts["gold"] = 200
        before = len(self.player.standby)
        msg = self.game.action_recruit_unit("player", "infantry")
        self.assertIn("招募了", msg)
        self.assertEqual(len(self.player.standby), before + 1)
        # 最新进池的单位 cooldown=0(待命·可用)
        last_uid = list(self.player.standby.keys())[-1]
        self.assertEqual(self.player.standby[last_uid], 0)

    def test_recruit_insufficient_resource(self):
        self._build_barracks()
        # 把 gold 扣到不够招步兵(cost gold:10)
        self.player.resources.amounts["gold"] = 5
        msg = self.game.action_recruit_unit("player", "infantry")
        self.assertIn("失败", msg)

    def test_recruit_global_presence(self):
        # 在 p_cap 建兵营,占住 p_cap 槽位;招募动作不依赖据点位置(全局)。
        # p_cap size=4,初始已占 2 槽(farm+iron_mine),建兵营占第 3 槽。
        self._build_barracks("p_cap")
        self.player.resources.amounts["gold"] = 200
        msg = self.game.action_recruit_unit("player", "infantry")
        self.assertIn("招募了", msg)

    def test_recruit_wrong_unit_for_building(self):
        # 建了兵营(招步兵),不能用来招骑兵(需马厩)。
        self._build_barracks()
        self.player.resources.amounts["gold"] = 200
        msg = self.game.action_recruit_unit("player", "cavalry")
        self.assertIn("失败", msg)


if __name__ == "__main__":
    unittest.main()
