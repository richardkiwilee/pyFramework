#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Godot 看门狗 —— 定时检查 Godot 进程，超时自动关闭窗口
======================================================
逻辑：
  1. 每隔 CHECK_INTERVAL 秒检查一次 Godot 是否在运行；
  2. 一旦检测到"正在运行"，进入计数状态（连续运行次数 streak 累加）；
  3. 若连续 KILL_THRESHOLD 次检查都处于运行状态（默认 36 次 × 5 秒 = 3 分钟），
     强制关闭 Godot 窗口（taskkill /F），并重置计数；
  4. 任意一次检查发现 Godot 未运行 → 计数清零（重新进入待机状态）。

用法：
  python supervisor_godot.py

测试用环境变量（可缩短周期）：
  GODOT_WATCH_INTERVAL  检查间隔秒数（默认 5）
  GODOT_WATCH_THRESHOLD 连续运行多少次后关闭（默认 36）
示例（每 3 秒查一次，连续 2 次就关）：
  GODOT_WATCH_INTERVAL=3 GODOT_WATCH_THRESHOLD=2 python supervisor_godot.py
"""

import os
import subprocess
import time
from datetime import datetime

# 要监控的 Godot 进程名（与游戏可执行文件一致）
PROCESS_NAME = "Godot_v4.6.2-stable_win64.exe"

# 默认参数：每 5 秒检查一次；连续 36 次（3 分钟）在运行则关闭
CHECK_INTERVAL = float(os.environ.get("GODOT_WATCH_INTERVAL", "5"))
KILL_THRESHOLD = int(os.environ.get("GODOT_WATCH_THRESHOLD", "36"))


def _now() -> str:
    return datetime.now().strftime("%H:%M:%S")


def is_running() -> bool:
    """通过 tasklist 判断 Godot 进程是否存在。

    注意两点（踩坑记录）：
    - 默认表格输出的"映像名称"列会被截断到 25 字符，长进程名匹配不到，
      必须用 /FO CSV 格式（不截断）；
    - 输出含中文（GBK 代码页），用字节比较进程名（ASCII）最稳妥。
    """
    try:
        result = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq " + PROCESS_NAME, "/FO", "CSV", "/NH"],
            capture_output=True,
            timeout=10,
        )
        return PROCESS_NAME.encode("ascii") in result.stdout
    except Exception as exc:  # 检查本身出错时视为"未运行"，不打断主循环
        print(f"[{_now()}] 检查失败：{exc}")
        return False


def kill_godot() -> None:
    """强制结束所有 Godot 进程（关闭窗口）。"""
    subprocess.run(
        ["taskkill", "/IM", PROCESS_NAME, "/F"],
        capture_output=True,
        text=True,
    )


def main() -> None:
    print(
        f"[{_now()}] 看门狗启动：每 {CHECK_INTERVAL:g} 秒检查一次，"
        f"连续 {KILL_THRESHOLD} 次在运行（约 {CHECK_INTERVAL * KILL_THRESHOLD / 60:g} 分钟）则关闭 Godot"
    )
    streak = 0
    try:
        while True:
            if is_running():
                streak += 1
                print(f"[{_now()}] Godot 运行中（连续 {streak}/{KILL_THRESHOLD} 次）")
                if streak >= KILL_THRESHOLD:
                    print(f"[{_now()}] 已连续运行约 {streak * CHECK_INTERVAL / 60:.1f} 分钟 → 关闭 Godot 窗口")
                    kill_godot()
                    streak = 0  # 重置状态，重新进入待机
            else:
                if streak > 0:
                    print(f"[{_now()}] Godot 未运行，计数清零")
                streak = 0
            time.sleep(CHECK_INTERVAL)
    except KeyboardInterrupt:
        print(f"\n[{_now()}] 看门狗已停止")


if __name__ == "__main__":
    main()
