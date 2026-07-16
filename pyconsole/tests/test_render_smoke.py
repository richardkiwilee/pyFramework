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
        g.player.table = [Card(10, "♠"), Card(9, "♥")]
        g.ai.table = [Card(5, "♦"), Card(6, "♣")]
        g.player.passed = True
        g.ai.passed = True
        g.settle()
        self.assertEqual(g.phase, "settled")
        g.render(new_buf())


if __name__ == "__main__":
    unittest.main()
