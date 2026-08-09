"""B10 锻造屋建筑回合事件 + 装备稀有度加权抽取测试。

覆盖:
- 锻造屋建筑定义存在性 + on_turn=forge_drop + requires=forge_culture。
- _weighted_random_artifact 按稀有度加权分布(大样本统计)。
- forge_drop handler 命中(强制 rng<0.05)→ 产出装备入库存。
- forge_drop 未命中(rng>=0.05)→ 无产出。
- 无装备定义时 _weighted_random_artifact 返回 None。
- dispatch 路径:建有锻造屋的据点经 start_turn 触发(大量回合后应偶发产出)。
"""
import random
import unittest
from collections import Counter

from pydemo.cli.scenario import build_scenario
from pydemo.game import game as game_mod
from pydemo.game.game import _weighted_random_artifact, FORGE_DROP_CHANCE


class _FakeRandomModule:
    """替身 random 模块:Random() 返回受控 rng,用于 forge_drop handler 测试。"""

    def __init__(self, rand_value, choice_index=0):
        self._rand_value = rand_value
        self._choice_index = choice_index

    def Random(self):
        outer = self

        class _R:
            def random(self):
                return outer._rand_value

            def choice(self, seq):
                return seq[outer._choice_index]

        return _R()


class TestForgeDrop(unittest.TestCase):
    def setUp(self):
        self.game = build_scenario()
        self.player = self.game.factions["player"]
        # 给足资源 + 学前置文化,以便能建锻造屋
        self.player.resources.amounts["culture"] = 50
        self.player.resources.amounts["stone"] = 200
        self.player.resources.amounts["iron"] = 200
        self.player.resources.amounts["wood"] = 200
        self.game.action_learn_culture("player", "forge_culture")

    def test_forge_building_def(self):
        bdef = self.game.building_defs.get("forge")
        self.assertIsNotNone(bdef, "buildings.json 应含 forge 锻造屋定义")
        self.assertEqual(bdef.get("kind"), "special")
        self.assertEqual(bdef.get("on_turn"), "forge_drop")
        self.assertIn("forge_culture", bdef.get("requires", []))

    def test_forge_drop_registered(self):
        # 注册表应含 forge_drop handler
        self.assertIn("forge_drop", game_mod.Game.BUILDING_TURN_EVENTS)

    def test_weighted_random_artifact_distribution(self):
        # 大样本统计 _weighted_random_artifact 的稀有度分布
        counts: Counter = Counter()
        artifact_defs = self.game.artifact_defs
        n = 4000
        for i in range(n):
            rng = random.Random(i)
            def_id = _weighted_random_artifact(rng, artifact_defs)
            self.assertIsNotNone(def_id)
            a = artifact_defs[def_id]
            counts[a.rarity] += 1
        # 期望比例:common 60% uncommon 30% rare 10%,容差 ±5%
        self.assertAlmostEqual(counts["common"] / n, 0.60, delta=0.05)
        self.assertAlmostEqual(counts["uncommon"] / n, 0.30, delta=0.05)
        self.assertAlmostEqual(counts["rare"] / n, 0.10, delta=0.05)

    def test_weighted_random_artifact_no_defs(self):
        rng = random.Random(0)
        self.assertIsNone(_weighted_random_artifact(rng, {}))

    def test_weighted_random_artifact_only_rare(self):
        # 只有 rare 装备定义时,按权重选 rare 桶,命中后正常返回 rare(不回退)
        from pydemo.game.unit import Artifact
        defs = {"only_rare": Artifact(id="only_rare", name="唯一", rarity="rare")}
        rng = random.Random(0)
        def_id = _weighted_random_artifact(rng, defs)
        self.assertEqual(def_id, "only_rare")

    def test_forge_drop_hit_produces_stock(self):
        # 强制命中:patch game 模块的 random 使 random()<0.05
        from pydemo.game.map_system import Building
        import pydemo.game.game as gm
        sh = self.game.map.strongholds["p_cap"]
        forge = Building(id="b_forge", type_id="forge", name="锻造屋")
        before = dict(self.player.inventory)
        orig = gm.random
        gm.random = _FakeRandomModule(rand_value=0.0)
        try:
            gm._forge_drop_handler(self.game, self.player, sh, forge)
        finally:
            gm.random = orig
        after = self.player.inventory
        diff = {k: after[k] - before.get(k, 0) for k in after
                if after[k] - before.get(k, 0) != 0}
        self.assertTrue(any(v > 0 for v in diff.values()),
                        "命中锻造屋应产出装备使库存+1")

    def test_forge_drop_miss_no_produce(self):
        from pydemo.game.map_system import Building
        import pydemo.game.game as gm
        sh = self.game.map.strongholds["p_cap"]
        forge = Building(id="b_forge", type_id="forge", name="锻造屋")
        before = dict(self.player.inventory)
        orig = gm.random
        gm.random = _FakeRandomModule(rand_value=0.99)  # >= 0.05 → 不命中
        try:
            gm._forge_drop_handler(self.game, self.player, sh, forge)
        finally:
            gm.random = orig
        self.assertEqual(self.player.inventory, before)

    def test_dispatch_via_start_turn(self):
        # 建锻造屋后跑多个回合,forge_drop dispatch 应不抛错;
        # 用固定 seed 的 game,大量回合后库存应有概率增长(不强制断言产量,避免 flaky)。
        from pydemo.game.map_system import Building
        # 重新学文化(上面已学),建锻造屋
        self.player.resources.amounts["stone"] = 200
        self.player.resources.amounts["iron"] = 200
        msg = self.game.action_build("player", "p_cap", "forge")
        self.assertIn("建造", msg, f"建锻造屋应成功,实际:{msg}")
        sh = self.game.map.strongholds["p_cap"]
        self.assertTrue(any(b.type_id == "forge" for b in sh.buildings))
        before_total = sum(self.player.inventory.values())
        # 跑 60 个玩家回合(每回合 5% 命中,期望约 3 件)
        for _ in range(60):
            self.game.start_turn(self.player)
            self.game.end_turn_advance()
        # 不强制断言产量(flaky),仅断言 dispatch 不抛错且库存非负
        after_total = sum(self.player.inventory.values())
        self.assertGreaterEqual(after_total, before_total)


if __name__ == "__main__":
    unittest.main()
