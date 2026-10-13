"""生成 Windows 图标 icons/app.ico（紫底白色时钟，和 macOS 版同一套图形）。

纯标准库实现，不依赖 Pillow / ImageMagick，在 macOS、Windows、Linux 上都能跑。
图形本身是 SDF（有向距离场）渲染的，天生分辨率无关 —— 每个尺寸都是重新算出来的，
不是把小图拉大，所以 16×16 的小图标也清晰。

用法：python3 packaging/make_ico.py
"""

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

# Windows 上输出被重定向到管道时 Python 会用 ANSI 代码页（英文系统 cp1252）编码
# stdout，打印中文会 UnicodeEncodeError，这里自己把流切到 UTF-8。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        pass

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from make_icon import SIZE, pixel_color  # noqa: E402

# ICO 里要放的尺寸。16/32/48 是任务栏和资源管理器用的，256 是「大图标」视图。
SIZES = [16, 24, 32, 48, 64, 128, 256]


def render_rgba(size: int) -> bytes:
    """把图案渲染成 size×size 的 RGBA 原始字节（顺序：从上到下、从左到右）。"""
    scale = SIZE / size
    out = bytearray()
    for yi in range(size):
        y = (yi + 0.5) * scale
        for xi in range(size):
            x = (xi + 0.5) * scale
            out.extend(pixel_color(x, y))
    return bytes(out)


def png_bytes(size: int) -> bytes:
    """同一套图案编码成 PNG（ICO 的 256×256 条目用这种格式）。"""
    rgba = render_rgba(size)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    raw = bytearray()
    stride = size * 4
    for row in range(size):
        raw.append(0)                                   # filter: none
        raw.extend(rgba[row * stride:(row + 1) * stride])

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


def bmp_bytes(size: int) -> bytes:
    """ICO 内嵌的 DIB 位图（BITMAPINFOHEADER + BGRA + AND 掩码）。

    老版本的 Windows 对「小尺寸用 PNG 压缩」支持不完全，
    所以 ≤128 的条目一律用这种最保险的未压缩格式。
    """
    rgba = render_rgba(size)
    header = struct.pack(
        "<IiiHHIIiiII",
        40,          # biSize
        size,        # biWidth
        size * 2,    # biHeight（ICO 规定要写两倍，含 AND 掩码）
        1,           # biPlanes
        32,          # biBitCount
        0,           # biCompression = BI_RGB
        size * size * 4,
        0, 0, 0, 0,
    )

    # 像素是自下而上存的，且顺序是 BGRA
    pixels = bytearray()
    stride = size * 4
    for row in range(size - 1, -1, -1):
        base = row * stride
        for col in range(size):
            i = base + col * 4
            r, g, b, a = rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]
            pixels += bytes((b, g, r, a))

    # AND 掩码：每行按 32 位对齐。全 0 = 不透明（真正的透明度由 alpha 通道决定）
    mask_stride = ((size + 31) // 32) * 4
    mask = bytes(mask_stride * size)

    return header + bytes(pixels) + mask


def build_ico(out: Path) -> None:
    entries, blobs = [], []
    offset = 6 + 16 * len(SIZES)
    for size in SIZES:
        data = png_bytes(size) if size >= 256 else bmp_bytes(size)
        entries.append(struct.pack(
            "<BBBBHHII",
            0 if size >= 256 else size,   # 宽度（256 记作 0）
            0 if size >= 256 else size,   # 高度
            0,                            # 调色板数量
            0,                            # 保留
            1,                            # 颜色平面
            32,                           # 位深
            len(data),
            offset,
        ))
        blobs.append(data)
        offset += len(data)

    out.write_bytes(struct.pack("<HHH", 0, 1, len(SIZES)) + b"".join(entries)
                    + b"".join(blobs))


def main() -> int:
    out = HERE / "icons" / "app.ico"
    out.parent.mkdir(parents=True, exist_ok=True)
    build_ico(out)
    print(f"完成：{out}  （{out.stat().st_size / 1024:.1f} KB，含 "
          f"{'/'.join(str(s) for s in SIZES)} 共 {len(SIZES)} 个尺寸）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
