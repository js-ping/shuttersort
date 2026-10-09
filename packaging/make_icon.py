"""生成 App 图标：紫底白色时钟，macOS 11+ 圆角规范（824/1024 内容区）。

纯标准库实现，输出 icons/app_icon.iconset/ 所需的全部尺寸，再用 iconutil 合成 .icns。
用法：python3 packaging/make_icon.py
"""

from __future__ import annotations

import math
import os
import struct
import subprocess
import sys
import zlib
from pathlib import Path

SIZE = 1024
MARGIN = 100          # macOS 11+ 图标内容区内边距
RADIUS = 186          # 圆角半径
BOX = SIZE - MARGIN * 2


# ---------------- 数学工具（SDF，d<0 在形状内部） ----------------

def sd_rounded_rect(x: float, y: float, half: float, r: float) -> float:
    qx, qy = abs(x) - half + r, abs(y) - half + r
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def sd_annulus(x: float, y: float, R: float, half: float) -> float:
    return abs(math.hypot(x, y) - R) - half


def sd_capsule(px, py, ax, ay, bx, by, r):
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    h = max(0.0, min(1.0, (pax * bax + pay * bay) / (bax * bax + bay * bay)))
    return math.hypot(pax - bax * h, pay - bay * h) - r


def cov(d: float) -> float:
    """SDF → 覆盖率（1px 抗锯齿）。"""
    return max(0.0, min(1.0, 0.5 - d))


# ---------------- 画面元素 ----------------

def clock_shapes(x: float, y: float) -> float:
    """时钟（环 + 指针 + 中点）的覆盖率。"""
    cx = cy = SIZE / 2.0
    dx, dy = x - cx, y - cy

    a = cov(sd_annulus(dx, dy, 190.0, 24.0))          # 外环

    h1 = cov(sd_capsule(dx, dy, 0.0, 0.0, 0.0, -118.0, 18.0))    # 分针（向上）
    h2 = cov(sd_capsule(dx, dy, 0.0, 0.0, 92.0, 0.0, 18.0))      # 时针（向右）
    dot = cov(math.hypot(dx, dy) - 26.0)                          # 中点

    return max(a, h1, h2, dot)


def pixel_color(x: float, y: float):
    """返回该像素 (r, g, b, a)，0-255。"""
    # 背景圆角矩形 + 对角渐变
    d = sd_rounded_rect(x - SIZE / 2.0, y - SIZE / 2.0, BOX / 2.0, RADIUS)
    bg_a = cov(d)
    if bg_a <= 0:
        return 0, 0, 0, 0
    t = (x + y) / (2.0 * SIZE)
    r = 176 + (77 - 176) * t        # #B07CEB → #4D2FA0
    g = 124 + (47 - 124) * t
    b = 235 + (160 - 235) * t

    fa = clock_shapes(x, y)
    if fa > 0:
        r = r * (1 - fa) + 255 * fa
        g = g * (1 - fa) + 255 * fa
        b = b * (1 - fa) + 255 * fa

    return int(r + 0.5), int(g + 0.5), int(b + 0.5), int(bg_a * 255 + 0.5)


# ---------------- PNG 写出 ----------------

def write_png(path: Path, size: int) -> None:
    raw = bytearray()
    sx = SIZE / size
    sy = SIZE / size
    for yi in range(size):
        raw.append(0)  # filter: none
        y = (yi + 0.5) * sy
        for xi in range(size):
            x = (xi + 0.5) * sx
            raw.extend(pixel_color(x, y))

    def chunk(tag: bytes, data: bytes) -> bytes:
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def main() -> int:
    out = Path(__file__).resolve().parent / "icons"
    iconset = out / "app_icon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)

    master = out / "icon_1024.png"
    print("生成母版 1024×1024 …")
    write_png(master, SIZE)

    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes:
        print(f"  缩放 {s}px …")
        subprocess.run(["sips", "-z", str(s), str(s), str(master),
                        "--out", str(iconset / f"icon_{s}x{s}.png")],
                       stdout=subprocess.DEVNULL, check=False)
        if s <= 512:
            subprocess.run(["sips", "-z", str(s), str(s), str(master),
                            "--out", str(iconset / f"icon_{s // 2}x{s // 2}@2x.png")],
                           stdout=subprocess.DEVNULL, check=False)

    icns = out / "app.icns"
    print("合成 app.icns …")
    r = subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if r.returncode != 0 or not icns.exists():
        print("iconutil 失败，跳过自定义图标")
        return 1
    print(f"完成：{icns}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
