"""把 tools/captures/ 里的截图拼成一张大图，方便一眼看完所有场景。

单张 1280x720 的图在查看器里信息密度太低，拼成 4 列的大图更省事。
用法: python tools/sheet.py [每行张数] [每张宽度]
"""
from __future__ import annotations

import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "captures")
OUT = os.path.join(ROOT, "tools", "_scratch", "sheet.png")


def main() -> None:
    cols = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    cw = int(sys.argv[2]) if len(sys.argv) > 2 else 640

    files = sorted(f for f in os.listdir(SRC) if f.endswith(".png"))
    if not files:
        print("没有截图，先跑 tools/capture.gd")
        return
    ch = int(cw * 9 / 16)
    rows = (len(files) + cols - 1) // cols
    pad = 4
    g = Image.new("RGB", (cols * (cw + pad) + pad, rows * (ch + pad) + pad), (16, 18, 26))
    for i, f in enumerate(files):
        im = Image.open(os.path.join(SRC, f)).convert("RGB").resize((cw, ch), Image.LANCZOS)
        x = pad + (i % cols) * (cw + pad)
        y = pad + (i // cols) * (ch + pad)
        g.paste(im, (x, y))
        print(f"{i:2d} {f}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    g.save(OUT)
    print(OUT, g.size, f"{len(files)} 张")


if __name__ == "__main__":
    main()
