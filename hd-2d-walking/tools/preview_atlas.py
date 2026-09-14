"""把 objects.png 里每个精灵单独放大 + 标注名字，输出到 tools/_scratch/。
只用在开发期肉眼核对美术，不参与游戏运行。"""
from __future__ import annotations

import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRATCH = os.path.join(ROOT, "tools", "_scratch")
CELL = 3  # 放大倍数
COLS = 7


def main() -> None:
    os.makedirs(SCRATCH, exist_ok=True)
    sheet = Image.open(os.path.join(ROOT, "assets", "world", "objects.png")).convert("RGBA")
    with open(os.path.join(ROOT, "assets", "world", "objects.json"), encoding="utf-8") as f:
        meta = json.load(f)

    names = sorted(meta, key=lambda n: (meta[n]["h"], n))
    cw = max(meta[n]["w"] for n in names) * CELL + 12
    ch = max(meta[n]["h"] for n in names) * CELL + 26
    rows = (len(names) + COLS - 1) // COLS
    g = Image.new("RGBA", (cw * COLS, ch * rows), (58, 62, 74, 255))
    d = ImageDraw.Draw(g)

    for i, n in enumerate(names):
        m = meta[n]
        sp = sheet.crop((m["x"], m["y"], m["x"] + m["w"], m["y"] + m["h"]))
        sp = sp.resize((m["w"] * CELL, m["h"] * CELL), Image.NEAREST)
        cx, cy = (i % COLS) * cw, (i // COLS) * ch
        # 画地面参考线（接地锚点所在的水平线）
        ay = cy + 20 + m["ay"] * CELL
        d.line([(cx, ay), (cx + cw, ay)], fill=(120, 200, 120, 255))
        g.alpha_composite(sp, (cx + 6, cy + 20))
        d.text((cx + 6, cy + 4), f"{n} {m['w']}x{m['h']}", fill=(255, 232, 150, 255))

    out = os.path.join(SCRATCH, "atlas_labeled.png")
    g.save(out)
    print(out, g.size)


if __name__ == "__main__":
    main()
