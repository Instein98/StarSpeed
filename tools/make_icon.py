"""程序图标（开发者 2026-11-19 第 1 轮 #10）：深蓝黑圆角方块，金黄五角星，左边三条朱红速度线。
用代码画（numpy），输出 icon.png（256×256，窗口图标）和 icon.ico（内嵌 PNG，导出 exe 用）。

    python -I tools/make_icon.py
"""
import math
import os
import struct
import zlib

import numpy as np

N = 256
SS = 4                          # 超采样抗锯齿
ROOT = os.path.join(os.path.dirname(__file__), "..")
NAVY = (0x1b, 0x22, 0x33)
GOLD = (0xff, 0xc9, 0x3c)
RED = (0xef, 0x4a, 0x2f)
WARM = (0xf7, 0xec, 0xd4)


def star_mask(x, y, cx, cy, r_out, r_in, rot):
    """点 (x, y) 是否在五角星里：按角度在内外半径间插值。"""
    ang = np.arctan2(y - cy, x - cx) - rot
    d = np.hypot(x - cx, y - cy)
    seg = (ang % (2 * math.pi / 5)) / (2 * math.pi / 5)       # 0..1，0 和 1 是尖
    tri = np.abs(seg - 0.5) * 2                                # 尖处 1，谷处 0
    # 尖和谷之间是直线：用极坐标下直线方程近似
    r_edge = r_in + (r_out - r_in) * tri ** 1.6
    return d <= r_edge


def render():
    M = N * SS
    ys, xs = np.mgrid[0:M, 0:M].astype(np.float64) / SS
    img = np.zeros((M, M, 4))
    # 圆角方块
    r = 44.0
    qx = np.maximum(np.abs(xs - N / 2) - (N / 2 - r), 0)
    qy = np.maximum(np.abs(ys - N / 2) - (N / 2 - r), 0)
    box = np.hypot(qx, qy) <= r
    img[box] = (*NAVY, 255)
    # 三条速度线（左边，向右变细）
    for i, (y0, x0, x1, w) in enumerate([(92, 30, 120, 9), (128, 18, 112, 11), (164, 30, 120, 9)]):
        t = np.clip((xs - x0) / (x1 - x0), 0, 1)
        half = w * (1 - 0.7 * t)
        line = (xs >= x0) & (xs <= x1) & (np.abs(ys - y0) <= half) & box
        img[line] = (*RED, 255)
    # 星：暖白描边 + 金黄
    cx, cy = 160, 132
    rot = -math.pi / 2
    outline = star_mask(xs, ys, cx, cy, 92, 40, rot) & box
    img[outline] = (*WARM, 255)
    star = star_mask(xs, ys, cx, cy, 80, 33, rot)
    img[star] = (*GOLD, 255)
    # 下采样
    out = img.reshape(N, SS, N, SS, 4).mean(axis=(1, 3))
    return np.clip(out, 0, 255).astype(np.uint8)


def png_bytes(a):
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(a.shape[0]))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", a.shape[1], a.shape[0], 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    a = render()
    png = png_bytes(a)
    open(os.path.join(ROOT, "icon.png"), "wb").write(png)
    # ICO：一个 256×256 的 PNG 条目（宽高字段 0 表示 256）
    ico = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", 0, 0, 0, 0, 1, 32, len(png), 22) + png
    open(os.path.join(ROOT, "icon.ico"), "wb").write(ico)
    print("wrote icon.png, icon.ico")
