"""生成点光用的径向衰减贴图。

Godot 的 GradientTexture2D(FILL_RADIAL) 在 Light2D 上会渲染成方块（实测），
所以这里直接算一张真正的圆形衰减图。光色烘进 RGB，alpha 恒为 255——
Light2D 到底读 rgb 还是 rgb*alpha 在不同版本里不一致，写成两者都对最保险。
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "world", "light_radial.png")
SIZE = 256


def main() -> None:
    r = SIZE // 2
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    d = np.sqrt((xx - r + 0.5) ** 2 + (yy - r + 0.5) ** 2) / r
    d = np.clip(d, 0.0, 1.0)
    # 平滑衰减：中心一小块保持接近满亮，边缘平方衰减到 0，不出现硬边
    fall = np.clip(1.0 - d, 0.0, 1.0) ** 2.0
    core = np.clip(1.0 - d * 2.2, 0.0, 1.0) ** 2.0 * 0.35
    fall = np.clip(fall + core, 0.0, 1.0)

    warm = np.array([1.0, 0.86, 0.60], np.float32)
    rgb = (fall[..., None] * warm[None, None, :] * 255.0).astype(np.uint8)
    a = np.full((SIZE, SIZE, 1), 255, np.uint8)
    img = Image.fromarray(np.concatenate([rgb, a], axis=2), "RGBA")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print(OUT, img.size)


if __name__ == "__main__":
    main()
