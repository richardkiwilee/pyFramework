"""生成世界物件精灵（树 / 建筑 / 道具 / 地面贴花），打包成单张图集。

输出:
  assets/world/objects.png    图集
  assets/world/objects.json   {name: {x, y, w, h, ax, ay}}  ay/ax = 接地锚点在图内偏移
  assets/characters/hero_*.png  角色 4 向行走条带（从免费角色包裁切对齐）

图集存在的意义：所有精灵共用一张 texture，Godot 2D 批处理才能生效。
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field

import numpy as np
from PIL import Image

from pixelkit import C, Canvas, dilate, erode, rim, shift

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_WORLD = os.path.join(ROOT, "assets", "world")
OUT_CHAR = os.path.join(ROOT, "assets", "characters")
CHAR_SHEET = os.path.join("D:/godot-tools/free-character-pack",
                          "002-1787672205983-frames64.png")


# ==================================================================== 图集


@dataclass
class Sprite:
    img: Image.Image
    ax: int  # 接地锚点（图内坐标）
    ay: int
    hull: list[list[int]] = field(default_factory=list)   # 阴影遮挡多边形（图内坐标）


def convex_hull(pts: np.ndarray, max_pts: int = 14) -> list[list[int]]:
    """Andrew 单调链求凸包，再抽稀到 max_pts 个点。给 Godot 当 2D 阴影遮挡多边形。"""
    p = sorted({(int(x), int(y)) for x, y in pts})
    if len(p) < 3:
        return [list(q) for q in p]

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list = []
    for q in p:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], q) <= 0:
            lower.pop()
        lower.append(q)
    upper: list = []
    for q in reversed(p):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], q) <= 0:
            upper.pop()
        upper.append(q)
    hull = lower[:-1] + upper[:-1]
    if len(hull) > max_pts:
        step = len(hull) / max_pts
        hull = [hull[int(i * step)] for i in range(max_pts)]
    return [list(q) for q in hull]


@dataclass
class Atlas:
    items: dict[str, Sprite] = field(default_factory=dict)

    def add(self, name: str, img: Image.Image, ax: int, ay: int) -> None:
        arr = np.array(img)
        ys, xs = np.nonzero(arr[:, :, 3] > 8)
        if len(xs) == 0:
            raise ValueError(f"{name} 完全是空的")
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1

        # 遮挡多边形用"实心区域"的凸包（排除描边外的零散像素）
        mask = arr[:, :, 3] > 160
        ys2, xs2 = np.nonzero(mask)
        hull = convex_hull(np.stack([xs2, ys2], axis=1)) if len(xs2) >= 3 else []

        self.items[name] = Sprite(
            img.crop((int(x0), int(y0), int(x1), int(y1))), int(ax - x0), int(ay - y0),
            hull=[[int(px - x0), int(py - y0)] for px, py in hull],
        )

    def save(self, prefix: str, pad: int = 1) -> None:
        names = sorted(self.items)
        # 货架式打包：按高度降序，行内左到右
        order = sorted(names, key=lambda n: -self.items[n].img.height)
        max_w = 512
        rows: list[list[str]] = []
        cur: list[str] = []
        cur_w = 0
        for n in order:
            w = self.items[n].img.width + pad
            if cur and cur_w + w > max_w:
                rows.append(cur)
                cur, cur_w = [], 0
            cur.append(n)
            cur_w += w
        if cur:
            rows.append(cur)

        width = max(sum(self.items[n].img.width + pad for n in r) for r in rows)
        height = sum(max(self.items[n].img.height for n in r) + pad for r in rows)
        sheet = Image.new("RGBA", (width, height), (0, 0, 0, 0))

        meta: dict[str, dict[str, int]] = {}
        y = 0
        for r in rows:
            x = 0
            rh = max(self.items[n].img.height for n in r)
            for n in r:
                sp = self.items[n]
                sheet.paste(sp.img, (x, y))
                # 只写渲染真正要用的字段。以前这里还带一个 hull 凸包，
                # 是给 LightOccluder2D 用的；改用仿射投影阴影之后没人读了，
                # 留着只会让人以为碰撞/遮挡用的是凸包。
                meta[n] = {"x": x, "y": y, "w": sp.img.width, "h": sp.img.height,
                           "ax": sp.ax, "ay": sp.ay}
                x += sp.img.width + pad
            y += rh + pad

        sheet.save(prefix + ".png")
        with open(prefix + ".json", "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=1, sort_keys=True)
        print(f"图集 {os.path.basename(prefix)}.png  {width}x{height}  {len(names)} 个精灵")


# ==================================================================== 树


def _trunk(cv: Canvas, cx: float, base_y: float, height: float, w_top: float,
           w_bot: float, seed: int) -> np.ndarray:
    """树干：底部宽、顶部窄，带左受光右背光和几条树皮纹。"""
    rng = np.random.default_rng(seed)
    m = np.zeros((cv.h, cv.w), bool)
    for i in range(int(height)):
        t = i / max(height - 1, 1)
        yy = int(base_y - i)
        hw = (w_bot + (w_top - w_bot) * t) / 2.0
        jitter = int(round(np.sin(i * 0.9 + seed) * 0.6))
        x0 = int(round(cx - hw)) + jitter
        x1 = int(round(cx + hw)) + jitter
        m |= cv.rect(x0, yy, max(1, x1 - x0), 1)
    m = shift(m, 0, 0)
    cv.blank(dilate(m, 1) & ~m, C("line"))
    cv.blank(m, C("wood_base"))
    cv.blank(rim(m, -1, -1) | rim(m, 0, -1), C("wood_lit"))
    cv.blank(rim(m, 1, 0) | rim(m, 1, 1), C("wood_dark"))
    # 树皮纹
    for _ in range(max(2, int(height / 6))):
        by = int(rng.uniform(base_y - height * 0.8, base_y - 1))
        bx = int(cx - w_bot / 2 + rng.integers(0, max(1, int(w_bot))))
        cv.blank(cv.rect(bx, by, 1, int(rng.integers(2, 4))) & m, C("wood_dark"))
    return m


def _foliage(cv: Canvas, blobs: list[tuple[float, float, float]], pal: tuple[str, ...],
             seed: int, clumpy: bool = True) -> np.ndarray:
    """团块树冠：多个圆取并集，每团自己带左上受光，整体再加一圈高光。"""
    deep, dark, base, lit, hi = pal
    rng = np.random.default_rng(seed)
    mask = np.zeros((cv.h, cv.w), bool)
    for (bx, by, br) in blobs:
        mask |= cv.circle(bx, by, br)

    mask = erode(mask, 0)
    cv.blank(dilate(mask, 1) & ~mask, C("line"))
    cv.blank(mask, C(dark))

    # 每团的左上受光
    for (bx, by, br) in blobs:
        b = cv.circle(bx, by, br) & mask
        if clumpy:
            cv.blank(shift(b, -2, -2) & b, C(base))
            cv.blank(shift(b, -3, -3) & b, C(lit))
        else:
            cv.blank(b & mask, C(base))

    # 整体左上边缘的强高光
    cv.blank(shift(mask, -2, -2) & mask & dilate(shift(mask, 1, 1) & ~mask, 1), C(lit))
    edge = dilate(mask, 2) & ~dilate(mask, 0)
    cv.blank(shift(mask, -1, -1) & shift(edge, -3, -3), C(hi))

    # 底部背光
    cv.blank(mask & shift(mask, 2, 3), C(deep))

    # 随机叶隙（暗色小洞，打散大面积平板感）
    ys, xs = np.nonzero(mask)
    for _ in range(int(len(xs) * 0.05)):
        i = rng.integers(0, len(xs))
        px, py = int(xs[i]), int(ys[i])
        if px < 3 or py < 3 or px > cv.w - 4 or py > cv.h - 4:
            continue
        r = int(rng.integers(1, 3))
        cv.blank(cv.circle(px, py, r) & mask, C(deep))
    return mask


def tree_broadleaf(seed: int, scale: float = 1.0, pal: tuple[str, ...] | None = None) -> Canvas:
    pal = pal or ("leaf_deep", "leaf_dark", "leaf_base", "leaf_lit", "leaf_hi")
    W, H = int(58 * scale), int(70 * scale)
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    cx = W / 2 + rng.uniform(-1.5, 1.5)
    base_y = H - 2.0
    trunk_h = 20 * scale
    _trunk(cv, cx, base_y, trunk_h + 6 * scale, 5 * scale, 8 * scale, seed)

    cy = base_y - trunk_h - 12 * scale
    R = 15 * scale
    blobs = [(cx + rng.uniform(-3, 3), cy + rng.uniform(-2, 2), R * 0.95)]
    for i in range(6):
        a = i / 6.0 * 2 * np.pi + rng.uniform(-0.35, 0.35)
        rr = R * rng.uniform(0.5, 0.72)
        blobs.append((cx + np.cos(a) * R * 0.72, cy + np.sin(a) * R * 0.58, rr))
    blobs.append((cx + rng.uniform(-5, 5), cy - R * 0.55, R * 0.6))
    _foliage(cv, blobs, pal, seed + 7)
    return cv


def tree_pine(seed: int, scale: float = 1.0) -> Canvas:
    W, H = int(44 * scale), int(84 * scale)
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    cx = W / 2
    base_y = H - 2.0
    _trunk(cv, cx, base_y, 12 * scale, 4 * scale, 6 * scale, seed)

    tiers = 4
    top_y = 6 * scale
    tier_h = (base_y - 12 * scale - top_y) / tiers
    mask = np.zeros((H, W), bool)
    for t in range(tiers):
        y0 = top_y + t * tier_h
        y1 = y0 + tier_h * 1.30
        hw = (4 + (t + 1) * 4.4) * scale
        # 三角形树冠 + 锯齿下沿（松针感）
        pts: list[tuple[float, float]] = [(cx, y0), (cx + hw, y1)]
        n = max(4, int(hw * 1.4))
        for s in range(1, n):
            xx = (cx + hw) - 2 * hw * s / n
            pts.append((xx, y1 - (3 if s % 2 else 0) * scale))
        pts.append((cx - hw, y1))
        mask |= cv.poly(pts)

    cv.blank(dilate(mask, 1) & ~mask, C("line"))
    cv.blank(mask, C("pine_dark"))
    cv.blank(shift(mask, -2, -1) & mask, C("pine_base"))
    cv.blank(shift(mask, -3, -2) & mask, C("pine_lit"))
    cv.blank(shift(mask, -4, -3) & mask, C("pine_hi"))
    cv.blank(mask & shift(mask, 2, 2), C("pine_deep"))
    # 针叶竖纹
    ys, xs = np.nonzero(mask)
    for _ in range(int(len(xs) * 0.03)):
        i = rng.integers(0, len(xs))
        px, py = int(xs[i]), int(ys[i])
        cv.blank(cv.rect(px, py, 1, int(rng.integers(2, 4))) & mask, C("pine_deep"))
    return cv


AUTUMN = ("aut_deep", "aut_dark", "aut_base", "aut_lit", "aut_hi")
DARKLEAF = ("leaf_deep", "pine_deep", "leaf_dark", "leaf_base", "leaf_lit")


def bush(seed: int, pal: tuple[str, ...] | None = None) -> Canvas:
    pal = pal or ("leaf_deep", "leaf_dark", "leaf_base", "leaf_lit", "leaf_hi")
    W, H = 26, 22
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    blobs = []
    for i in range(4):
        blobs.append((W / 2 + rng.uniform(-5, 5), H - 7 + rng.uniform(-3, 3),
                      rng.uniform(4.5, 7.5)))
    _foliage(cv, blobs, pal, seed)
    return cv


def rock(seed: int, scale: float = 1.0) -> Canvas:
    W, H = int(24 * scale), int(18 * scale)
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    m = np.zeros((H, W), bool)
    n = 5
    pts = []
    for i in range(n):
        a = i / n * 2 * np.pi
        r = (W * 0.36) * (0.75 + 0.45 * float(rng.random()))
        pts.append((W / 2 + np.cos(a) * r, H - 3 + np.sin(a) * (H * 0.28)))
    m = cv.poly(pts)
    m &= cv.rect(0, 0, W, H - 1)
    cv.blank(dilate(m, 1) & ~m, C("line"))
    cv.blank(m, C("rock_base"))
    cv.blank(shift(m, -2, -2) & m, C("rock_lit"))
    cv.blank(shift(m, -3, -3) & m, C("rock_hi"))
    cv.blank(m & shift(m, 1, 2), C("rock_deep"))
    cv.blank(cv.line(int(W * 0.35), int(H * 0.35), int(W * 0.62), int(H * 0.6)) & m,
             C("rock_dark"))
    return cv


# ==================================================================== 建筑


def _shingles(cv: Canvas, poly: np.ndarray, pal: str, x0: int, x1: int,
              y0: int, y1: int, step: int, seed: int) -> None:
    """在屋顶多边形内画瓦垄：横线 + 交错竖缝。"""
    rng = np.random.default_rng(seed)
    for y in range(y0, y1, step):
        cv.blank(cv.rect(x0, y, x1 - x0, 1) & poly, C(pal + "_deep"))
    for y in range(y0, y1, step):
        off = (y // step) % 2
        for x in range(x0 + off * step // 2, x1, step):
            cv.blank(cv.rect(x, y + 1, 1, step - 1) & poly, C(pal + "_dark"))


def make_house(w: int, h: int, roof_pal: str, seed: int, *,
               door_offset: float = 0.0, windows: int = 2,
               chimney: bool = True, beams: bool = True) -> Canvas:
    cv = Canvas(w, h)
    rng = np.random.default_rng(seed)

    wall_x0, wall_x1 = int(w * 0.14), int(w * 0.86)
    roof_y = int(h * 0.40)
    base_y = h - 2
    ov = max(3, int(w * 0.10))
    ridge_x0, ridge_x1 = wall_x0 + int(w * 0.15), wall_x1 - int(w * 0.15)
    ridge_y = int(h * 0.07)

    wall = cv.rect(wall_x0, roof_y, wall_x1 - wall_x0, base_y - roof_y)
    roof = cv.poly([(ridge_x0, ridge_y), (ridge_x1, ridge_y),
                    (wall_x1 + ov, roof_y + 1), (wall_x0 - ov, roof_y + 1)])
    chimney_m = np.zeros((h, w), bool)
    if chimney:
        chx = wall_x1 - int(w * 0.22)
        chimney_m = cv.rect(chx, ridge_y - int(h * 0.07), max(6, int(w * 0.11)),
                            int(h * 0.16))

    body = wall | roof | chimney_m
    cv.blank(dilate(body, 1) & ~body, C("line"))

    # --- 墙
    cv.blank(wall, C("wall_base"))
    cv.blank(rim(wall, 0, -1) | rim(wall, 1, 0), C("wall_deep"))   # 檐下阴影
    cv.blank(cv.rect(wall_x0, roof_y, wall_x1 - wall_x0, max(2, int(h * 0.05))), C("wall_dark"))
    cv.blank(cv.rect(wall_x0, base_y - 3, wall_x1 - wall_x0, 3), C("wall_dark"))
    cv.blank(rim(wall, -1, 0), C("wall_lit"))
    if beams:
        for bx in range(wall_x0 + 2, wall_x1 - 2, max(9, int(w * 0.16))):
            cv.blank(cv.rect(bx, roof_y + 1, 2, base_y - roof_y - 2) & wall, C("wood_dark"))
        cv.blank(cv.rect(wall_x0, roof_y + 1, wall_x1 - wall_x0, 2) & wall, C("wood_deep"))

    # --- 门
    dw, dh = max(8, int(w * 0.16)), max(13, int(h * 0.22))
    dx = int((wall_x0 + wall_x1) / 2 - dw / 2 + door_offset * w)
    door = cv.rect(dx, base_y - dh, dw, dh) & wall
    cv.blank(door, C("wood_deep"))
    cv.blank(cv.rect(dx + 1, base_y - dh + 1, dw - 2, dh - 1) & wall, C("wood_base"))
    cv.blank(cv.rect(dx + 1, base_y - dh + 1, 1, dh - 1) & wall, C("wood_lit"))
    cv.blank(cv.rect(dx + dw // 2, base_y - dh + 1, 1, dh - 1) & wall, C("wood_deep"))
    cv.blank(cv.rect(dx + dw - 3, base_y - dh + int(dh * 0.45), 2, 2) & wall, C("rock_hi"))

    # --- 窗
    if windows > 0:
        ww, wh = max(8, int(w * 0.15)), max(7, int(h * 0.13))
        wy = roof_y + int((base_y - roof_y) * 0.26)
        span = wall_x1 - wall_x0
        for i in range(windows):
            wx = wall_x0 + int(span * (0.24 + 0.52 * i / max(1, windows - 1 or 1)))
            wx = wall_x0 + int(span * (0.20 + 0.60 * (i + 0.5) / windows))
            win = cv.rect(wx - ww // 2, wy, ww, wh) & wall
            cv.blank(dilate(win, 1) & wall & ~win, C("wood_deep"))
            cv.blank(win, C("glass_dark"))
            cv.blank(rim(win, -1, -1), C("glass_lit"))
            cv.blank(cv.rect(wx - 1, wy, 1, wh) & win, C("wood_dark"))
            cv.blank(cv.rect(wx - ww // 2, wy + wh // 2, ww, 1) & win, C("wood_dark"))

    # --- 屋顶
    cv.blank(roof, C(roof_pal + "_base"))
    _shingles(cv, roof, roof_pal, wall_x0 - ov, wall_x1 + ov, ridge_y, roof_y + 1,
              max(4, int(h * 0.055)), seed)
    cv.blank(shift(roof, -2, -1) & roof, C(roof_pal + "_lit"))
    cv.blank(shift(roof, -3, -2) & roof, C(roof_pal + "_hi"))
    cv.blank(rim(roof, 1, 1) | rim(roof, 0, 1), C(roof_pal + "_deep"))
    cv.blank(cv.rect(ridge_x0, ridge_y, ridge_x1 - ridge_x0, 2), C(roof_pal + "_lit"))
    cv.blank(cv.rect(ridge_x0, ridge_y + 2, ridge_x1 - ridge_x0, 1), C(roof_pal + "_deep"))

    # --- 烟囱
    if chimney:
        cv.blank(chimney_m, C("rock_dark"))
        cv.blank(rim(chimney_m, -1, 0) | rim(chimney_m, 0, -1), C("rock_base"))
        top = chimney_m & shift(chimney_m, 0, -1)
        cv.blank(cv.rect(chx, ridge_y - int(h * 0.07), max(6, int(w * 0.11)), 3), C("rock_deep"))
        cv.blank(cv.rect(chx, ridge_y - int(h * 0.07), max(6, int(w * 0.11)), 1), C("line"))
        _ = top
    return cv


def make_barn(seed: int) -> Canvas:
    cv = make_house(92, 80, "thatch", seed, door_offset=0.0, windows=0, beams=False)
    # 大门 + 干草阁楼口
    cv.blank(cv.rect(30, 44, 32, 32), C("wood_deep"))
    cv.blank(cv.rect(32, 46, 28, 30), C("wood_dark"))
    for x in range(34, 60, 6):
        cv.blank(cv.rect(x, 46, 2, 30), C("wood_base"))
    cv.blank(cv.rect(44, 46, 2, 30), C("wood_deep"))
    cv.blank(cv.rect(38, 20, 16, 14), C("wood_deep"))
    cv.blank(cv.rect(39, 21, 14, 12), C("glass_dark"))
    return cv


def make_windmill(seed: int) -> tuple[Canvas, Canvas]:
    """返回 (塔身, 扇叶)。扇叶单独一张，运行时旋转。"""
    W, H = 52, 112
    cv = Canvas(W, H)
    base_y = H - 2
    cx = W / 2
    top_y = int(H * 0.20)
    tower = cv.poly([(cx - 8, top_y), (cx + 8, top_y),
                     (cx + 15, base_y), (cx - 15, base_y)])
    cv.blank(dilate(tower, 1) & ~tower, C("line"))
    cv.blank(tower, C("wall_base"))
    cv.blank(rim(tower, -1, 0), C("wall_lit"))
    cv.blank(rim(tower, 1, 0), C("wall_dark"))
    for i in range(6):
        y = top_y + int((base_y - top_y) * i / 6)
        hw = 8 + 7 * (y - top_y) / max(1, base_y - top_y)
        cv.blank(cv.rect(int(cx - hw), y, int(hw * 2), 2) & tower, C("wood_dark"))
    cv.blank(cv.rect(int(cx - 4), base_y - 16, 9, 16) & tower, C("wood_deep"))
    cv.blank(cv.rect(int(cx - 3), base_y - 15, 7, 15) & tower, C("wood_base"))
    cv.blank(cv.rect(int(cx - 3), base_y - 2, 5, 3) & tower, C("wood_lit"))

    # 帽子
    cap = cv.poly([(cx, top_y - 14), (cx + 12, top_y + 3), (cx - 12, top_y + 3)])
    cv.blank(dilate(cap, 1) & ~cap, C("line"))
    cv.blank(cap, C("slate_base"))
    cv.blank(shift(cap, -2, -1) & cap, C("slate_lit"))
    cv.blank(rim(cap, 1, 1), C("slate_deep"))
    cv.blank(cv.rect(int(cx - 2), top_y - 1, 5, 4), C("wood_deep"))  # 轴

    # 扇叶：先画一片朝右的，再整体旋转 90° 复制成四片
    SZ = 88
    C0 = SZ / 2.0
    leaf = Canvas(SZ, SZ)
    blade = np.zeros((SZ, SZ), bool)
    for x in range(6, 40):
        t = (x - 6) / 33.0
        hw = 2.0 + 6.5 * t                      # 近轴窄、叶尖宽
        blade |= leaf.rect(int(C0) + x, int(C0 - hw), 1, int(hw * 2))
    # 帆格
    for x in range(9, 40, 5):
        t = (x - 6) / 33.0
        hw = 2.0 + 6.5 * t
        blade |= leaf.rect(int(C0) + x, int(C0 - hw), 1, int(hw * 2))
    leaf.blank(dilate(blade, 1) & ~blade, C("line"))
    leaf.blank(blade, C("wood_dark"))
    leaf.blank(rim(blade, 0, -1), C("wood_base"))
    leaf.blank(rim(blade, 0, 1), C("wood_deep"))
    hub = leaf.circle(C0, C0, 5.0)
    leaf.blank(dilate(hub, 1) & ~hub, C("line"))
    leaf.blank(hub, C("rock_dark"))
    leaf.blank(rim(hub, -1, -1), C("rock_lit"))
    leaf.blank(leaf.circle(C0, C0, 2.0), C("wood_deep"))

    B = Canvas(SZ, SZ)
    one = leaf.out()
    for k in range(4):
        rot = np.array(one.rotate(-90 * k, resample=Image.NEAREST, center=(C0, C0)))
        m = rot[:, :, 3] > 0
        B.px[m] = rot[m]
    return cv, B


# ==================================================================== 道具


def make_well(seed: int) -> Canvas:
    W, H = 30, 38
    cv = Canvas(W, H)
    base = H - 2
    body = cv.ellipse(W / 2, base - 8, 12, 8)
    body |= cv.rect(3, base - 8, W - 6, 8)
    cv.blank(dilate(body, 1) & ~body, C("line"))
    cv.blank(body, C("rock_base"))
    cv.blank(rim(body, -1, 0), C("rock_lit"))
    cv.blank(rim(body, 1, 0) | cv.rect(3, base - 3, W - 6, 3), C("rock_dark"))
    cv.blank(cv.ellipse(W / 2, base - 8, 9, 5), C("wood_deep"))
    cv.blank(cv.ellipse(W / 2, base - 9, 8, 4), C("water_deep"))
    cv.blank(cv.ellipse(W / 2 - 2, base - 10, 3, 1.5), C("water_lit"))
    for px in (5, W - 7):
        cv.blank(cv.rect(px, 8, 2, base - 16), C("wood_dark"))
        cv.blank(cv.rect(px, 8, 1, base - 16), C("wood_lit"))
    roof = cv.poly([(2, 8), (W - 2, 8), (W / 2, 0)])
    cv.blank(dilate(roof, 1) & ~roof, C("line"))
    cv.blank(roof, C("thatch_base"))
    cv.blank(shift(roof, -1, -1) & roof, C("thatch_lit"))
    cv.blank(rim(roof, 0, 1), C("thatch_deep"))
    cv.blank(cv.rect(6, 10, W - 12, 2), C("wood_deep"))
    return cv


def make_lamp(seed: int) -> Canvas:
    W, H = 16, 46
    cv = Canvas(W, H)
    base = H - 2
    cv.blank(cv.rect(W // 2 - 1, 12, 3, base - 12), C("wood_dark"))
    cv.blank(cv.rect(W // 2 - 1, 12, 1, base - 12), C("wood_lit"))
    cv.blank(cv.rect(W // 2 - 3, base - 3, 7, 3), C("rock_dark"))
    head = cv.rect(W // 2 - 4, 4, 9, 10)
    cv.blank(dilate(head, 1) & ~head, C("line"))
    cv.blank(head, C("wood_deep"))
    glass = cv.rect(W // 2 - 3, 5, 7, 8)
    cv.blank(glass, C("lamp_warm"))
    cv.blank(rim(glass, -1, -1), (255, 244, 210, 255))
    cv.blank(cv.rect(W // 2 - 4, 3, 9, 2), C("rock_dark"))
    return cv


def make_fence_h(seed: int) -> Canvas:
    W, H = 20, 20
    cv = Canvas(W, H)
    base = H - 2
    m = np.zeros((H, W), bool)
    for x in (2, W - 4):
        m |= cv.rect(x, base - 14, 2, 14)
    m |= cv.rect(0, base - 11, W, 2)
    m |= cv.rect(0, base - 5, W, 2)
    cv.blank(dilate(m, 1) & ~m, C("line"))
    cv.blank(m, C("wood_base"))
    cv.blank(rim(m, 0, -1), C("wood_lit"))
    cv.blank(rim(m, 0, 1), C("wood_dark"))
    return cv


def make_fence_v(seed: int) -> Canvas:
    W, H = 14, 16
    cv = Canvas(W, H)
    base = H - 1
    m = cv.rect(W // 2 - 3, 2, 2, base - 2) | cv.rect(W // 2 + 1, 2, 2, base - 2)
    m |= cv.rect(1, 5, W - 2, 2) | cv.rect(1, 10, W - 2, 2)
    cv.blank(dilate(m, 1) & ~m, C("line"))
    cv.blank(m, C("wood_dark"))
    cv.blank(rim(m, -1, 0), C("wood_base"))
    return cv


def make_barrel(seed: int) -> Canvas:
    W, H = 16, 22
    cv = Canvas(W, H)
    base = H - 2
    m = cv.rect(2, 3, W - 4, base - 3) | cv.ellipse(W / 2, base - 1, (W - 4) / 2, 2.5) \
        | cv.ellipse(W / 2, 3, (W - 4) / 2, 2.5)
    cv.blank(dilate(m, 1) & ~m, C("line"))
    cv.blank(m, C("wood_base"))
    cv.blank(rim(m, -1, 0), C("wood_lit"))
    cv.blank(rim(m, 1, 0), C("wood_dark"))
    cv.blank(cv.rect(1, 6, W - 2, 2) & m, C("rock_dark"))
    cv.blank(cv.rect(1, base - 6, W - 2, 2) & m, C("rock_dark"))
    return cv


def make_crate(seed: int) -> Canvas:
    W, H = 18, 18
    cv = Canvas(W, H)
    m = cv.rect(1, 2, W - 2, H - 4) | cv.poly([(1, 2), (W - 1, 2), (W - 4, 0), (4, 0)])
    cv.blank(dilate(m, 1) & ~m, C("line"))
    cv.blank(m, C("wood_base"))
    cv.blank(rim(m, -1, -1), C("wood_lit"))
    cv.blank(rim(m, 1, 1), C("wood_deep"))
    cv.blank(cv.rect(1, H // 2, W - 2, 2) & m, C("wood_dark"))
    return cv


def make_haystack(seed: int) -> Canvas:
    W, H = 32, 26
    cv = Canvas(W, H)
    m = cv.poly([(3, H - 2), (W - 3, H - 2), (W / 2 + 3, 3), (W / 2 - 3, 3)])
    cv.blank(dilate(m, 1) & ~m, C("line"))
    cv.blank(m, C("thatch_base"))
    cv.blank(rim(m, -1, -1), C("thatch_lit"))
    cv.blank(rim(m, 1, 1), C("thatch_dark"))
    for i in range(5):
        y = 5 + i * 4
        cv.blank(cv.rect(0, y, W, 1) & m, C("thatch_deep"))
    return cv


def make_signpost(seed: int) -> Canvas:
    W, H = 18, 30
    cv = Canvas(W, H)
    base = H - 2
    cv.blank(cv.rect(W // 2 - 1, 8, 3, base - 8), C("wood_dark"))
    cv.blank(cv.rect(W // 2 - 1, 8, 1, base - 8), C("wood_lit"))
    board = cv.rect(2, 3, W - 4, 9)
    cv.blank(dilate(board, 1) & ~board, C("line"))
    cv.blank(board, C("wood_base"))
    cv.blank(rim(board, -1, -1), C("wood_lit"))
    cv.blank(cv.rect(4, 6, W - 9, 1), C("wood_deep"))
    cv.blank(cv.rect(4, 9, W - 11, 1), C("wood_deep"))
    return cv


def make_torii(seed: int) -> Canvas:
    W, H = 46, 44
    cv = Canvas(W, H)
    m = cv.rect(6, 14, 4, H - 16) | cv.rect(W - 10, 14, 4, H - 16)
    m |= cv.rect(1, 12, W - 2, 4)
    m |= cv.rect(4, 19, W - 8, 3)
    m |= cv.rect(2, 6, W - 4, 5)
    m |= cv.rect(0, 4, W, 3)
    cv.blank(dilate(m, 1) & ~m, C("line"))
    cv.blank(m, C("cloth_red"))
    cv.blank(rim(m, 0, -1), (206, 96, 78, 255))
    cv.blank(rim(m, 0, 1), (120, 40, 36, 255))
    return cv


def make_flowers(seed: int, tint: str) -> Canvas:
    W, H = 16, 14
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    pal = {"pink": ((232, 150, 176), (204, 106, 140)),
           "white": ((244, 240, 226), (206, 200, 182)),
           "yellow": ((246, 218, 116), (214, 176, 74)),
           "blue": ((150, 176, 232), (108, 134, 200))}[tint]
    for _ in range(int(rng.integers(3, 6))):
        x = int(rng.integers(2, W - 2))
        y = int(rng.integers(3, H - 2))
        cv.blank(cv.rect(x, y + 1, 1, H - 2 - y), (86, 132, 62, 255))
        cv.blank(cv.circle(x + 0.5, y, 1.6), (*pal[1], 255))
        cv.blank(cv.circle(x + 0.5, y - 0.4, 1.0), (*pal[0], 255))
    return cv


def make_tuft(seed: int) -> Canvas:
    W, H = 14, 12
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    for _ in range(int(rng.integers(3, 7))):
        x = int(rng.integers(1, W - 1))
        hgt = int(rng.integers(4, 9))
        lean = int(rng.integers(-1, 2))
        for i in range(hgt):
            yy = H - 1 - i
            xx = x + int(round(lean * i / max(hgt - 1, 1)))
            cv.blank(cv.rect(xx, yy, 1, 1), (74, 116, 54, 255) if i < hgt - 2 else (104, 148, 74, 255))
    return cv


def make_stump(seed: int) -> Canvas:
    W, H = 16, 14
    cv = Canvas(W, H)
    base = H - 2
    m = cv.rect(3, 5, W - 6, base - 5) | cv.ellipse(W / 2, 5, (W - 6) / 2, 3.2)
    cv.blank(dilate(m, 1) & ~m, C("line"))
    cv.blank(m, C("wood_dark"))
    cv.blank(rim(m, -1, 0), C("wood_base"))
    top = cv.ellipse(W / 2, 5, (W - 8) / 2, 2.2)
    cv.blank(top, C("wood_lit"))
    cv.blank(cv.ellipse(W / 2, 5, (W - 10) / 2, 1.2), C("wood_base"))
    return cv


def make_reeds(seed: int) -> Canvas:
    """水边苇丛：细秆高低不一，梢头带穗。"""
    W, H = 20, 26
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    for _ in range(int(rng.integers(7, 12))):
        x = int(rng.integers(2, W - 2))
        hgt = int(rng.integers(12, 22))
        lean = int(rng.integers(-2, 3))
        for i in range(hgt):
            yy = H - 2 - i
            xx = x + int(round(lean * i / max(hgt - 1, 1)))
            t = i / max(hgt - 1, 1)
            col = (86, 118, 58, 255) if t < 0.55 else (128, 152, 76, 255)
            cv.blank(cv.rect(xx, yy, 1, 1), col)
        tipx = x + lean
        cv.blank(cv.rect(tipx, H - 2 - hgt, 2, 4), (168, 146, 88, 255))
    return cv


def make_dock(seed: int) -> Canvas:
    """木栈桥：横铺的板子，右端伸进水里，底下几根桩。"""
    W, H = 48, 22
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    top = 6
    for i in range(6):
        y = top + i * 2
        col = C("wood_base") if i % 2 == 0 else C("wood_lit")
        cv.blank(cv.rect(1, y, W - 2, 2), col)
        cv.blank(cv.rect(1, y + 1, W - 2, 1), C("wood_dark"))
    cv.blank(cv.rect(1, top, W - 2, 1), C("wood_hi"))
    cv.blank(cv.rect(1, top + 11, W - 2, 1), C("wood_deep"))
    for x in (3, W - 6, W // 2):
        cv.blank(cv.rect(x, top + 12, 2, H - top - 13), C("wood_dark"))
    return cv


def make_boat(seed: int) -> Canvas:
    """小划艇，侧视：船体弧线 + 一支桨。"""
    W, H = 30, 16
    cv = Canvas(W, H)
    hull = cv.ellipse(W / 2, H - 1, W / 2 - 1, 7.0) & cv.rect(0, H - 9, W, 9)
    cv.blank(hull, C("wood_dark"))
    cv.blank(rim(hull, -1, -1), C("wood_base"))
    inner = hull & cv.rect(2, H - 8, W - 4, 4)
    cv.blank(inner & cv.rect(3, H - 8, W - 6, 2), C("wood_lit"))
    cv.blank(cv.rect(W - 12, 0, 2, H - 7), C("wood_base"))
    cv.blank(cv.rect(W - 18, 1, 8, 2), C("wood_lit"))
    return cv


def make_crop(seed: int, pal: tuple[str, str]) -> Canvas:
    W, H = 16, 20
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    for x in (4, 11):
        hgt = int(rng.integers(12, 17))
        cv.blank(cv.rect(x, H - 2 - hgt, 1, hgt), (100, 128, 60, 255))
        cv.blank(cv.rect(x, H - 2 - hgt, 3, 5), C(pal[0]))
        cv.blank(cv.rect(x, H - 3 - hgt, 4, 3), C(pal[1]))
    return cv


def make_stone_wall(seed: int) -> Canvas:
    W, H = 16, 18
    cv = Canvas(W, H)
    m = cv.rect(0, 4, W, H - 4)
    cv.blank(dilate(m, 1) & ~m, C("line"))
    cv.blank(m, C("rock_dark"))
    rng = np.random.default_rng(seed)
    for row in range(4):
        y = 5 + row * 4
        off = (row % 2) * 4
        for x in range(-4 + off, W, 8):
            bw = int(rng.integers(6, 8))
            b = cv.rect(x, y, bw, 3) & m
            cv.blank(b, C("rock_base"))
            cv.blank(rim(b, 0, -1), C("rock_lit"))
            cv.blank(rim(b, 0, 1), C("rock_deep"))
    return cv


def make_hanging_sign(seed: int) -> Canvas:
    W, H = 18, 30
    cv = Canvas(W, H)
    cv.blank(cv.rect(W // 2 - 1, 0, 2, 16), C("wood_dark"))
    board = cv.rect(1, 12, W - 2, 14)
    cv.blank(dilate(board, 1) & ~board, C("line"))
    cv.blank(board, C("wood_base"))
    cv.blank(rim(board, -1, -1), C("wood_lit"))
    cv.blank(cv.rect(3, 16, W - 6, 2), C("cloth_blue"))
    cv.blank(cv.rect(3, 20, W - 8, 2), C("cloth_red"))
    return cv


# ==================================================================== 角色


def make_character() -> None:
    """从免费角色包裁出 4 向行走条带，统一锚点对齐（脚底 + 水平中心）。"""
    sheet = Image.open(CHAR_SHEET).convert("RGBA")
    rows = {"down": 10, "side": 8, "up": 9}
    COLS = 6

    # 先求所有用到帧的联合包围盒，保证各方向共用同一裁剪框
    boxes = []
    for r in rows.values():
        for c in range(COLS):
            f = sheet.crop((c * 64, r * 64, c * 64 + 64, r * 64 + 64))
            a = np.array(f)
            ys, xs = np.nonzero(a[:, :, 3] > 8)
            if len(xs):
                boxes.append((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    x0 = int(min(b[0] for b in boxes))
    x1 = int(max(b[2] for b in boxes))
    y1 = int(max(b[3] for b in boxes))          # 所有帧的脚底取最深那帧
    y0 = y1 - 32                                  # 固定 32px 高，脚底对齐
    x0 -= 2
    x1 += 2
    w, h = x1 - x0, y1 - y0
    print(f"角色裁剪框 {w}x{h}  (x {x0}..{x1}, y {y0}..{y1})")

    os.makedirs(OUT_CHAR, exist_ok=True)
    for name, r in rows.items():
        strip = Image.new("RGBA", (w * COLS, h), (0, 0, 0, 0))
        for c in range(COLS):
            f = sheet.crop((c * 64 + x0, r * 64 + y0, c * 64 + x1, r * 64 + y1))
            strip.paste(f, (c * w, 0))
        strip.save(os.path.join(OUT_CHAR, f"hero_{name}.png"))
    # 待机：取行走循环里最中正的一帧，另外复制一帧做呼吸用
    for name, r in rows.items():
        src = Image.open(os.path.join(OUT_CHAR, f"hero_{name}.png"))
        best = None
        for c in range(COLS):
            f = src.crop((c * w, 0, (c + 1) * w, h))
            a = np.array(f)
            ys, xs = np.nonzero(a[:, :, 3] > 8)
            spread = xs.max() - xs.min()
            if best is None or spread < best[0]:
                best = (spread, c)
        c = best[1]
        idle = Image.new("RGBA", (w * 2, h), (0, 0, 0, 0))
        f = src.crop((c * w, 0, (c + 1) * w, h))
        idle.paste(f, (0, 0))
        idle.paste(Image.fromarray(np.roll(np.array(f), 1, axis=0)), (w, 0))
        idle.save(os.path.join(OUT_CHAR, f"hero_idle_{name}.png"))
    print("角色条带已输出:", ", ".join(sorted(os.listdir(OUT_CHAR))))


# ==================================================================== main


def main() -> None:
    os.makedirs(OUT_WORLD, exist_ok=True)
    a = Atlas()

    # --- 树
    a.add("tree_oak_a", tree_broadleaf(1, 1.10).out(), 32, 75)
    a.add("tree_oak_b", tree_broadleaf(2, 1.34, DARKLEAF).out(), 39, 91)
    a.add("tree_oak_c", tree_broadleaf(3, 0.92).out(), 27, 63)
    a.add("tree_aut_a", tree_broadleaf(4, 1.16, AUTUMN).out(), 34, 79)
    a.add("tree_aut_b", tree_broadleaf(5, 0.98, AUTUMN).out(), 28, 68)
    a.add("tree_pine_a", tree_pine(11, 1.00).out(), 22, 82)
    a.add("tree_pine_b", tree_pine(12, 1.22).out(), 27, 100)
    a.add("tree_pine_c", tree_pine(13, 0.82).out(), 18, 68)
    a.add("bush_a", bush(21).out(), 13, 20)
    a.add("bush_b", bush(22, DARKLEAF).out(), 13, 20)
    a.add("bush_aut", bush(23, AUTUMN).out(), 13, 20)
    a.add("rock_a", rock(31, 1.0).out(), 12, 16)
    a.add("rock_b", rock(32, 1.5).out(), 18, 24)
    a.add("stump", make_stump(41).out(), 8, 12)

    # --- 建筑
    a.add("house_red", make_house(66, 76, "roof", 51).out(), 33, 74)
    a.add("house_slate", make_house(58, 68, "slate", 52, door_offset=-0.06).out(), 29, 66)
    a.add("house_thatch", make_house(74, 72, "thatch", 53, windows=3).out(), 37, 70)
    a.add("house_small", make_house(46, 54, "roof", 54, windows=1).out(), 23, 52)
    a.add("barn", make_barn(55).out(), 46, 78)
    wm_tower, wm_blades = make_windmill(61)
    a.add("windmill_tower", wm_tower.out(), 26, 110)
    a.add("windmill_blades", wm_blades.out(), 44, 44)

    # --- 道具
    a.add("well", make_well(71).out(), 15, 36)
    a.add("lamp", make_lamp(72).out(), 8, 44)
    a.add("fence_h", make_fence_h(73).out(), 10, 18)
    a.add("fence_v", make_fence_v(74).out(), 7, 14)
    a.add("barrel", make_barrel(75).out(), 8, 20)
    a.add("crate", make_crate(76).out(), 9, 17)
    a.add("haystack", make_haystack(77).out(), 16, 24)
    a.add("signpost", make_signpost(78).out(), 9, 28)
    a.add("torii", make_torii(79).out(), 23, 42)
    a.add("stone_wall", make_stone_wall(80).out(), 8, 16)
    a.add("hanging_sign", make_hanging_sign(81).out(), 9, 28)
    for i, tint in enumerate(("pink", "white", "yellow", "blue")):
        a.add(f"flowers_{tint}", make_flowers(90 + i, tint).out(), 8, 13)
    a.add("tuft_a", make_tuft(95).out(), 7, 11)
    a.add("tuft_b", make_tuft(96).out(), 7, 11)
    a.add("crop_wheat", make_crop(97, ("thatch_lit", "thatch_hi")).out(), 8, 18)
    a.add("crop_green", make_crop(98, ("leaf_base", "leaf_lit")).out(), 8, 18)
    a.add("reeds", make_reeds(101).out(), 10, 24)
    a.add("dock", make_dock(102).out(), 24, 14)
    a.add("boat", make_boat(103).out(), 15, 12)

    a.save(os.path.join(OUT_WORLD, "objects"))
    make_character()


if __name__ == "__main__":
    main()
