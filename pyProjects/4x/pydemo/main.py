"""
TheGreatConquest - Python 原型入口。

运行:
    python -m pydemo.main
"""
from __future__ import annotations
import sys
from .cli.fsm import ConsoleFSM


def main() -> None:
    # Windows 控制台默认编码可能是 GBK,强制 UTF-8 以正确显示中文。
    try:
        sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
        sys.stdin.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    except Exception:
        pass
    fsm = ConsoleFSM()
    try:
        fsm.run()
    except KeyboardInterrupt:
        print("\n中断,退出。")
        raise SystemExit(0)


if __name__ == "__main__":
    main()
