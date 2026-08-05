"""TheGreatConquest TUI 入口。

运行：
    C:\\.env311\\Scripts\\python.exe python-demo/main_tui.py

使用本游戏专属键绑定（pydemo.tui.keys.resolver）构造 App，
从主菜单场景开始运行场景栈。
"""
from __future__ import annotations

import os
import sys


def main() -> None:
    # 让 import 能找到 pyconsole 与 pydemo（两包都在 python-demo/ 下）
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)

    # Windows 控制台默认编码可能是 GBK，强制 UTF-8 以正确显示中文
    try:
        sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
        sys.stdin.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    except Exception:
        pass

    from pyconsole.core.app import App
    from pydemo.tui.keys import resolver
    from pydemo.tui.scenes.main_menu import MainMenuScene

    app = App(resolver=resolver)
    app.startup()
    try:
        app.run(MainMenuScene())
    except KeyboardInterrupt:
        pass
    finally:
        # 退出时清屏复位终端
        sys.stdout.write("\x1b[2J\x1b[H")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
