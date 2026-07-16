"""渲染冒烟测试：不输出到终端，只验证场景渲染到 FrameBuffer 不抛异常。

覆盖：主菜单、百科（空查询/有查询/无结果）、MessageScene、Tab overlay。
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
        # 模拟输入 "剑"
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
        # 主菜单空格无效：选中项不变化、不切场景
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        s = MainMenuScene()
        s.on_enter(None)
        before = s.focus
        res = s.handle_action(InputEvent(actions.SELECT))
        self.assertEqual(res.kind, "none")
        self.assertEqual(s.focus, before)

    # ---- 21 点游戏场景冒烟 ----
    def _game(self, first_player="player"):
        # 用注入 rng，并直接设定先后手（绕开 rng 的随机选择），保证测试稳定
        import random
        g = Game21Scene(rng=random.Random(42))
        g.on_enter(None)
        g._tasks.clear()
        g._ai_turn_pending = False
        g.turn = first_player
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
        # 抽牌 → holding
        g.handle_action(InputEvent(actions.CONFIRM))  # 聚焦"抽牌"
        self.assertEqual(g.phase, "holding")
        g.render(new_buf())

    def test_game21_sleeve_select_renders(self):
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        from pyconsole.game.cards import Card
        g = self._game("player")
        # 塞两张牌进袖子，让"从袖子打出"进入 sleeve_select
        g.player.sleeve = [Card(3, "♠"), Card(5, "♥")]
        # 菜单项现在是 [抽牌, 从袖子打出, Pass 停牌] → 索引 1
        g.menu_focus = 1
        g.handle_action(InputEvent(actions.CONFIRM))
        self.assertEqual(g.phase, "sleeve_select")
        g.render(new_buf())

    def test_game21_ai_turn_renders(self):
        g = self._game("ai")
        # AI 回合：on_tick 推进一步
        import time
        g.on_tick(1.0)  # 触发 _ai_turn_pending 排程
        g.render(new_buf())

    def test_game21_advance_ai_to_settled(self):
        # 让 AI 持续行动直到局面推进（不卡死、最终能到 settled）
        g = self._game("ai")
        # 玩家先 pass，使对局只取决于 AI 的动作收敛
        g.player.passed = True
        now = 1.0
        for _ in range(200):
            g.on_tick(now)
            now += 1.0
            if g.phase == "settled":
                break
        g.render(new_buf())
        self.assertEqual(g.phase, "settled")

    def test_game21_settled_renders(self):
        # 直接构造一个已结算状态
        from pyconsole.game.cards import Card
        g = self._game("player")
        g.player.slots[0] = Card(10, "♠")
        g.player.slots[1] = Card(9, "♥")
        g.ai.slots[0] = Card(5, "♦")
        g.ai.slots[1] = Card(6, "♣")
        g.player.passed = True
        g.ai.passed = True
        g.settle()
        self.assertEqual(g.phase, "settled")
        g.render(new_buf())

    # ---- 新规则：5 卡槽 / 手动选槽 / 袖子满手动弃 / 抽牌锁定 ----
    def test_slots_default_five_and_empty(self):
        g = self._game("player")
        self.assertEqual(len(g.player.slots), 5)
        self.assertTrue(all(s is None for s in g.player.slots))
        self.assertEqual(g.player.first_free_slot(), 0)
        self.assertEqual(g.player.table, [])  # 只读视图

    def test_table_is_read_only_view_of_slots(self):
        from pyconsole.game.cards import Card
        g = self._game("player")
        g.player.slots[2] = Card(7, "♠")
        self.assertEqual(g.player.table, [Card(7, "♠")])

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
        g.menu_focus = len(g._menu_items()) - 1  # 聚焦 Pass
        g.handle_action(InputEvent(actions.CONFIRM))
        # Pass 被拒：仍在 menu、玩家未停牌
        self.assertEqual(g.phase, "menu")
        self.assertFalse(g.player.passed)

    def test_stash_does_not_end_turn_then_play_ends_turn(self):
        # 抽→藏→抽→打：合法；打出后才结束回合
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        g = self._game("player")
        # 第一次抽牌
        g.handle_action(InputEvent(actions.CONFIRM))   # holding
        held1 = g.held_card
        g.handle_action(InputEvent(actions.CHAR, "2"))  # 藏入袖子
        self.assertEqual(len(g.player.sleeve), 1)
        self.assertEqual(g.phase, "menu")
        self.assertTrue(g._drawn_this_turn)
        # 第二次抽牌
        g.handle_action(InputEvent(actions.CONFIRM))   # holding
        self.assertNotEqual(g.held_card, held1)  # 是另一张
        # 打出（进入卡槽选择后回车确认放第一个空槽）
        g.handle_action(InputEvent(actions.CHAR, "1"))  # 打出 → slot_select
        self.assertEqual(g.phase, "slot_select")
        g.handle_action(InputEvent(actions.CONFIRM))    # 放到焦点空槽
        # 打出 → 回合结束，交回对方（AI），抽牌标志清零
        self.assertFalse(g._drawn_this_turn)
        self.assertIn(g.phase, ("ai_turn",))  # 已交给 AI

    def test_place_to_occupied_slot_fails_and_reselects(self):
        # 占用槽放置失败，停留重选；改放空槽成功
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        from pyconsole.game.cards import Card
        g = self._game("player")
        # 预占卡槽 2
        g.player.slots[1] = Card(5, "♣")
        # 抽牌 → 打出 → slot_select
        g.handle_action(InputEvent(actions.CONFIRM))
        g.handle_action(InputEvent(actions.CHAR, "1"))  # 打出
        self.assertEqual(g.phase, "slot_select")
        before = list(c for c in g.player.slots if c)
        # 直接选卡槽 2（已占用）：放置失败
        g.handle_action(InputEvent(actions.CHAR, "2"))
        self.assertEqual(g.phase, "slot_select")  # 仍在重选
        self.assertEqual([c for c in g.player.slots if c], before)  # 桌面无变化
        # 改选卡槽 1（空）：放置成功
        g.handle_action(InputEvent(actions.CHAR, "1"))
        self.assertIsNotNone(g.player.slots[0])

    def test_slot_focus_cycles_left_right(self):
        # ←/→ 在 slot_select 内循环切换 _slot_focus
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
        # 从 0 向左循环到 4
        g._slot_focus = 0
        g.handle_action(InputEvent(actions.LEFT))
        self.assertEqual(g._slot_focus, 4)

    def test_sleeve_full_manual_discard(self):
        # 袖子满 2 张再藏入：进入 discard 手动选择丢弃哪张
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        from pyconsole.game.cards import Card
        g = self._game("player")
        g.player.sleeve = [Card(3, "♠"), Card(5, "♥")]
        # 抽一张牌准备藏
        g.handle_action(InputEvent(actions.CONFIRM))   # holding
        held = g.held_card
        # 选藏入袖子（holding 选项 2）
        g.handle_action(InputEvent(actions.CHAR, "2"))
        self.assertEqual(g.phase, "discard")  # 进入手动丢弃
        # ←→ 切换丢弃焦点
        g.handle_action(InputEvent(actions.RIGHT))
        self.assertEqual(g.discard_focus, 1)
        # 回车丢弃选中（index 1 = 5♥），再藏入新牌
        g.handle_action(InputEvent(actions.CONFIRM))
        self.assertEqual(g.player.sleeve, [Card(3, "♠"), held])
        self.assertEqual(g.phase, "menu")

    def test_sleeve_select_to_slot(self):
        # 从袖子打出：选袖子牌 → 选卡槽 → 放置成功
        from pyconsole.core.actions import InputEvent
        from pyconsole.core import actions
        from pyconsole.game.cards import Card
        g = self._game("player")
        c = Card(8, "♦")
        g.player.sleeve = [c]
        # 菜单：抽牌(0) / 从袖子打出(1) / Pass(2)
        g.menu_focus = 1
        g.handle_action(InputEvent(actions.CONFIRM))
        # 只有一张袖子牌 → 直接进 slot_select
        self.assertEqual(g.phase, "slot_select")
        g.handle_action(InputEvent(actions.CONFIRM))  # 放第一空槽
        self.assertEqual(g.player.slots[0], c)
        self.assertEqual(g.player.sleeve, [])

    # ---- Tab 牌堆总览 overlay ----
    def test_game21_overlay_renders(self):
        # 按住 Tab：完整牌堆网格 + 左上角抽牌堆顶隐写卡背，渲染不抛
        g = self._game("player")
        buf = new_buf()
        g.render(buf)
        custom = g.render_overlay(buf, W, H)
        self.assertTrue(custom)  # game21 自行绘制 overlay

    def test_game21_overlay_stealth_decodes(self):
        # 抽牌堆顶牌应可从 overlay 左上角卡背解码还原
        from pyconsole.game.card_back import decode_card_back, SUIT_TO_CODE
        from pyconsole.game.cards import rank_label
        g = self._game("player")
        buf = new_buf()
        g.render(buf)
        g.render_overlay(buf, W, H)
        # 卡背 19x11 位于面板左上 (px+2, py+2)；用解码逻辑在缓冲里找
        # 直接重建：overlay 用的就是 deck[-1]
        top = g.deck[-1]
        # 在缓冲里搜出 19x11 的卡背区域并解码
        art = _extract_card_art(buf, W, H, 19, 11)
        decoded = decode_card_back(art)
        expected = f"{rank_label(top.rank)}{SUIT_TO_CODE[top.suit]}"
        self.assertEqual(decoded, expected)

    def test_game21_overlay_tracks_locations(self):
        # 玩家/AI 拿到的牌（从牌堆抽走），其位置在 overlay 网格里应反映为对应归属
        from pyconsole.game.cards import Card
        g = self._game("player")
        # 从牌堆真实抽牌（pop），保证一张牌只在一个位置
        p_card = g.deck.pop()
        a_card = g.deck.pop()
        g.player.slots[0] = p_card
        g.ai.sleeve = [a_card]
        self.assertNotIn(p_card, g.deck)
        self.assertNotIn(a_card, g.deck)
        self.assertEqual(g._card_location(p_card), "你-桌面")
        self.assertEqual(g._card_location(a_card), "AI-袖子")
        # 仍在牌堆里的牌应定位为"抽牌堆"
        still_in_deck = g.deck[-1]
        self.assertEqual(g._card_location(still_in_deck), "抽牌堆")

    def test_game21_overlay_empty_deck(self):
        # 牌堆空时 overlay 不崩
        g = self._game("player")
        g.deck = []
        buf = new_buf()
        g.render(buf)
        custom = g.render_overlay(buf, W, H)
        self.assertTrue(custom)

    def test_main_menu_tab_disabled(self):
        # 主菜单 allow_status_overlay=False：Tab 不应被允许
        self.assertFalse(MainMenuScene().allow_status_overlay)

    def test_game21_tab_enabled(self):
        # 21 点 allow_status_overlay=True：Tab 可用
        self.assertTrue(Game21Scene().allow_status_overlay)


def _extract_card_art(buf, w, h, cw, ch):
    """在缓冲里找到第一个 19x11 的卡背区域并读回为 ASCII（供解码验证）。"""
    # 卡背左上角是 '┌'；扫描找到第一个 ┌ 起始、且右下是 ┘ 的 19x11 区域
    cells = buf.cells
    for y in range(h - ch + 1):
        for x in range(w - cw + 1):
            if cells[y][x].char != "┌":
                continue
            if cells[y + ch - 1][x + cw - 1].char != "┘":
                continue
            lines = []
            for ry in range(y, y + ch):
                lines.append("".join(cells[ry][rx].char or " " for rx in range(x, x + cw)))
            return "\n".join(lines)
    raise AssertionError("未在缓冲中找到 19x11 卡背区域")


if __name__ == "__main__":
    unittest.main()
