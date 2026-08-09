"""B7 科技/文化门控单元测试。

覆盖:
- Faction.tech_learned/culture_learned 集合存在且默认空。
- action_learn_tech/culture:前置未满足→失败;前置满足+资源够→成功加入 set;
  资源不足→失败;重复学习→失败。
- action_build 门控:recruit/special 类建筑需 requires 已学;未学→「需先研究 X」;
  产出建筑(produce)免门控,始终可建(资源够即可)。
- AI 学习不抛错(ai_take_turn 返回 learn_tech/learn_culture 动作,可执行)。
"""
import unittest

from pydemo.cli.scenario import build_scenario
from pydemo.game.ai import ai_take_turn


class TestTechCultureGating(unittest.TestCase):
    def setUp(self):
        self.game = build_scenario()
        self.player = self.game.factions["player"]
        self.ai = self.game.factions["ai"]

    def test_faction_has_learned_sets(self):
        self.assertIsInstance(self.player.tech_learned, set)
        self.assertIsInstance(self.player.culture_learned, set)
        self.assertEqual(self.player.tech_learned, set())
        self.assertEqual(self.player.culture_learned, set())

    def test_learn_tech_no_prereq_success(self):
        # martial_tradition 无前置,cost {tech:4};玩家初始 tech=0 → 资源不足。
        # 先给资源再学。
        self.player.resources.amounts["tech"] = 10
        msg = self.game.action_learn_tech("player", "martial_tradition")
        self.assertIn("martial_tradition", self.player.tech_learned)
        self.assertIn("学习了", msg)

    def test_learn_tech_missing_prereq(self):
        # archery_discipline 需 martial_tradition;未学 → 失败。
        self.player.resources.amounts["tech"] = 50
        self.player.resources.amounts["wood"] = 50
        msg = self.game.action_learn_tech("player", "archery_discipline")
        self.assertIn("失败", msg)
        self.assertNotIn("archery_discipline", self.player.tech_learned)

    def test_learn_tech_after_prereq(self):
        self.player.resources.amounts["tech"] = 50
        self.player.resources.amounts["wood"] = 50
        self.game.action_learn_tech("player", "martial_tradition")
        msg = self.game.action_learn_tech("player", "archery_discipline")
        self.assertIn("学习了", msg)
        self.assertIn("archery_discipline", self.player.tech_learned)

    def test_learn_tech_insufficient_resource(self):
        # 玩家初始 tech=0 → 学不起 martial_tradition(cost tech:4)。
        msg = self.game.action_learn_tech("player", "martial_tradition")
        self.assertIn("失败", msg)
        self.assertNotIn("martial_tradition", self.player.tech_learned)

    def test_learn_tech_duplicate(self):
        self.player.resources.amounts["tech"] = 50
        self.game.action_learn_tech("player", "martial_tradition")
        msg = self.game.action_learn_tech("player", "martial_tradition")
        self.assertIn("已学习", msg)

    def test_learn_culture_no_prereq_success(self):
        self.player.resources.amounts["culture"] = 10
        self.player.resources.amounts["gold"] = 50
        msg = self.game.action_learn_culture("player", "cavalry_nobility")
        self.assertIn("cavalry_nobility", self.player.culture_learned)
        self.assertIn("学习了", msg)

    def test_build_recruit_requires_gate(self):
        # barracks 需 martial_tradition;未学 → 建造失败。
        # 给足资源确保失败原因是门控而非资源。
        self.player.resources.amounts["wood"] = 200
        self.player.resources.amounts["gold"] = 200
        msg = self.game.action_build("player", "p_cap", "barracks")
        self.assertIn("失败", msg)
        self.assertIn("研究", msg)
        # 学了之后可建
        self.player.resources.amounts["tech"] = 50
        self.game.action_learn_tech("player", "martial_tradition")
        # 重新补资源(学习消耗了资源)再建
        self.player.resources.amounts["wood"] = 200
        self.player.resources.amounts["gold"] = 200
        msg2 = self.game.action_build("player", "p_cap", "barracks")
        self.assertIn("建造", msg2)

    def test_build_produce_exempt_from_gate(self):
        # market 产出建筑无 requires,资源够即可建(免门控)。
        # p_cap 初始已占 2 槽(farm+iron_mine),size=4,剩 2 空槽。
        self.player.resources.amounts["wood"] = 50
        msg = self.game.action_build("player", "p_cap", "market")
        self.assertIn("建造", msg)

    def test_ai_learn_does_not_raise(self):
        # 给 AI 充足资源使其能学习;跑一回合 AI 动作不应抛错。
        self.ai.resources.amounts["tech"] = 50
        self.ai.resources.amounts["culture"] = 50
        self.ai.resources.amounts["gold"] = 200
        self.ai.resources.amounts["wood"] = 200
        acts = ai_take_turn(self.ai, self.game)
        kinds = [k for k, _ in acts]
        # AI 应产生了学习动作(资源充足)。
        self.assertTrue("learn_tech" in kinds or "learn_culture" in kinds)
        # 执行所有 AI 动作不应抛错。
        for kind, payload in acts:
            if kind == "learn_tech":
                self.game.action_learn_tech("ai", payload["tech"])
            elif kind == "learn_culture":
                self.game.action_learn_culture("ai", payload["culture"])
            elif kind == "build":
                self.game.action_build("ai", payload["stronghold"], payload["building"])
            elif kind == "recruit_hero":
                self.game.action_recruit_hero("ai", payload["stronghold"], payload["hero"])
            elif kind == "move_attack":
                self.game.action_move_attack("ai", payload["army"], payload["to"])
            elif kind == "deploy":
                self.game.action_deploy("ai", payload["army"], payload["unit"], payload.get("slot"))
            elif kind == "new_army":
                army = self.game.create_army("ai", payload["stronghold"], payload.get("name", "AI"))
                hero = self.game.unit_index.get(payload["hero"])
                if hero:
                    self.game.set_captain(army, hero)


if __name__ == "__main__":
    unittest.main()
