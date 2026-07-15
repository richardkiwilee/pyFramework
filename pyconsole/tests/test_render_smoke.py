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


if __name__ == "__main__":
    unittest.main()
