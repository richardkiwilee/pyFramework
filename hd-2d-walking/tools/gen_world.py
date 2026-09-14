"""生成大世界：地形高度图 + 逐像素材质场 + 按行分带烘焙的地形贴图 + 物件摆放。

投影约定（斜俯视，相机倾角 ~53°）:
    屏幕 y = row*16 - height*12        （越高越往上）
    深度 z = row*12 + height*16        （越大越靠近相机）
地面/崖壁全部逐像素生成，所以不会有平铺重复和"色块拼布"。

输出:
  assets/world/world.json        高度图 / 物件表 / 分带索引
  assets/world/terrain_XX.png    地形分带贴图
  tools/_scratch/world_preview.png  缩略俯视图（开发期肉眼检查）
"""
from __future__ import annotations

import json
import math
import os

import numpy as np
from PIL import Image

from pixelkit import dither_threshold, value_noise

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "world")
SCRATCH = os.path.join(ROOT, "tools", "_scratch")

TS = 16          # 每格像素
ELEV = 12        # 每级高差的屏幕位移
BAND_ROWS = 4    # 每条地形带包含的行数

WT = 192         # 世界宽（格）
HT = 108         # 世界高（格）
PW, PH = WT * TS, HT * TS

MAX_H = 3

# ---------------------------------------------------------------- 材质 id
M_GRASS, M_FOREST, M_DRY, M_DIRT, M_PATH, M_SOIL, M_SAND, M_WATER, M_ROCK = range(9)

# 调色板（与 pixelkit.PAL 保持一致，这里用 RGB 方便数组运算）
P = {
    "grass_deep": (54, 88, 46), "grass_dark": (70, 108, 54),
    "grass_base": (90, 132, 64), "grass_lit": (114, 158, 78),
    "grass_hi": (140, 182, 96),
    "dry_deep": (108, 110, 52), "dry_dark": (134, 136, 64),
    "dry_base": (160, 158, 80), "dry_lit": (186, 180, 98),
    "dirt_deep": (92, 68, 46), "dirt_dark": (118, 88, 58),
    "dirt_base": (148, 114, 74), "dirt_lit": (176, 140, 96),
    "rock_deep": (66, 60, 56), "rock_dark": (96, 88, 78),
    "rock_base": (128, 118, 104), "rock_lit": (158, 148, 130),
    "rock_hi": (186, 178, 160),
    "water_deep": (32, 74, 110), "water_dark": (46, 98, 138),
    "water_base": (62, 126, 164), "water_lit": (96, 166, 194),
    "water_shallow": (108, 176, 186), "water_glint": (188, 226, 232),
    "sand_base": (206, 188, 142), "sand_lit": (228, 212, 170),
    "sand_dark": (176, 154, 112),
    "soil_dark": (104, 74, 50), "soil_base": (126, 92, 60), "soil_lit": (150, 112, 74),
}
for k, v in list(P.items()):
    P[k] = np.array(v, np.float32)


def mixc(a, b, t) -> np.ndarray:
    t = np.asarray(t, np.float32)[..., None] if np.ndim(t) else t
    return a * (1.0 - t) + b * t


# ==================================================================== 高度图


def build_height() -> np.ndarray:
    """设计感的起伏：北面高原岭 + 东丘 + 西台地 + 几处小丘，中南部大片平原。"""
    x = np.arange(WT, dtype=np.float32)[None, :]
    r = np.arange(HT, dtype=np.float32)[:, None]

    n_big = value_noise(11, WT, HT, scale=26, octaves=3)
    n_mid = value_noise(12, WT, HT, scale=13, octaves=3)

    h = np.zeros((HT, WT), np.float32)

    # 北面高原：越靠北越高，边界用噪声打散，避免一条直线
    north = np.clip((30.0 - r + (n_big - 0.5) * 16.0) / 20.0, 0.0, 1.0)
    h += (north ** 1.15) * 3.4

    # 东侧丘陵群
    h += 2.6 * np.exp(-(((x - 152) ** 2) / 520.0 + ((r - 34) ** 2) / 340.0))
    h += 1.7 * np.exp(-(((x - 128) ** 2) / 240.0 + ((r - 66) ** 2) / 190.0))

    # 西侧台地
    h += 2.2 * np.exp(-(((x - 20) ** 2) / 430.0 + ((r - 46) ** 2) / 620.0))

    # 南部平原上的孤立小丘（可以走上去看风景）
    h += 1.6 * np.exp(-(((x - 58) ** 2) / 90.0 + ((r - 96) ** 2) / 60.0))
    h += 1.4 * np.exp(-(((x - 164) ** 2) / 120.0 + ((r - 96) ** 2) / 90.0))

    # 大尺度噪声让等高线自然
    h += (n_big - 0.5) * 1.5 + (n_mid - 0.5) * 0.7

    # --- 村庄所在地推平
    h = flatten(h, 28, 50, 66, 30)     # x0, y0, w, h
    # --- 农田区推平成缓坡
    h = flatten(h, 88, 42, 40, 26)
    # --- 湖畔
    h = flatten(h, 132, 68, 40, 26)

    h = np.clip(h, 0.0, float(MAX_H))
    return h


def flatten(h: np.ndarray, x0: int, y0: int, w: int, hh: int, factor: float = 0.86) -> np.ndarray:
    """把一块区域的起伏压平（向该区域均值靠拢），再平滑过渡到边缘。"""
    out = h.copy()
    sub = out[y0 : y0 + hh, x0 : x0 + w]
    target = float(np.median(sub))
    ramp = np.ones((hh, w), np.float32)
    edge = 5
    for i in range(edge):
        t = (i + 1) / (edge + 1)
        ramp[i, :] = t
        ramp[-1 - i, :] *= t
        ramp[:, i] *= t
        ramp[:, -1 - i] *= t
    sub[:] = sub * (1.0 - ramp * factor) + target * ramp * factor
    return out


def smooth_height(h: np.ndarray, passes: int = 1) -> np.ndarray:
    k = np.array([1.0, 2.0, 1.0], np.float32)
    k /= k.sum()
    for _ in range(passes):
        h = np.apply_along_axis(lambda m: np.convolve(m, k, mode="same"), 0, h)
        h = np.apply_along_axis(lambda m: np.convolve(m, k, mode="same"), 1, h)
    return h


# ==================================================================== 形状辅助


def new_field() -> np.ndarray:
    return np.zeros((PH, PW), np.float32)


def stamp_disc(f: np.ndarray, cx: float, cy: float, rx: float, ry: float,
               feather: float = 3.0):
    """在 (cx, cy)（像素坐标）盖一个椭圆 soft mask（0..1），只算包围盒。"""
    x0 = max(0, int(cx - rx - feather - 2))
    x1 = min(PW, int(cx + rx + feather + 2))
    y0 = max(0, int(cy - ry - feather - 2))
    y1 = min(PH, int(cy + ry + feather + 2))
    if x1 <= x0 or y1 <= y0:
        return np.zeros((1, 1), np.float32), (0, 0, 1, 1)
    yy, xx = np.mgrid[y0:y1, x0:x1]
    d = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    m = np.clip((1.0 - d) * (max(rx, ry) / max(feather, 0.5)), 0.0, 1.0)
    return np.clip(m, 0.0, 1.0), (x0, y0, x1, y1)


def stamp_capsule(f: np.ndarray, p0, p1, radius: float, feather: float = 2.5) -> None:
    """在两点之间画一条软胶囊（用于道路）。"""
    x0 = int(min(p0[0], p1[0]) - radius - feather - 2)
    x1 = int(max(p0[0], p1[0]) + radius + feather + 2)
    y0 = int(min(p0[1], p1[1]) - radius - feather - 2)
    y1 = int(max(p0[1], p1[1]) + radius + feather + 2)
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(PW, x1), min(PH, y1)
    if x1 <= x0 or y1 <= y0:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L2 = dx * dx + dy * dy
    if L2 < 1e-6:
        t = np.zeros_like(xx)
    else:
        t = np.clip(((xx - p0[0]) * dx + (yy - p0[1]) * dy) / L2, 0.0, 1.0)
    ex = xx - (p0[0] + t * dx)
    ey = yy - (p0[1] + t * dy)
    d = np.sqrt(ex * ex + ey * ey)
    m = np.clip((radius + feather - d) / max(feather, 0.5), 0.0, 1.0)
    np.maximum(f[y0:y1, x0:x1], m, out=f[y0:y1, x0:x1])


# ==================================================================== 世界布局

# 道路：一系列折线（格坐标）
ROADS: list[list[tuple[float, float]]] = [
    # 主路：南边草原 → 村庄 → 风车 → 北上高原神社
    [(96, 104), (92, 92), (80, 84), (66, 78), (54, 74), (46, 66), (44, 56), (52, 48),
     (64, 42), (74, 34), (82, 26), (88, 16), (92, 8)],
    # 村庄支路 → 农田
    [(58, 68), (70, 66), (84, 62), (98, 58), (108, 52)],
    # 湖岸小路
    [(96, 104), (114, 96), (130, 88), (138, 79), (141, 73)],
    # 西侧台地小路
    [(44, 56), (36, 62), (26, 62), (18, 56)],
    # 村中横街（串联村舍）
    [(36, 63), (44, 62), (52, 62), (60, 64), (68, 64)],
    # 村南巷子
    [(46, 74), (44, 70), (44, 63)],
]

LAKE = (150.0, 80.0, 15.0, 9.0)        # 格坐标 (cx, cy, rx, ry)

# 阔叶林片区（格坐标 cx, cy, 半径, 高度上限）
GROVES = [
    (28, 90, 15, 2.0), (58, 98, 13, 2.0), (152, 100, 15, 2.0),
    (176, 64, 12, 2.0), (14, 100, 12, 2.0), (108, 92, 14, 2.0),
    (78, 8, 14, 4.0), (152, 12, 13, 4.0), (34, 26, 16, 4.0),
]
# 北岭针叶林（格坐标 x0, y0, w, h）
PINE_FOREST = (0, 0, WT, 30)

# 农田矩形（格坐标 x, y, w, h）
FARMS = [
    (92, 48, 12, 8), (106, 48, 11, 8),
    (92, 58, 12, 7), (106, 58, 11, 7),
    (92, 66, 12, 6),
]


def road_field() -> np.ndarray:
    f = new_field()
    for path in ROADS:
        pts = [(p[0] * TS + TS / 2, p[1] * TS + TS / 2) for p in path]
        for i in range(len(pts) - 1):
            stamp_capsule(f, pts[i], pts[i + 1], 11.0, 5.0)
    return f


def farm_field() -> np.ndarray:
    f = new_field()
    for (fx, fy, fw, fh) in FARMS:
        f[fy * TS : (fy + fh) * TS, fx * TS : (fx + fw) * TS] = 1.0
    return f


def lake_field() -> np.ndarray:
    cx, cy, rx, ry = LAKE
    m, box = stamp_disc(new_field(), cx * TS, cy * TS, rx * TS, ry * TS, feather=TS * 1.6)
    f = new_field()
    x0, y0, x1, y1 = box
    f[y0:y1, x0:x1] = m
    return f


def forest_field() -> np.ndarray:
    """只在真正有树的片区铺林地色 —— 而不是"高地一律深绿"。"""
    f = new_field()
    x0, y0, w, h = PINE_FOREST
    f[y0 * TS : (y0 + h) * TS, x0 * TS : (x0 + w) * TS] = 1.0
    for (gx, gy, gr, _gd) in GROVES:
        m, box = stamp_disc(new_field(), gx * TS, gy * TS, gr * TS, gr * TS * 0.82,
                            feather=TS * 3.0)
        bx0, by0, bx1, by1 = box
        np.maximum(f[by0:by1, bx0:bx1], m * 0.85, out=f[by0:by1, bx0:bx1])
    # 打散边缘，免得看到清晰的椭圆轮廓
    n = value_noise(25, PW, PH, scale=34, octaves=3)
    return np.clip((f - 0.42) * 2.6 + (n - 0.5) * 0.9, 0.0, 1.0)


# ==================================================================== 材质与上色


def build_material(hmap: np.ndarray) -> tuple[np.ndarray, dict]:
    """逐像素决定材质 id，并回传若干连续场供上色用。"""
    n_fine = value_noise(21, PW, PH, scale=6, octaves=2)
    n_spec = value_noise(22, PW, PH, scale=3, octaves=2)
    n_big = value_noise(23, PW, PH, scale=110, octaves=3)
    n_patch = value_noise(24, PW, PH, scale=54, octaves=2)

    # 丘陵/高地 → 林地色；东南 → 干燥色
    hpx = np.repeat(np.repeat(hmap, TS, axis=0), TS, axis=1)

    road = road_field()
    farm = farm_field()
    lake = lake_field()
    forest = forest_field()

    # 干草：东南方向，用大尺度噪声把分界线打得七零八落
    xx = np.arange(PW, dtype=np.float32)[None, :] / PW
    yy = np.arange(PH, dtype=np.float32)[:, None] / PH
    n_biome = value_noise(26, PW, PH, scale=150, octaves=3)
    dry = np.clip((xx * 0.50 + yy * 0.80 - 0.70) * 1.9
                  + (n_biome - 0.5) * 3.6 + (n_patch - 0.5) * 1.4, 0.0, 1.0)
    # 裸岩：陡坡（与北邻高差大）
    dh_n = np.zeros_like(hpx)
    dh_n[TS:, :] = np.abs(hpx[TS:, :] - hpx[:-TS, :])
    rock = np.clip((dh_n - 0.05) * 2.2, 0.0, 1.0) * np.clip(n_spec * 2.0, 0.0, 1.0)

    weights = np.stack([
        1.0 - forest - dry * 0.6,                    # M_GRASS
        forest,                                      # M_FOREST
        dry,                                         # M_DRY
        np.zeros_like(hpx),                          # M_DIRT（下面单独给）
        road * 1.35,                                 # M_PATH
        farm * 1.25,                                 # M_SOIL
        np.clip((lake - 0.35) * 2.4, 0.0, 1.0) * 0.0,  # M_SAND 先占位
        np.clip((lake - 0.62) * 3.0, 0.0, 1.0),      # M_WATER
        rock * 0.9,                                  # M_ROCK
    ], axis=0)

    # 沙：只在水陆交界那一圈。上界必须压在水线以下，
    # 否则沙子权重会一直伸进湖心，把水面顶掉，湖就成了"沙坑里的一滩蓝"。
    shore = np.clip((lake - 0.34) * 3.0, 0.0, 1.0) * np.clip((0.74 - lake) * 5.0, 0.0, 1.0)
    weights[M_SAND] = shore * 1.5

    # 泥土：路缘、农田边缘
    weights[M_DIRT] = np.clip((road - 0.25) * 1.2, 0.0, 1.0) * 0.0 + \
        np.clip((farm - 0.35) * 1.4, 0.0, 1.0) * 0.0

    # 每种材质叠一点高频噪声，让边界自然抖动而不是硬边
    jitter = (n_fine - 0.5) * 0.85
    for i in range(len(weights)):
        weights[i] = weights[i] + jitter * (0.5 if i in (M_PATH, M_SOIL) else 0.18)
    weights[M_SAND] += (n_spec - 0.5) * 0.25
    weights[M_GRASS] += (n_fine - 0.5) * 0.20
    weights[M_DIRT] = np.clip(weights[M_DIRT], 0, None)
    weights[M_ROCK] += (n_spec - 0.5) * 0.2

    mat = np.argmax(weights, axis=0).astype(np.uint8)
    return mat, {"n_fine": n_fine, "n_spec": n_spec, "n_big": n_big,
                 "n_patch": n_patch, "hpx": hpx, "lake": lake}


def colorize(mat: np.ndarray, f: dict) -> np.ndarray:
    """把材质 id 变成逐像素颜色。每种材质都带细颗粒 + 大尺度色斑。"""
    nf, ns, nb, np_ = f["n_fine"], f["n_spec"], f["n_big"], f["n_patch"]
    hpx = f["hpx"]
    out = np.zeros((PH, PW, 3), np.float32)

    # 像素级碎细节：细噪声阈值化后变成 1~3px 的小丛，比逐像素白噪声更像草叶
    det_lit = value_noise(27, PW, PH, scale=2, octaves=1)
    det_dark = value_noise(28, PW, PH, scale=2, octaves=1)
    blades_lit = det_lit > 0.74
    blades_dark = det_dark < 0.26

    def mk(dark, base, lit, deep, hi, speck=0.0):
        c = mixc(P[dark], P[base], np.clip(nf * 1.5 - 0.25, 0, 1))
        c = mixc(c, P[lit], np.clip((ns - 0.58) * 2.4, 0, 1))
        c = mixc(c, P[deep], np.clip((0.24 - nf) * 1.8, 0, 1) * 0.7)
        c = mixc(c, P[hi], np.clip((nb - 0.62) * 1.6, 0, 1) * 0.55)
        if speck:
            c[blades_lit] = P[lit] * (1.0 + 0.06 * speck) + P[hi] * 0.06 * speck
            c[blades_dark] = P[deep] * 0.92 + P[dark] * 0.08
        return c

    grass = mk("grass_dark", "grass_base", "grass_lit", "grass_deep", "grass_hi", 0.5)
    forest = mk("grass_deep", "grass_dark", "grass_base", "grass_deep", "grass_lit", 0.3)
    dry = mk("dry_dark", "dry_base", "dry_lit", "dry_deep", "dry_lit", 0.5)
    path = mk("dirt_deep", "dirt_base", "dirt_lit", "dirt_dark", "dirt_lit", 0.7)
    soil = mk("soil_dark", "soil_base", "soil_lit", "dirt_deep", "soil_lit", 0.35)
    sand = mk("sand_dark", "sand_base", "sand_lit", "sand_dark", "sand_lit", 0.5)
    rock = mk("rock_deep", "rock_base", "rock_lit", "rock_deep", "rock_hi", 0.4)

    # 水面不是一块蓝：靠岸浅、中间深，这是"有水深"的唯一视觉线索。
    # 深度用湖场本身（1 = 湖心），再叠噪声打散等深线。
    lake = f["lake"]
    depth = np.clip((lake - 0.62) / 0.30, 0.0, 1.0)
    depth = np.clip(depth + (nf - 0.5) * 0.55, 0.0, 1.0)
    water = mixc(P["water_shallow"], P["water_base"], np.clip(depth * 1.8, 0, 1))
    water = mixc(water, P["water_deep"], np.clip((depth - 0.45) * 2.0, 0, 1))
    water = mixc(water, P["water_dark"], np.clip((nb - 0.55) * 1.8, 0, 1) * 0.6)
    # 波纹：沿湖场等值线走的同心亮环，越靠岸越密。
    # 直接用 sin(湖场) 得到的是同心椭圆，正是水面该有的样子。
    ripple = np.sin(lake * 46.0 + nf * 5.0) * 0.5 + 0.5
    water = mixc(water, P["water_lit"], np.clip((ripple - 0.62) * 2.6, 0, 1) * depth * 0.55)
    # 碎光：高处才有的镜面点，压缩到湖心附近，像正午的反光
    glint = np.clip((ns - 0.80) * 5.0, 0, 1) * np.clip((depth - 0.5) * 2.0, 0, 1)
    water = mixc(water, P["water_glint"], glint * 0.7)

    table = {M_GRASS: grass, M_FOREST: forest, M_DRY: dry, M_DIRT: path,
             M_PATH: path, M_SOIL: soil, M_SAND: sand, M_WATER: water, M_ROCK: rock}
    for mid, col in table.items():
        m = mat == mid
        out[m] = col[m]

    # 高地受光更足、低洼略暗（静态整体明暗）
    lift = np.clip((hpx - 1.0) * 0.035, -0.05, 0.09)
    out *= (1.0 + lift)[..., None]
    # 大尺度明暗斑驳，消除"一整块平色"
    out *= (0.94 + (nb - 0.5) * 0.13)[..., None]
    return np.clip(out, 0, 255)


# ==================================================================== 分带烘焙


def build_ao(hmap: np.ndarray) -> np.ndarray:
    """每格的"被高处压住"程度 → 贴边阴影。"""
    ao = np.zeros((HT, WT), np.float32)
    for dy, dx, w in ((-1, 0, 1.0), (1, 0, 0.55), (0, -1, 0.5), (0, 1, 0.5),
                      (-1, -1, 0.4), (-1, 1, 0.4), (1, -1, 0.3), (1, 1, 0.3)):
        ys0, ys1 = max(0, dy), min(HT, HT + dy)
        xs0, xs1 = max(0, dx), min(WT, WT + dx)
        nb = hmap[ys0:ys1, xs0:xs1]
        me = hmap[ys0 - dy : ys1 - dy, xs0 - dx : xs1 - dx]
        ao[ys0 - dy : ys1 - dy, xs0 - dx : xs1 - dx] += np.clip(nb - me, 0, 3) * w
    return np.clip(ao * 0.10, 0.0, 0.30)


def bake_bands(rgb: np.ndarray, hmap: np.ndarray) -> list[dict]:
    """按行分带，把每格顶面 + 崖壁画进带内，返回带索引。"""
    os.makedirs(OUT, exist_ok=True)
    ao = build_ao(hmap)
    n_fine = value_noise(31, PW, PH, scale=8, octaves=2)
    n_str = value_noise(32, PW, PH, scale=5, octaves=2)

    bands: list[dict] = []
    nb = (HT + BAND_ROWS - 1) // BAND_ROWS
    for b in range(nb):
        r0 = b * BAND_ROWS
        r1 = min(HT, r0 + BAND_ROWS)
        # 该带内容的屏幕 y 范围
        hs = hmap[r0:r1, :]
        y_top = int(r0 * TS - ELEV * int(hs.max())) if r1 > r0 else r0 * TS
        hn = hmap[r1:r1 + 1, :]
        h_next = int(hn.min()) if hn.size else 0   # 用最小值，否则矮的那几列会被裁掉
        y_bot = r1 * TS - ELEV * h_next + TS
        y_top -= 2
        h_img = y_bot - y_top
        if h_img <= 0:
            continue

        canvas = np.zeros((h_img, PW, 3), np.float32)
        filled = np.zeros((h_img, PW), bool)

        for r in range(r0, r1):
            h_row = hmap[r]
            hn_row = hmap[r + 1] if r + 1 < HT else np.zeros(WT, np.int8)
            for x in range(WT):
                h = int(h_row[x])
                px = x * TS
                py = r * TS - h * ELEV - y_top
                if py < 0 or py + TS > h_img:
                    continue
                tile = rgb[r * TS : (r + 1) * TS, px : px + TS]
                # 贴边阴影（越靠近更高的邻居越暗）
                a = ao[r, x]
                if a > 0.001:
                    sh = np.ones((TS, TS), np.float32)
                    for dy, dx, w in ((-1, 0, 1.0), (0, -1, 0.7), (0, 1, 0.7), (1, 0, 0.4)):
                        ry, rx = r + dy, x + dx
                        if 0 <= ry < HT and 0 <= rx < WT and hmap[ry, rx] > h:
                            k = min(5, (hmap[ry, rx] - h) * 4 + 2)
                            if dy == -1:
                                sh[:k, :] *= 1.0 - a
                            elif dy == 1:
                                sh[-k:, :] *= 1.0 - a * 0.7
                            elif dx == -1:
                                sh[:, :k] *= 1.0 - a * 0.8
                            else:
                                sh[:, -k:] *= 1.0 - a * 0.8
                    tile = tile * sh[..., None]
                canvas[py : py + TS, px : px + TS] = tile
                filled[py : py + TS, px : px + TS] = True

                # --- 崖壁：从顶面下沿一直填到下一行地表
                wall_top = py + TS
                wall_bot = (r + 1) * TS - int(hn_row[x]) * ELEV - y_top
                wall_bot = min(h_img, max(wall_top, wall_bot))
                if wall_bot > wall_top:
                    hgt = wall_bot - wall_top
                    yy = np.arange(hgt, dtype=np.float32)[:, None]
                    xx = np.arange(TS, dtype=np.float32)[None, :, None]
                    stri = n_str[wall_top + y_top : wall_bot + y_top, px : px + TS]
                    # 岩体：横向层理，上亮下暗
                    base = mixc(P["rock_dark"], P["rock_base"],
                                np.clip(0.42 + stri * 0.85, 0, 1))
                    base = mixc(base, P["rock_lit"],
                                np.clip((stri - 0.62) * 1.8, 0, 1) * 0.8)
                    strata = value_noise(33 + r, PW, PH, scale=4, octaves=1)[
                        wall_top + y_top : wall_bot + y_top, px : px + TS]
                    base = base * (0.93 + 0.15 * (strata > 0.5))[..., None]
                    base *= (1.0 - 0.26 * (yy / max(hgt - 1, 1)))[..., None]
                    # 左右两端压暗，让崖壁有厚度
                    base *= (1.0 - 0.30 * np.clip(1.6 - xx / 2.2, 0, 1))
                    base *= (1.0 - 0.30 * np.clip(1.6 - (TS - 1 - xx) / 2.2, 0, 1))
                    # 顶部草檐（草皮从崖边垂下来，最亮的一线在最上）
                    lip = min(3, hgt)
                    if lip >= 1:
                        base[0] = mixc(P["grass_lit"], P["grass_base"], 0.35)
                    if lip >= 2:
                        base[1] = mixc(P["grass_base"], P["grass_dark"],
                                       0.3 + 0.5 * n_fine[wall_top + y_top + 1, px : px + TS])
                    if lip >= 3:
                        base[2] = mixc(P["grass_dark"], P["grass_deep"], 0.45)
                    if hgt > lip:                       # 草檐下的暗影线
                        base[lip] *= 0.58
                    if hgt > lip + 1:
                        base[lip + 1] *= 0.78
                    base[-1] *= 0.72                    # 接地暗
                    canvas[wall_top:wall_bot, px : px + TS] = base
                    filled[wall_top:wall_bot, px : px + TS] = True
                    # 崖顶边沿的一线亮边（草皮受光），让台阶边缘清晰
                    canvas[py + TS - 1, px : px + TS] = mixc(
                        P["grass_hi"], P["grass_lit"], 0.4)

        # 裁掉全空的边
        rows_any = filled.any(axis=1)
        if not rows_any.any():
            continue
        y0 = int(np.argmax(rows_any))
        y1 = int(len(rows_any) - np.argmax(rows_any[::-1]))
        rgba = np.dstack([
            np.clip(canvas[y0:y1], 0, 255).astype(np.uint8),
            (filled[y0:y1] * 255).astype(np.uint8),
        ])
        img = Image.fromarray(rgba, "RGBA")
        name = f"terrain_{b:02d}.png"
        img.save(os.path.join(OUT, name))
        bands.append({"file": name, "y": y_top + y0, "row": r0})

    return bands


# ==================================================================== 物件摆放


class Placer:
    def __init__(self, hmap: np.ndarray, mat: np.ndarray):
        self.h = hmap
        self.m = mat
        self.blocked = np.zeros((HT, WT), bool)   # 建筑/树占位
        self.objects: list[dict] = []
        # 水面 = 不可通行
        self.water = np.zeros((HT, WT), bool)
        for r in range(HT):
            for x in range(WT):
                sub = mat[r * TS : (r + 1) * TS, x * TS : (x + 1) * TS]
                if (sub == M_WATER).mean() > 0.4:
                    self.water[r, x] = True

    def free(self, x: int, y: int, rad: float = 1.0) -> bool:
        for dy in range(int(-rad), int(rad) + 1):
            for dx in range(int(-rad), int(rad) + 1):
                xx, yy = x + dx, y + dy
                if not (0 <= xx < WT and 0 <= yy < HT):
                    return False
                if self.blocked[yy, xx] or self.water[yy, xx]:
                    return False
        return True

    def near_road(self, x: int, y: int, dist: float = 2.5) -> bool:
        for path in ROADS:
            pts = path
            for i in range(len(pts) - 1):
                if _seg_dist(x, y, pts[i], pts[i + 1]) < dist:
                    return True
        return False

    def in_farm(self, x: int, y: int) -> bool:
        for (fx, fy, fw, fh) in FARMS:
            if fx <= x < fx + fw and fy <= y < fy + fh:
                return True
        return False

    def put(self, name: str, x: float, y: float, ox: float = 0.0, oy: float = 0.0,
            block: float = 0.0) -> None:
        tx, ty = int(x), int(y)
        if not (0 <= tx < WT and 0 <= ty < HT):
            return
        self.objects.append({"n": name, "x": round(float(x), 2), "y": round(float(y), 2),
                             "ox": round(float(ox), 2), "oy": round(float(oy), 2),
                             "h": int(self.h[ty, tx])})
        if block > 0:
            # 用 floor 而不是 ceil：树/桶这种 block≈0.9 的物件应该只占脚下 1 格。
            # ceil 会让它们占满 3x3，1500 棵树叠起来能把整张图封成迷宫。
            rad = int(block)
            for dy in range(-rad, rad + 1):
                for dx in range(-rad, rad + 1):
                    xx, yy = tx + dx, ty + dy
                    if 0 <= xx < WT and 0 <= yy < HT and dx * dx + dy * dy <= block * block + 0.4:
                        self.blocked[yy, xx] = True


def _walk_path(path, spacing: float):
    """沿折线等距取点，返回 (x, y, 单位方向dx, dy)。村庄宅基地就是靠它排出来的。"""
    out = []
    for i in range(len(path) - 1):
        ax, ay = path[i]
        bx, by = path[i + 1]
        seg = math.hypot(bx - ax, by - ay)
        if seg < 0.001:
            continue
        dx, dy = (bx - ax) / seg, (by - ay) / seg
        n = int(seg / spacing)
        for k in range(n):
            t = (k + 0.5) * spacing
            out.append((ax + dx * t, ay + dy * t, dx, dy))
    return out


def _seg_dist(px, py, a, b) -> float:
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def place_objects(hmap: np.ndarray, mat: np.ndarray) -> list[dict]:
    pl = Placer(hmap, mat)
    rng = np.random.default_rng(2027)

    # ---------------------------------------------------------- 村庄
    # 房子沿街两侧排：村子的"村"感来自"房子贴着路、彼此看得见"，
    # 而不是把几栋房子撒在一片草地上。所以先在路两侧量出宅基地，再逐个落屋。
    plots: list[tuple[float, float]] = []
    for path in ROADS[4:6] + [ROADS[0][3:7]]:
        for (px, py, dx, dy) in _walk_path(path, 7.5):
            for side in (-1.0, 1.0):
                nx = px - dy * side * 3.4
                ny = py + dx * side * 3.4
                if 30 < nx < 74 and 54 < ny < 78:
                    plots.append((nx, ny))
    rng.shuffle(plots)

    house_kinds = ["house_red", "house_slate", "house_thatch", "house_small",
                   "house_thatch", "house_red", "house_slate", "house_small"]
    placed = 0
    for (hx, hy) in plots:
        if placed >= 15:
            break
        spot = None
        for oy in (0, 1, -1, 2, -2, 3):
            for ox in (0, 1, -1, 2, -2, 3):
                cx, cy = int(hx) + ox, int(hy) + oy
                if pl.free(cx, cy, 2.6) and not pl.near_road(cx, cy, 2.6) and not pl.in_farm(cx, cy):
                    spot = (cx, cy)
                    break
            if spot:
                break
        if spot is None:
            continue
        kind = house_kinds[placed % len(house_kinds)]
        pl.put(kind, spot[0], spot[1], oy=1.0, block=2.6)
        placed += 1
        # 宅旁小园：篱笆围一格，里面种两株作物或一丛花
        gx, gy = spot[0] + int(rng.integers(-5, 6)), spot[1] + 3
        if pl.free(gx, gy, 1.4) and not pl.in_farm(gx, gy):
            for k in range(3):
                if pl.free(gx - 1 + k, gy - 1, 0):
                    pl.put("fence_h", gx - 1 + k, gy - 1)
            if pl.free(gx, gy, 0):
                pl.put(("flowers_yellow", "crop_green", "bush_a", "flowers_pink")
                       [int(rng.integers(0, 4))], gx, gy)

    # 村口风车（放在村北的小高地上）
    for (wx, wy) in ((72, 50), (70, 52), (74, 52), (68, 50)):
        if pl.free(wx, wy, 3):
            pl.put("windmill_tower", wx, wy, oy=2.0, block=3.0)
            pl.objects.append({"n": "windmill_blades", "x": wx, "y": wy,
                               "ox": 0.0, "oy": -78.0, "h": int(hmap[wy, wx]),
                               "spin": 1})
            break

    # 东路的终点是湖：给它一间渔屋和几条苇丛，路才不是断在草里
    pl.put("house_thatch", 137, 80, oy=1.0, block=2.6)
    pl.put("crate", 141, 76, block=0.8)
    pl.put("boat", 147, 76, block=0.0)
    pl.put("dock", 144, 74, block=0.0)
    for (rx, ry) in ((146, 69), (149, 71), (144, 70), (151, 74), (147, 86), (152, 84)):
        if pl.free(rx, ry, 0):
            pl.put("reeds", rx, ry, oy=float(rng.uniform(-3, 3)))

    # 水井、灯柱、告示牌、货箱
    pl.put("well", 46, 65, block=1.0)
    for (lx, ly) in ((40, 64), (52, 64), (40, 74), (56, 72), (66, 56),
                     (36, 61), (58, 63), (48, 69), (34, 68), (62, 68)):
        if pl.free(lx, ly, 0):
            pl.put("lamp", lx, ly, oy=2.0)
    pl.put("signpost", 62, 66)
    pl.put("barrel", 38, 62)
    pl.put("crate", 50, 70)
    pl.put("barrel", 51, 71)
    pl.put("barrel", 45, 66)
    pl.put("crate", 45, 67)

    # 村舍之间补树：村庄不该是光秃秃的草地
    for _ in range(700):
        x = int(rng.integers(30, 72))
        y = int(rng.integers(54, 80))
        if rng.random() > 0.20:
            continue
        if not pl.free(x, y, 1) or pl.near_road(x, y, 2.0) or pl.in_farm(x, y):
            continue
        if hmap[y, x] > 2:
            continue
        roll = rng.random()
        name = (("tree_oak_a", "tree_aut_a", "tree_oak_c", "tree_oak_b")
                [int(rng.integers(0, 4))] if roll < 0.55 else
                ("bush_a", "bush_aut", "flowers_white")[int(rng.integers(0, 3))])
        pl.put(name, x, y, ox=float(rng.uniform(-5, 5)),
               block=0.9 if "tree" in name else 0.0)

    # ---------------------------------------------------------- 农田
    for (fx, fy, fw, fh) in FARMS:
        for y in range(fy + 1, fy + fh - 1):
            for x in range(fx + 1, fx + fw - 1):
                if (x + y) % 2 == 0:
                    pl.put("crop_wheat" if (fy // 8) % 2 == 0 else "crop_green", x, y)
        for x in range(fx, fx + fw, 2):
            pl.put("fence_h", x, fy)
            pl.put("fence_h", x, fy + fh - 1)

    pl.put("barn", 118, 62, oy=1.0, block=3.0)
    pl.put("haystack", 122, 68)
    pl.put("haystack", 120, 70)
    pl.put("haystack", 124, 67)
    pl.put("crate", 114, 66)
    pl.put("lamp", 110, 60, oy=2.0)

    # ---------------------------------------------------------- 北岭神社
    shrine = None
    for r in range(6, 16):
        for x in range(84, 100):
            if pl.free(x, r, 2) and hmap[r, x] >= 2:
                shrine = (x, r)
                break
        if shrine:
            break
    if shrine:
        sx, sy = shrine
        pl.put("torii", sx, sy, oy=1.0, block=2.0)
        for x in range(sx - 5, sx + 6, 1):
            if pl.free(x, sy + 3, 0):
                pl.put("stone_wall", x, sy + 3)
        pl.put("lamp", sx - 4, sy + 4, oy=2.0)
        pl.put("lamp", sx + 4, sy + 4, oy=2.0)

    # ---------------------------------------------------------- 森林
    # 高地针叶林
    for _ in range(1500):
        x = int(rng.integers(0, WT))
        y = int(rng.integers(0, HT))
        if hmap[y, x] < 2:
            continue
        if not pl.free(x, y, 1) or pl.near_road(x, y, 2.6) or pl.in_farm(x, y):
            continue
        if rng.random() > 0.45:
            continue
        name = ("tree_pine_a", "tree_pine_b", "tree_pine_c")[int(rng.integers(0, 3))]
        pl.put(name, x, y, ox=float(rng.uniform(-5, 5)), block=0.9)

    # 低地阔叶林（成片）
    for (gx, gy, gr, gd) in GROVES:
        for _ in range(int(gr * gr * 1.5)):
            a = rng.uniform(0, math.tau)
            d = math.sqrt(rng.uniform(0, 1)) * gr
            x = int(gx + math.cos(a) * d)
            y = int(gy + math.sin(a) * d * 0.8)
            if not (0 <= x < WT and 0 <= y < HT):
                continue
            if not pl.free(x, y, 1) or pl.near_road(x, y, 2.4) or pl.in_farm(x, y):
                continue
            if hmap[y, x] > gd:
                continue
            roll = rng.random()
            if roll < 0.62:
                name = ("tree_oak_a", "tree_oak_b", "tree_oak_c")[int(rng.integers(0, 3))]
            elif roll < 0.78:
                name = ("tree_aut_a", "tree_aut_b")[int(rng.integers(0, 2))]
            elif roll < 0.86:
                name = "stump"
            else:
                name = ("bush_a", "bush_b", "bush_aut")[int(rng.integers(0, 3))]
            pl.put(name, x, y, ox=float(rng.uniform(-5, 5)), block=0.9 if "tree" in name else 0.0)

    # 平原上零散大树
    for _ in range(900):
        x = int(rng.integers(0, WT))
        y = int(rng.integers(40, HT))
        if rng.random() > 0.16:
            continue
        if not pl.free(x, y, 1) or pl.near_road(x, y, 2.2) or pl.in_farm(x, y):
            continue
        if hmap[y, x] > 2:
            continue
        name = ("tree_oak_a", "tree_aut_a", "tree_oak_c")[int(rng.integers(0, 3))]
        pl.put(name, x, y, ox=float(rng.uniform(-5, 5)), block=0.9)

    # 点缀物：按噪声场成簇分布 —— 花是一丛一丛的，石头聚在山脚，不是满地撒胡椒面
    n_flower = value_noise(41, WT, HT, scale=7, octaves=2)
    n_rock = value_noise(42, WT, HT, scale=9, octaves=2)
    n_bush = value_noise(43, WT, HT, scale=11, octaves=2)
    for _ in range(4200):
        x = int(rng.integers(0, WT))
        y = int(rng.integers(0, HT))
        if not pl.free(x, y, 0) or pl.in_farm(x, y) or pl.water[y, x]:
            continue
        if pl.near_road(x, y, 1.1):
            continue
        p_flo = max(0.0, n_flower[y, x] - 0.58) * 2.0
        p_rk = max(0.0, n_rock[y, x] - 0.66) * 2.2
        p_bu = max(0.0, n_bush[y, x] - 0.62) * 1.8
        roll = float(rng.random())
        if roll < p_flo:
            pl.put(("flowers_pink", "flowers_white", "flowers_yellow", "flowers_blue")
                   [int(rng.integers(0, 4))], x, y)
        elif roll < p_flo + p_rk:
            pl.put(("rock_a", "rock_b", "rock_b")[int(rng.integers(0, 3))], x, y)
        elif roll < p_flo + p_rk + p_bu:
            pl.put(("bush_a", "bush_b", "bush_aut")[int(rng.integers(0, 3))], x, y)
        elif roll < p_flo + p_rk + p_bu + 0.035:
            pl.put("tuft_" + ("a" if rng.random() < 0.5 else "b"), x, y)
        elif roll < p_flo + p_rk + p_bu + 0.042:
            pl.put("stump", x, y)
    return pl


# ==================================================================== 预览图


def save_preview(hmap: np.ndarray, rgb: np.ndarray, objects: list[dict]) -> None:
    os.makedirs(SCRATCH, exist_ok=True)
    small = np.array(Image.fromarray(rgb.astype(np.uint8)).resize((WT, HT), Image.BOX),
                     np.float32)
    # 高度以明暗叠加显示
    small *= (0.72 + hmap[..., None] * 0.13)
    img = Image.fromarray(np.clip(small, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    for o in objects:
        x, y = o["x"], o["y"]
        col = (255, 255, 255, 255)
        if "tree" in o["n"]:
            col = (40, 90, 40, 255)
        elif "house" in o["n"] or "barn" in o["n"] or "windmill" in o["n"]:
            col = (220, 60, 40, 255)
        elif "crop" in o["n"] or "fence" in o["n"]:
            col = (230, 200, 60, 255)
        d.point((x, y), fill=col)
    img.resize((WT * 5, HT * 5), Image.NEAREST).save(os.path.join(SCRATCH, "world_preview.png"))
    print("预览:", os.path.join(SCRATCH, "world_preview.png"))


# ==================================================================== main


def main() -> None:
    print("生成高度图…")
    hmap = smooth_height(build_height(), passes=1)
    hmap = np.clip(np.round(hmap), 0, MAX_H).astype(np.int8)
    print("  高度分布:", {int(k): int(v) for k, v in zip(*np.unique(hmap, return_counts=True))})

    print("生成材质场…")
    mat, fields = build_material(hmap)
    print("  材质占比:", {int(k): round(float(v), 3)
                          for k, v in zip(*np.unique(mat, return_counts=True))})

    print("逐像素上色…")
    rgb = colorize(mat, fields)

    print("分带烘焙地形…")
    bands = bake_bands(rgb, hmap)

    print("摆放物件…")
    placer = place_objects(hmap, mat)
    objects = placer.objects
    print(f"  {len(objects)} 个物件")

    save_preview(hmap, rgb, objects)

    # 不可通行：水 + 世界外圈
    solid_rows = []
    for r in range(HT):
        solid_rows.append("".join("1" if placer.blocked[r, x] else "0" for x in range(WT)))
    water_rows = []
    for r in range(HT):
        row = []
        for x in range(WT):
            sub = mat[r * TS : (r + 1) * TS, x * TS : (x + 1) * TS]
            row.append("1" if (sub == M_WATER).mean() > 0.35 else "0")
        water_rows.append("".join(row))

    data = {
        "tile": TS, "row_h": TS, "elev_h": ELEV,
        "w": WT, "h": HT, "max_h": MAX_H,
        "height": ["".join(str(int(v)) for v in row) for row in hmap],
        "water": water_rows,
        "solid": solid_rows,
        "bands": bands,
        "objects": objects,
        "spawn": {"x": 62.0, "y": 80.0},
    }
    path = os.path.join(OUT, "world.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))
    print(f"写出 {path}  ({os.path.getsize(path) / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
