"""按游戏里的投影与深度规则把整张世界合成出来，用于开发期肉眼检查。

用法:  python tools/preview_world.py [中心格x] [中心格y] [输出宽度格数]
默认合成村庄附近。这与 Godot 端用的是同一套公式，所以这里对了，游戏里就对。
"""
from __future__ import annotations

import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "world")
SCRATCH = os.path.join(ROOT, "tools", "_scratch")


def main() -> None:
    cx = float(sys.argv[1]) if len(sys.argv) > 1 else 52.0
    cy = float(sys.argv[2]) if len(sys.argv) > 2 else 70.0
    view_w = int(sys.argv[3]) if len(sys.argv) > 3 else 44   # 视野宽度（格）

    world = json.load(open(os.path.join(OUT, "world.json"), encoding="utf-8"))
    TS, ELEV = world["tile"], world["elev_h"]
    WT, HT = world["w"], world["h"]
    hmap = [[int(c) for c in row] for row in world["height"]]

    full_w = WT * TS
    full_h = HT * TS + world["max_h"] * ELEV + 64
    canvas = Image.new("RGBA", (full_w, full_h), (0, 0, 0, 0))
    for b in world["bands"]:
        img = Image.open(os.path.join(OUT, b["file"])).convert("RGBA")
        canvas.alpha_composite(img, (0, b["y"]))

    sheet = Image.open(os.path.join(OUT, "objects.png")).convert("RGBA")
    meta = json.load(open(os.path.join(OUT, "objects.json"), encoding="utf-8"))

    def depth(o) -> int:
        return int(o["y"]) * ELEV + int(o["h"]) * 16

    objs = sorted(world["objects"], key=depth)
    for o in objs:
        m = meta.get(o["n"])
        if m is None:
            continue
        sp = sheet.crop((m["x"], m["y"], m["x"] + m["w"], m["y"] + m["h"]))
        px = o["x"] * TS + o["ox"] - m["ax"]
        py = o["y"] * TS - o["h"] * ELEV + o["oy"] - m["ay"]
        canvas.alpha_composite(sp, (int(round(px)), int(round(py))))

    # 世界边界画个框，方便确认没有越界
    half_w = view_w * TS // 2
    half_h = int(half_w * 9 / 16)
    ccx = int(cx * TS)
    ccy = int(cy * TS - 3 * ELEV)
    box = (max(0, ccx - half_w), max(0, ccy - half_h),
           min(full_w, ccx + half_w), min(full_h, ccy + half_h))
    crop = canvas.crop(box)
    bg = Image.new("RGBA", crop.size, (24, 30, 44, 255))
    bg.alpha_composite(crop)
    os.makedirs(SCRATCH, exist_ok=True)
    out = os.path.join(SCRATCH, "world_view.png")
    bg.convert("RGB").save(out)
    print(out, bg.size)


if __name__ == "__main__":
    main()
