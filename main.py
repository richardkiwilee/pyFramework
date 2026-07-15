"""PyConsole Framework 入口。

运行：python main.py
"""
from __future__ import annotations

import os
import sys

# 确保能 import pyconsole 包
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pyconsole.core.app import App
from pyconsole.core.keys import KeyResolver, load_bindings
from pyconsole.scenes.main_menu import MainMenuScene


def main() -> int:
    # 加载键绑定（默认 + keybindings.json 覆盖，缺失则用默认）
    bindings_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "keybindings.json")
    bindings = load_bindings(bindings_path)
    resolver = KeyResolver(bindings)

    app = App(resolver=resolver)
    try:
        app.run(MainMenuScene())
    except KeyboardInterrupt:
        pass
    finally:
        app.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
