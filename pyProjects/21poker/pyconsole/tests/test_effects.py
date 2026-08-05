"""效果系统单元测试（阶段 7）。

纯函数部分（is_shell_card / slot_can_place / slot_is_occupied / is_forced_activate）在此测；
执行器（剥削/损坏）涉及场景经济方法，在 scenes/game21 落地后由 test_render_smoke 间接覆盖。
"""
import unittest

from pyconsole.game.cards import Card, make_standard_card
from pyconsole.game.effects import (
    Effect, SlotEffect, SHELL, FORCED, EXPLOIT, BROKEN,
    is_shell_card, is_forced_activate, slot_can_place, slot_is_occupied,
    run_effect, EFFECT_REGISTRY,
)


class _FakeSlot:
    """测试用卡槽桩：含 cards 与 slot_effect。"""
    def __init__(self, cards=None, slot_effect=None):
        self.cards = cards or []
        self.slot_effect = slot_effect


def _shell_card():
    return Card(suit="★", tag="壳", points=(0,), on_play=Effect(kind=SHELL))


def _normal_card(rank=5):
    return make_standard_card(rank, "♠")


class TestShellCard(unittest.TestCase):
    def test_normal_card_not_shell(self):
        self.assertFalse(is_shell_card(_normal_card()))

    def test_shell_effect_makes_shell(self):
        self.assertTrue(is_shell_card(_shell_card()))

    def test_shell_via_on_end(self):
        c = Card(suit="★", tag="壳", points=(0,), on_end=Effect(kind=SHELL))
        self.assertTrue(is_shell_card(c))


class TestSlotCanPlace(unittest.TestCase):
    def test_empty_slot_accepts_any(self):
        self.assertTrue(slot_can_place(_FakeSlot(), _normal_card()))

    def test_slot_with_normal_top_rejects(self):
        slot = _FakeSlot(cards=[_normal_card(7)])
        self.assertFalse(slot_can_place(slot, _normal_card(5)))

    def test_slot_with_shell_top_accepts(self):
        slot = _FakeSlot(cards=[_shell_card()])
        self.assertTrue(slot_can_place(slot, _normal_card(5)))

    def test_shell_slot_effect_accepts_any_top(self):
        # 空壳效果槽：即使栈顶是非空壳牌，仍可放
        se = SlotEffect(kind=SHELL, cost=0)
        slot = _FakeSlot(cards=[_normal_card(7)], slot_effect=se)
        self.assertTrue(slot_can_place(slot, _normal_card(5)))

    def test_shell_slot_effect_empty_accepts(self):
        se = SlotEffect(kind=SHELL)
        self.assertTrue(slot_can_place(_FakeSlot(slot_effect=se), _normal_card()))


class TestSlotIsOccupied(unittest.TestCase):
    def test_empty_not_occupied(self):
        self.assertFalse(slot_is_occupied(_FakeSlot()))

    def test_normal_top_occupied(self):
        self.assertTrue(slot_is_occupied(_FakeSlot(cards=[_normal_card(7)])))

    def test_shell_top_not_occupied(self):
        # 栈顶是空壳牌 → 未占据（可继续叠）
        self.assertFalse(slot_is_occupied(_FakeSlot(cards=[_shell_card()])))

    def test_shell_then_normal_occupied(self):
        # 空壳牌上叠了非空壳牌 → 占据
        slot = _FakeSlot(cards=[_shell_card(), _normal_card(5)])
        self.assertTrue(slot_is_occupied(slot))


class TestForcedActivate(unittest.TestCase):
    def test_no_activate_not_forced(self):
        self.assertFalse(is_forced_activate(_normal_card()))

    def test_normal_activate_not_forced(self):
        c = Card(suit="★", tag="X", points=(1,), on_activate=Effect(kind="某效果"))
        self.assertFalse(is_forced_activate(c))

    def test_forced_activate(self):
        c = Card(suit="★", tag="X", points=(1,),
                 on_activate=Effect(kind="某效果", params={"forced": True}))
        self.assertTrue(is_forced_activate(c))


class TestRunEffect(unittest.TestCase):
    def test_unknown_kind_silently_skipped(self):
        # 未注册的 kind 不应抛
        run_effect("不存在", None, 0, -1, _normal_card(), Effect(kind="不存在"))

    def test_registered_executor_called(self):
        from pyconsole.game.effects import register
        seen = {}

        @register("测试效果_临时")
        def _exec(scene, actor_idx, slot_idx, card, effect):
            seen["called"] = (actor_idx, slot_idx, effect.level)

        c = Card(suit="★", tag="X", points=(1,), on_play=Effect(kind="测试效果_临时", level=3))
        run_effect("测试效果_临时", None, 1, 2, c, c.on_play)
        self.assertEqual(seen.get("called"), (1, 2, 3))
        # 清理
        del EFFECT_REGISTRY["测试效果_临时"]


if __name__ == "__main__":
    unittest.main()
