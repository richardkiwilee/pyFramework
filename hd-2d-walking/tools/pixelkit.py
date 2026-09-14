"""像素美术工具库：调色板 + 位掩码绘制原语。

所有精灵都按"光从左上来"的约定绘制：左/上受光，右/下背光，外圈描边。
坐标一律用 numpy 掩码 (h, w) bool，颜色用 (r, g, b) 或 (r, g, b, a)。
"""
from __future__ import annotations

import numpy as np
from PIL import Image

# ---------------------------------------------------------------- 调色板

PAL: dict[str, tuple[int, int, int]] = {
    # 草（主色，不饱和，避免"塑料绿"）
    "grass_deep": (54, 88, 46),
    "grass_dark": (70, 108, 54),
    "grass_base": (90, 132, 64),
    "grass_lit": (114, 158, 78),
    "grass_hi": (140, 182, 96),
    # 干草 / 秋色平原
    "dry_deep": (108, 110, 52),
    "dry_dark": (134, 136, 64),
    "dry_base": (160, 158, 80),
    "dry_lit": (186, 180, 98),
    # 泥土 / 路
    "dirt_deep": (92, 68, 46),
    "dirt_dark": (118, 88, 58),
    "dirt_base": (148, 114, 74),
    "dirt_lit": (176, 140, 96),
    "pebble": (150, 142, 130),
    # 岩石
    "rock_deep": (66, 60, 56),
    "rock_dark": (96, 88, 78),
    "rock_base": (128, 118, 104),
    "rock_lit": (158, 148, 130),
    "rock_hi": (186, 178, 160),
    # 水
    "water_deep": (32, 74, 110),
    "water_dark": (46, 98, 138),
    "water_base": (62, 126, 164),
    "water_lit": (96, 166, 194),
    "foam": (198, 224, 226),
    # 阔叶树冠
    "leaf_deep": (36, 66, 40),
    "leaf_dark": (52, 90, 46),
    "leaf_base": (72, 118, 56),
    "leaf_lit": (100, 148, 70),
    "leaf_hi": (128, 174, 88),
    # 松针
    "pine_deep": (28, 58, 46),
    "pine_dark": (42, 80, 58),
    "pine_base": (58, 104, 68),
    "pine_lit": (80, 132, 82),
    "pine_hi": (104, 158, 96),
    # 秋叶
    "aut_deep": (108, 58, 32),
    "aut_dark": (150, 82, 36),
    "aut_base": (190, 116, 44),
    "aut_lit": (216, 152, 62),
    "aut_hi": (236, 190, 92),
    # 木料
    "wood_deep": (60, 40, 26),
    "wood_dark": (88, 58, 36),
    "wood_base": (120, 84, 52),
    "wood_lit": (152, 112, 72),
    "wood_hi": (180, 140, 96),
    # 红瓦屋顶
    "roof_deep": (98, 40, 36),
    "roof_dark": (134, 56, 46),
    "roof_base": (170, 78, 60),
    "roof_lit": (202, 108, 82),
    "roof_hi": (224, 142, 112),
    # 蓝瓦屋顶
    "slate_deep": (40, 56, 82),
    "slate_dark": (56, 78, 106),
    "slate_base": (78, 106, 136),
    "slate_lit": (104, 136, 166),
    "slate_hi": (136, 168, 194),
    # 茅草屋顶
    "thatch_deep": (92, 72, 38),
    "thatch_dark": (124, 100, 50),
    "thatch_base": (158, 130, 68),
    "thatch_lit": (188, 160, 92),
    "thatch_hi": (212, 188, 122),
    # 墙面
    "wall_deep": (128, 106, 82),
    "wall_dark": (168, 144, 114),
    "wall_base": (206, 184, 150),
    "wall_lit": (228, 210, 180),
    "wall_hi": (242, 230, 206),
    # 玻璃 / 夜窗
    "glass_dark": (44, 60, 74),
    "glass_base": (70, 96, 112),
    "glass_lit": (116, 152, 166),
    "lamp_warm": (255, 208, 130),
    # 布 / 衣物点缀
    "cloth_red": (162, 62, 54),
    "cloth_blue": (60, 88, 132),
    # 描边与阴影（不用纯黑，用带蓝紫的深色）
    "line": (38, 32, 42),
    "line_soft": (54, 48, 62),
}


def C(name: str, a: int = 255) -> tuple[int, int, int, int]:
    r, g, b = PAL[name]
    return (r, g, b, a)


def mix(a: tuple, b: tuple, t: float) -> tuple[int, int, int, int]:
    """两色线性插值，t=0 → a，t=1 → b。"""
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(4))  # type: ignore[return-value]


def shade(name: str, t: float) -> tuple[int, int, int, int]:
    """把颜色朝黑/白推，t<0 变暗、t>0 变亮。"""
    base = C(name)
    if t >= 0:
        return mix(base, (255, 255, 255, 255), t)
    return mix(base, (0, 0, 0, 255), -t)


# ---------------------------------------------------------------- 画布


class Canvas:
    """一张 RGBA 画布，所有绘制都是掩码操作。"""

    def __init__(self, w: int, h: int):
        self.w = w
        self.h = h
        self.px = np.zeros((h, w, 4), np.uint8)

    # -- 基本 --------------------------------------------------------

    def blank(self, mask: np.ndarray, color) -> None:
        self.px[mask] = color

    def out(self) -> Image.Image:
        return Image.fromarray(self.px, "RGBA")

    @property
    def mask(self) -> np.ndarray:
        return self.px[:, :, 3] > 0

    def opaque_mask(self, min_a: int = 200) -> np.ndarray:
        return self.px[:, :, 3] >= min_a

    # -- 形状 --------------------------------------------------------

    def rect(self, x: int, y: int, w: int, h: int) -> np.ndarray:
        m = np.zeros((self.h, self.w), bool)
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(self.w, x + w), min(self.h, y + h)
        if x1 > x0 and y1 > y0:
            m[y0:y1, x0:x1] = True
        return m

    def ellipse(self, cx: float, cy: float, rx: float, ry: float) -> np.ndarray:
        yy, xx = np.mgrid[0 : self.h, 0 : self.w]
        return ((xx - cx) / max(rx, 0.001)) ** 2 + ((yy - cy) / max(ry, 0.001)) ** 2 <= 1.0

    def circle(self, cx: float, cy: float, r: float) -> np.ndarray:
        return self.ellipse(cx, cy, r, r)

    def poly(self, points: list[tuple[float, float]]) -> np.ndarray:
        """扫描线多边形填充（整数像素中心测试）。"""
        yy, xx = np.mgrid[0 : self.h, 0 : self.w]
        xx = xx + 0.5
        yy = yy + 0.5
        inside = np.zeros((self.h, self.w), bool)
        n = len(points)
        for i in range(n):
            x1, y1 = points[i]
            x2, y2 = points[(i + 1) % n]
            if y1 == y2:
                continue
            cond = ((yy >= np.minimum(y1, y2)) & (yy < np.maximum(y1, y2)))
            xx_int = (x2 - x1) * (yy - y1) / (y2 - y1) + x1
            inside ^= cond & (xx < xx_int)
        return inside

    def line(self, x0: int, y0: int, x1: int, y1: int, thick: int = 1) -> np.ndarray:
        m = np.zeros((self.h, self.w), bool)
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(steps + 1):
            t = i / max(steps, 1)
            px = int(round(x0 + (x1 - x0) * t))
            py = int(round(y0 + (y1 - y0) * t))
            r = thick // 2
            m |= self.rect(px - r, py - r, thick, thick)
        return m


# ---------------------------------------------------------------- 掩码运算


def shift(m: np.ndarray, dx: int, dy: int) -> np.ndarray:
    """平移掩码，空出的地方补 False（不环绕）。"""
    out = np.zeros_like(m)
    h, w = m.shape
    xs0, xs1 = max(0, dx), min(w, w + dx)
    ys0, ys1 = max(0, dy), min(h, h + dy)
    if xs1 <= xs0 or ys1 <= ys0:
        return out
    out[ys0:ys1, xs0:xs1] = m[ys0 - dy : ys1 - dy, xs0 - dx : xs1 - dx]
    return out


def dilate(m: np.ndarray, n: int = 1) -> np.ndarray:
    out = m.copy()
    for _ in range(n):
        acc = out.copy()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc |= shift(out, dx, dy)
        out = acc
    return out


def erode(m: np.ndarray, n: int = 1) -> np.ndarray:
    out = m.copy()
    for _ in range(n):
        acc = out.copy()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc &= shift(out, dx, dy)
        out = acc
    return out


def outline_of(m: np.ndarray, thickness: int = 1) -> np.ndarray:
    """掩码外圈（不含自身）。"""
    return dilate(m, thickness) & ~m


def rim(m: np.ndarray, dx: int, dy: int) -> np.ndarray:
    """把掩码朝 (dx, dy) 推后再与原掩码相交 —— 得到朝那个方向的边缘带。"""
    return shift(m, dx, dy) & m


# ---------------------------------------------------------------- 噪声


def value_noise(seed: int, w: int, h: int, scale: int, octaves: int = 3,
                persistence: float = 0.5, wrap: bool = True) -> np.ndarray:
    """0..1 的值噪声。wrap=True 时在 w/h 上无缝（用于可平铺纹理）。"""
    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        gw = max(2, int(np.ceil(w / (scale / (2 ** o)))))
        gh = max(2, int(np.ceil(h / (scale / (2 ** o)))))
        grid = rng.random((gh, gw)).astype(np.float32)
        if wrap:
            # 让最后一列/行与第一列/行对齐，保证拼接连续
            grid[-1, :] = grid[0, :]
            grid[:, -1] = grid[:, 0]
        img = np.array(
            Image.fromarray((grid * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR),
            np.float32,
        ) / 255.0
        acc += img * amp
        total += amp
        amp *= persistence
    return acc / total


def hash_noise(seed: int, w: int, h: int) -> np.ndarray:
    """逐像素白噪声 0..1，用于抖动/颗粒。"""
    rng = np.random.default_rng(seed)
    return rng.random((h, w)).astype(np.float32)


def bayer4() -> np.ndarray:
    """4x4 有序抖动矩阵，归一化到 0..1。用于像素画的规矩抖动。"""
    b = np.array(
        [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32
    )
    return (b + 0.5) / 16.0


def dither_threshold(w: int, h: int, ox: int = 0, oy: int = 0) -> np.ndarray:
    """平铺的 4x4 抖动阈值场，大小 (h, w)，带偏移保证跨格连续。"""
    b = bayer4()
    yy, xx = np.mgrid[0:h, 0:w]
    return b[(yy + oy) % 4, (xx + ox) % 4]


def quantize_to_palette(img: np.ndarray, colors: list[tuple[int, int, int]],
                        alpha_threshold: int = 8) -> np.ndarray:
    """把 RGB 图吸附到给定调色板（保留 alpha）。让画面统一、有像素画味。"""
    h, w, _ = img.shape
    rgb = img[:, :, :3].astype(np.float32)
    pal = np.array(colors, np.float32)
    flat = rgb.reshape(-1, 3)
    d = ((flat[:, None, :] - pal[None, :, :]) ** 2).sum(axis=2)
    idx = d.argmin(axis=1)
    out = img.copy()
    out[:, :, :3] = pal[idx].reshape(h, w, 3).astype(np.uint8)
    return out
