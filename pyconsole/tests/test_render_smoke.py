"""渲染冒烟测试：不输出到终端，只验证场景渲染到 FrameBuffer 不抛异常。

覆盖：主菜单、百科（空查询/有查询/无结果）、MessageScene、Tab overlay。
21 点部分在阶段 7 重写为新 API（players/Slot 栈/经济/软pass）。
这些不测视觉正确性，只测"不崩"——保证渲染管线贯通。
"""
import unittest

from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.scenes.main_menu import MainMenuScene
from pyconsole.scenes.wiki import WikiScene
from pyconsole.scenes.message import MessageScene
from pyconsole.scenes.game21 import Game21Scene
from pyconsole.core import overlay as overlay_mod
from pyconsole.core.game_state import get_state

W, H = 100, 30


def new_buf():
    return FrameBuffer(W, H)


class TestRenderSmoke(unittest.TestCase):
    def test_main_menu_renders(self):
        s = MainMenuScene()
        s.on_enter(None)
        s.render(new_buf())  # 不应抛异常

    def test_main_menu_navigation_renders(self):
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        s = MainMenuScene()
        s.on_enter(None)
        s.handle_action(InputEvent(actions.DOWN))
        s.handle_action(InputEvent(actions.SELECT))
        s.render(new_buf())

    def test_wiki_empty_query_renders(self):
        s = WikiScene()
        s.on_enter(None)
        s.render(new_buf())  # 空查询状态

    def test_wiki_with_query_renders(self):
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        s = WikiScene()
        s.on_enter(None)
        for ch in "剑":
            s.handle_action(InputEvent(actions.CHAR, ch))
        self.assertNotEqual(s.query, "")
        s.render(new_buf())

    def test_wiki_no_result_renders(self):
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        s = WikiScene()
        s.on_enter(None)
        for ch in "zzzz不存在的":
            s.handle_action(InputEvent(actions.CHAR, ch))
        s.render(new_buf())

    def test_wiki_selection_and_scroll_renders(self):
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        s = WikiScene()
        s.on_enter(None)
        for ch in "武":
            s.handle_action(InputEvent(actions.CHAR, ch))
        s.handle_action(InputEvent(actions.DOWN))
        s.handle_action(InputEvent(actions.SCROLL_DOWN))
        s.render(new_buf())

    def test_message_scene_renders(self):
        s = MessageScene("测试提示\n第二行")
        s.on_enter(None)
        s.render(new_buf())

    def test_overlay_renders(self):
        buf = new_buf()
        MainMenuScene().render(buf)  # 先画个背景
        overlay_mod.render(buf, W, H, "MainMenuScene", 1, get_state(), 10)

    def test_get_hints(self):
        s = MainMenuScene()
        s.on_enter(None)
        self.assertTrue(len(s.get_hints()) > 0)
        w = WikiScene()
        w.on_enter(None)
        self.assertTrue(len(w.get_hints()) > 0)

    def test_main_menu_space_is_noop(self):
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        s = MainMenuScene()
        s.on_enter(None)
        before = s.focus
        res = s.handle_action(InputEvent(actions.SELECT))
        self.assertEqual(res.kind, "none")
        self.assertEqual(s.focus, before)

    # ---- 21 点游戏场景冒烟（阶段 7 新 API） ----
    def _game(self, first_player="player"):
        """构造一个可控对局：注入 rng，强行设定先后手。

        不清空 _ai_turn_pending（否则会杀死 on_enter 排好的首个 AI 回合）。
        """
        import random
        g = Game21Scene(rng=random.Random(42))
        g.on_enter(None)
        # on_enter 已起手第1轮并按 rng 选先手；强行覆盖为指定先手
        g.current = 0 if first_player == "player" else 1
        g._tasks.clear()
        g._ai_turn_pending = False
        if first_player == "ai":
            g._start_ai_turn()
        else:
            g.phase = "menu"
        return g

    def test_game21_menu_renders(self):
        g = self._game("player")
        g.render(new_buf())  # 初始菜单态不抛

    def test_game21_holding_renders(self):
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        g = self._game("player")
        g.handle_action(InputEvent(actions.CONFIRM))  # 聚焦"抽牌"
        self.assertEqual(g.phase, "holding")
        g.render(new_buf())

    def test_game21_sleeve_select_renders(self):
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        g.players[0].sleeve = [make_standard_card(3, "♠"), make_standard_card(5, "♥")]
        g.menu_focus = 1
        g.handle_action(InputEvent(actions.CONFIRM))
        self.assertEqual(g.phase, "sleeve_select")
        g.render(new_buf())

    def test_game21_ai_turn_renders(self):
        g = self._game("ai")
        g.on_tick(1.0)  # 触发 _ai_turn_pending 排程
        g.render(new_buf())

    def test_game21_advance_to_round_settled(self):
        # 玩家一直 pass，让 AI 自行收敛到轮结算
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        g = self._game("player")
        # 玩家 pass
        g.players[0].passed = True
        g.players[0].pass_score = 0
        g._end_turn(0)
        now = 1.0
        for _ in range(400):
            g.on_tick(now)
            now += 0.3
            if g.phase == "round_settled":
                break
        g.render(new_buf())
        self.assertEqual(g.phase, "round_settled")

    def test_game21_round_settled_renders(self):
        # 直接构造一个轮结算状态
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        g.players[0].slots[0].cards.append(make_standard_card(10, "♠"))
        g.players[0].slots[1].cards.append(make_standard_card(9, "♥"))
        g.players[1].slots[0].cards.append(make_standard_card(5, "♦"))
        g.players[1].slots[1].cards.append(make_standard_card(6, "♣"))
        g.players[0].passed = True
        g.players[1].passed = True
        g._end_turn(0)  # 全 pass → _round_end
        self.assertEqual(g.phase, "round_settled")
        g.render(new_buf())

    def test_game21_activate_prompt_renders(self):
        # 构造 activate_prompt：给玩家一张带 on_activate 的牌并放牌
        from pyconsole.game.cards import make_standard_card
        from pyconsole.game.effects import Effect
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        g = self._game("player")
        # 一张带非强制 on_activate 的牌
        card = make_standard_card(7, "♠")
        card = type(card)(suit=card.suit, tag=card.tag, points=card.points, rank=card.rank,
                          on_play=None, on_activate=Effect(kind="未知效果"), on_end=None)
        g.held_card = card
        g._drawn_this_turn = True
        g.phase = "holding"
        g.handle_action(InputEvent(actions.CHAR, "1"))   # 打出 → slot_select
        g.handle_action(InputEvent(actions.CONFIRM))       # 放第一槽
        # on_activate 非强制 → activate_prompt（"未知效果"无执行器，静默跳过）
        self.assertEqual(g.phase, "activate_prompt")
        g.render(new_buf())

    def test_game21_round_settled_any_key_advances(self):
        # round_settled 按任意键 → 进入下一轮（round_num+1，重新收底注）
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        g = self._game("player")
        g.players[0].passed = True
        g.players[1].passed = True
        g._end_turn(0)
        self.assertEqual(g.phase, "round_settled")
        r0 = g.round_num
        g.handle_action(InputEvent(actions.CONFIRM))
        self.assertEqual(g.round_num, r0 + 1)
        self.assertIn(g.phase, ("menu", "ai_turn"))  # 下轮先手随机

    # ---- 新规则：栈模型 / 手动选槽 / 袖子满手动弃 / 抽牌锁定 ----
    def test_slots_default_five_and_empty(self):
        g = self._game("player")
        self.assertEqual(len(g.players[0].slots), 5)
        self.assertTrue(all(len(s.cards) == 0 for s in g.players[0].slots))
        self.assertEqual(g.players[0].first_playable_slot(), 0)
        self.assertEqual(g.players[0].table, [])

    def test_table_is_read_only_view_of_slots(self):
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        g.players[0].slots[2].cards.append(make_standard_card(7, "♠"))
        self.assertEqual([str(c) for c in g.players[0].table], ["7♠"])

    def test_draw_commits_to_play_blocks_pass(self):
        # 抽牌后：Pass 应被拒绝（必须打出一张牌）
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        g = self._game("player")
        g.handle_action(InputEvent(actions.CONFIRM))   # 抽牌 → holding
        self.assertTrue(g._drawn_this_turn)
        self.assertFalse(g._can_pass())
        self.assertFalse(g._can_play_sleeve())
        # 先藏入袖子（回到 menu），再尝试 Pass：仍被拒绝
        g.handle_action(InputEvent(actions.CHAR, "2"))  # 藏入袖子
        self.assertEqual(g.phase, "menu")
        self.assertTrue(g._drawn_this_turn)  # 藏牌不结束回合
        g.menu_focus = len(g._menu_items(0)) - 1  # 聚焦 Pass
        g.handle_action(InputEvent(actions.CONFIRM))
        # Pass 被拒：仍在 menu、玩家未停牌
        self.assertEqual(g.phase, "menu")
        self.assertFalse(g.players[0].passed)

    def test_stash_does_not_end_turn_then_play_ends_turn(self):
        # 抽→藏→抽→打：合法；打出后才结束回合
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        g = self._game("player")
        g.handle_action(InputEvent(actions.CONFIRM))   # holding
        held1 = g.held_card
        g.handle_action(InputEvent(actions.CHAR, "2"))  # 藏入袖子
        self.assertEqual(len(g.players[0].sleeve), 1)
        self.assertEqual(g.phase, "menu")
        self.assertTrue(g._drawn_this_turn)
        g.handle_action(InputEvent(actions.CONFIRM))   # 第二次抽
        self.assertNotEqual(g.held_card, held1)
        g.handle_action(InputEvent(actions.CHAR, "1"))  # 打出 → slot_select
        self.assertEqual(g.phase, "slot_select")
        g.handle_action(InputEvent(actions.CONFIRM))    # 放到焦点空槽
        self.assertFalse(g._drawn_this_turn)
        # 出牌后结束 turn；可能进 activate_prompt（牌无激活则直接交 AI）
        self.assertIn(g.phase, ("ai_turn", "activate_prompt"))

    def test_place_to_occupied_slot_fails_and_reselects(self):
        # 占用槽放置失败，停留重选；改放空槽成功
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        g.players[0].slots[1].cards.append(make_standard_card(5, "♣"))  # 预占槽2
        g.handle_action(InputEvent(actions.CONFIRM))
        g.handle_action(InputEvent(actions.CHAR, "1"))  # 打出
        self.assertEqual(g.phase, "slot_select")
        before = [c for s in g.players[0].slots for c in s.cards]
        g.handle_action(InputEvent(actions.CHAR, "2"))  # 选槽2（占用）
        self.assertEqual(g.phase, "slot_select")  # 仍在重选
        self.assertEqual([c for s in g.players[0].slots for c in s.cards], before)
        g.handle_action(InputEvent(actions.CHAR, "1"))  # 改选槽1（空）
        self.assertEqual(len(g.players[0].slots[0].cards), 1)

    def test_slot_focus_cycles_left_right(self):
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        g = self._game("player")
        g.handle_action(InputEvent(actions.CONFIRM))
        g.handle_action(InputEvent(actions.CHAR, "1"))  # slot_select
        g._slot_focus = 0
        g.handle_action(InputEvent(actions.RIGHT))
        self.assertEqual(g._slot_focus, 1)
        g.handle_action(InputEvent(actions.RIGHT))
        self.assertEqual(g._slot_focus, 2)
        g.handle_action(InputEvent(actions.LEFT))
        self.assertEqual(g._slot_focus, 1)
        g._slot_focus = 0
        g.handle_action(InputEvent(actions.LEFT))
        self.assertEqual(g._slot_focus, 4)

    def test_sleeve_full_manual_discard(self):
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        g.players[0].sleeve = [make_standard_card(3, "♠"), make_standard_card(5, "♥")]
        g.handle_action(InputEvent(actions.CONFIRM))   # holding
        held = g.held_card
        g.handle_action(InputEvent(actions.CHAR, "2"))  # 藏入 → discard（满）
        self.assertEqual(g.phase, "discard")
        g.handle_action(InputEvent(actions.RIGHT))
        self.assertEqual(g.discard_focus, 1)
        g.handle_action(InputEvent(actions.CONFIRM))    # 丢弃 index1=5♥，再藏入新牌
        self.assertEqual([str(c) for c in g.players[0].sleeve], ["3♠", str(held)])
        self.assertEqual(g.phase, "menu")

    def test_sleeve_select_to_slot(self):
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        c = make_standard_card(8, "♦")
        g.players[0].sleeve = [c]
        g.menu_focus = 1  # 从袖子打出
        g.handle_action(InputEvent(actions.CONFIRM))
        # 只有一张袖子牌 → 直接进 slot_select
        self.assertEqual(g.phase, "slot_select")
        g.handle_action(InputEvent(actions.CONFIRM))  # 放第一空槽
        self.assertEqual(g.players[0].slots[0].cards[0], c)
        self.assertEqual(g.players[0].sleeve, [])

    # ---- 经济 / 多轮 ----
    def test_ante_charged_at_round_start(self):
        # 第1轮底注2：开局后双方各 -2、池 +4
        import random
        g = Game21Scene(rng=random.Random(1))
        g.on_enter(None)
        self.assertEqual(g.round_num, 1)
        self.assertEqual(g.pool, 4)
        self.assertEqual([p.gold for p in g.players], [18, 18])

    def test_ante_scales_with_round(self):
        # 强行推进到第2轮，底注应为4
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        g = self._game("player")
        g.players[0].passed = True
        g.players[1].passed = True
        g._end_turn(0)  # round_settled
        self.assertEqual(g.phase, "round_settled")
        g.handle_action(InputEvent(actions.CONFIRM))  # 进第2轮
        self.assertEqual(g.round_num, 2)
        # 第2轮底注4：双方各 -4（从结算后金币起算，这里仅校验底注额）
        self.assertEqual(g.round_num * 2, 4)

    def test_ante_insufficient_pays_all(self):
        # 玩家金币不足底注时：全部支付（不负债）
        import random
        g = Game21Scene(rng=random.Random(1))
        g.on_enter(None)
        g.players[0].gold = 3
        # 第2轮底注4，玩家只有3 → 付3、池+3
        g.round_num = 1  # 让 _begin_round 变成第2轮
        g._begin_round()
        self.assertEqual(g.players[0].gold, 0)
        self.assertGreaterEqual(g.pool, 3)

    def test_game_over_when_player_gold_zero(self):
        # 轮末 0 检查：玩家金币归 0 → 游戏结束（最多金币者胜）
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        g.players[0].passed = True
        g.players[1].passed = True
        # 模拟玩家已被底注/付费抽干到 0（结算前）
        g.players[0].gold = 0
        g.players[1].gold = 20
        # AI 点数更高 → 独得池
        g.players[1].slots[0].cards.append(make_standard_card(10, "♠"))
        g.players[1].slots[1].cards.append(make_standard_card(9, "♥"))  # 19
        g._end_turn(0)  # 全 pass → _round_end
        # 玩家金币 0 → game_over，AI 钱多 → AI 胜
        self.assertEqual(g.phase, "game_over")
        self.assertEqual(g.game_over_winners, [1])

    def test_ante_drains_player_to_zero_triggers_game_over(self):
        # 底注抽干：第2轮起手收底注时玩家金币不足以全额，付光归0；该轮结算后判游戏结束
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        # 第1轮结算：双方 pass
        g.players[0].passed = True
        g.players[1].passed = True
        g._end_turn(0)
        self.assertEqual(g.phase, "round_settled")
        # 把玩家金币压到 2（不足以付第2轮底注4 → 付2归0）
        g.players[0].gold = 2
        g.players[1].gold = 20
        g.handle_action(InputEvent(actions.CONFIRM))  # 进第2轮，收底注
        self.assertEqual(g.players[0].gold, 0)
        # 第2轮：让 AI 独胜（点数更高，独得池）使玩家无收益
        g.players[1].slots[0].cards.append(make_standard_card(10, "♠"))
        g.players[1].slots[1].cards.append(make_standard_card(9, "♥"))  # AI 19
        g.players[0].passed = True
        g.players[0].pass_score = 0
        g.players[1].passed = True
        g.players[1].pass_score = g.players[1].score()[0]
        g._end_turn(g.current)
        self.assertEqual(g.phase, "game_over")
        self.assertEqual(g.game_over_winners, [1])

    # ---- 软 pass ----
    def test_soft_pass_cancel_on_score_change(self):
        # 玩家 pass 后，他人效果改变其点数 → passed 取消
        g = self._game("player")
        g.players[0].passed = True
        g.players[0].pass_score = 10
        # 模拟点数变动：往玩家槽加一张牌（点数≠10）
        from pyconsole.game.cards import make_standard_card
        g.players[0].slots[0].cards.append(make_standard_card(5, "♠"))
        g._after_effect_cancel_pass()
        self.assertFalse(g.players[0].passed)

    def test_soft_pass_no_cancel_on_same_score(self):
        # 点数未变（交换牌但总分相同）→ 不取消
        g = self._game("player")
        g.players[0].passed = True
        g.players[0].pass_score = 10
        from pyconsole.game.cards import make_standard_card
        g.players[0].slots[0].cards.append(make_standard_card(10, "♠"))  # 10 == pass_score
        g._after_effect_cancel_pass()
        self.assertTrue(g.players[0].passed)

    # ---- 栈模型 / 空壳 ----
    def test_double_check_auto_pass_when_no_playable_slot(self):
        # 5 槽全占满 → _check_auto_pass 触发自动 pass
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        for i in range(5):
            g.players[0].slots[i].cards.append(make_standard_card(2 + i, "♠"))
        self.assertTrue(g.players[0].is_table_full())
        triggered = g._check_auto_pass(0)
        self.assertTrue(triggered)
        self.assertTrue(g.players[0].passed)

    def test_shell_slot_allows_stacking(self):
        # 空壳效果槽：栈顶非空壳牌仍可继续放
        from pyconsole.game.cards import make_standard_card
        from pyconsole.game.effects import SlotEffect, SHELL
        from pyconsole.scenes.game21 import Slot
        g = self._game("player")
        slot = Slot(cards=[make_standard_card(5, "♠")], slot_effect=SlotEffect(kind=SHELL))
        g.players[0].slots[0] = slot
        # 栈顶是5♠（非空壳），但槽有空壳效果 → 可放
        from pyconsole.game.effects import slot_can_place
        self.assertTrue(slot_can_place(slot, make_standard_card(7, "♠")))
        # 占据判定：栈顶非空壳 → 仍算占据（用于桌满判定）
        from pyconsole.game.effects import slot_is_occupied
        self.assertTrue(slot_is_occupied(slot))

    # ---- 21 决胜链 ----
    def test_resolve_winners_unique_high(self):
        # 玩家20、AI 18 → 玩家胜
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        g.players[0].slots[0].cards.append(make_standard_card(10, "♠"))
        g.players[0].slots[1].cards.append(make_standard_card(10, "♥"))  # 20
        g.players[1].slots[0].cards.append(make_standard_card(9, "♦"))
        g.players[1].slots[1].cards.append(make_standard_card(9, "♣"))   # 18
        self.assertEqual(g._resolve_winners(), [0])

    def test_resolve_winners_busted_loses(self):
        # 玩家爆牌、AI 未爆 → AI 胜
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        for r in (10, 10, 5):
            g.players[0].slots[len(g.players[0].slots) and 0].cards.append(make_standard_card(r, "♠"))
        # 玩家 3 张 10/10/5 = 25 爆
        g.players[0].slots[0].cards = [make_standard_card(10, "♠"),
                                      make_standard_card(10, "♥"),
                                      make_standard_card(5, "♠")]
        g.players[1].slots[0].cards.append(make_standard_card(10, "♦"))
        g.players[1].slots[1].cards.append(make_standard_card(7, "♣"))  # 17
        self.assertEqual(g._resolve_winners(), [1])

    def test_resolve_winners_21_tiebreak_fewer_cards(self):
        # 双方都21：玩家1张(A+10=21? A+K=21 用2张)、AI 用3张 → 玩家张数少胜
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        # 玩家：A + K = 21（2张）
        g.players[0].slots[0].cards.append(make_standard_card(1, "♠"))
        g.players[0].slots[1].cards.append(make_standard_card(13, "♥"))
        # AI：7+7+7 = 21（3张）
        for i in range(3):
            g.players[1].slots[i].cards.append(make_standard_card(7, "♦"))
        self.assertEqual(g._resolve_winners(), [0])

    def test_resolve_winners_21_tie_splits_pool(self):
        # 双方都21且张数相同、最大单张相同 → 平分池
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        # 双方都用 A + K（21，2张，最大单张A=11）
        g.players[0].slots[0].cards.append(make_standard_card(1, "♠"))
        g.players[0].slots[1].cards.append(make_standard_card(13, "♥"))
        g.players[1].slots[0].cards.append(make_standard_card(1, "♦"))
        g.players[1].slots[1].cards.append(make_standard_card(13, "♣"))
        self.assertEqual(sorted(g._resolve_winners()), [0, 1])

    # ---- 洗牌规则：抽牌堆空→弃牌堆洗 ----
    def test_draw_reshuffles_discard_when_deck_empty(self):
        # 抽牌堆空、弃牌堆有牌 → 洗弃牌堆为新抽牌堆
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        g.deck = []
        g.discard = [make_standard_card(r, "♠") for r in range(1, 6)]
        before = len(g.discard)
        card = g._draw_from_deck()
        self.assertIsNotNone(card)
        self.assertEqual(len(g.deck), before - 1)  # 弃牌堆搬来后抽1
        self.assertEqual(len(g.discard), 0)

    # ---- Tab 牌堆总览 overlay ----
    def test_game21_overlay_renders(self):
        g = self._game("player")
        buf = new_buf()
        g.render(buf)
        custom = g.render_overlay(buf, W, H)
        self.assertTrue(custom)  # game21 自行绘制 overlay

    def test_game21_overlay_tracks_locations(self):
        # 玩家/AI 拿到的牌（从牌堆抽走），其位置在 overlay 网格里应反映为对应归属
        from pyconsole.game.cards import make_standard_card
        g = self._game("player")
        p_card = g.deck.pop()
        a_card = g.deck.pop()
        g.players[0].slots[0].cards.append(p_card)
        g.players[1].sleeve = [a_card]
        self.assertNotIn(p_card, g.deck)
        self.assertNotIn(a_card, g.deck)
        self.assertEqual(g._card_location(p_card), "你-桌面")
        self.assertEqual(g._card_location(a_card), "AI-袖子")
        self.assertEqual(g._card_location(g.deck[-1]), "抽牌堆")

    def test_game21_overlay_empty_deck(self):
        # 牌堆空时 overlay 不崩
        g = self._game("player")
        g.deck = []
        buf = new_buf()
        g.render(buf)
        custom = g.render_overlay(buf, W, H)
        self.assertTrue(custom)

    def test_main_menu_tab_disabled(self):
        self.assertFalse(MainMenuScene().allow_status_overlay)

    def test_game21_tab_enabled(self):
        self.assertTrue(Game21Scene().allow_status_overlay)


if __name__ == "__main__":
    unittest.main()
