#!/usr/bin/env python3
"""造一批覆盖各种格式的样本，供逐字段对照测试使用。

样本构造器放在 reference/mkfixtures.py（那些样本本身就是踩坑踩出来的），
再补上没覆盖的：大端 TIFF、WebP、HEIC、子目录、带时区偏移的 EXIF。
"""
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "reference"))

import mkfixtures as st        # noqa: E402  （纯工具函数，import 无副作用）

# 默认写到临时目录，也可以 --out 指定
OUT = Path(sys.argv[sys.argv.index("--out") + 1]) if "--out" in sys.argv \
    else Path(tempfile.gettempdir()) / "shuttersort-corpus"


def make_webp(exif_tiff: bytes) -> bytes:
    """RIFF/WEBP + EXIF chunk。WebP 的长度是小端，奇数长度要补一字节。"""
    payload = b"Exif\x00\x00" + exif_tiff
    chunk = b"EXIF" + struct.pack("<I", len(payload)) + payload
    if len(payload) & 1:
        chunk += b"\x00"
    body = b"WEBP" + chunk
    return b"RIFF" + struct.pack("<I", len(body)) + body


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    # ---- 自检那套基础样本 ----
    st.build_samples(OUT)

    # ---- 大端 TIFF ----
    (OUT / "bigendian.tif").write_bytes(st.make_tiff("2020:02:29 23:59:58", little=False))

    # ---- WebP ----
    (OUT / "picture.webp").write_bytes(make_webp(st.make_tiff("2017:12:25 06:30:00")))

    # ---- 带时区偏移的 EXIF（OffsetTimeOriginal）----
    # 手工拼一个 IFD，DateTimeOriginal + OffsetTimeOriginal=+08:00
    def tiff_with_offset(dt: str, off: str) -> bytes:
        en = "<"
        head = b"II" + struct.pack(en + "H", 42) + struct.pack(en + "I", 8)
        ifd0 = struct.pack(en + "H", 1) + struct.pack(en + "HHI", 0x8769, 4, 1) + struct.pack(en + "I", 26)
        ifd0 += struct.pack(en + "I", 0)
        raw = dt.encode() + b"\x00"
        offb = off.encode() + b"\x00"
        entries = [(0x9003, raw), (0x9011, offb)]
        data_off = 26 + 2 + 12 * len(entries) + 4
        body, blob = b"", b""
        for tag, val in entries:
            if len(val) <= 4:
                blob += struct.pack(en + "HHI", tag, 2, len(val)) + val.ljust(4, b"\x00")
            else:
                blob += (struct.pack(en + "HHI", tag, 2, len(val))
                         + struct.pack(en + "I", data_off + len(body)))
                body += val
        exif = struct.pack(en + "H", len(entries)) + blob + struct.pack(en + "I", 0) + body
        return head + ifd0 + exif

    t = tiff_with_offset("2019:08:01 12:00:00", "+08:00")
    app1 = b"\xff\xe1" + struct.pack(">H", len(t) + 8) + b"Exif\x00\x00" + t
    (OUT / "offset_time.jpg").write_bytes(b"\xff\xd8" + app1 + b"\xff\xd9")

    # ---- XMP 里带 Z（UTC）----
    (OUT / "utc_z.jpg").write_bytes(st.make_jpeg(
        xmp='<x:xmpmeta><xmp:CreateDate>2020-06-01T04:05:06Z</xmp:CreateDate></x:xmpmeta>'))

    # ---- 子目录（测递归，也测同秒冲突）----
    sub = OUT / "子目录"
    sub.mkdir()
    (sub / "child_a.jpg").write_bytes(st.make_jpeg("2022:03:04 05:06:07"))
    (sub / "child_b.jpg").write_bytes(st.make_jpeg("2022:03:04 05:06:07"))   # 同名冲突

    # ---- HEIC：用系统 sips 从 JPEG 转一张（真容器，不是手搓的）----
    src = OUT / "photo_exif.jpg"
    if shutil.which("sips") and src.exists():
        dst = OUT / "real.heic"
        r = subprocess.run(["sips", "-s", "format", "heic", str(src), "--out", str(dst)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("HEIC:", "生成成功" if dst.exists() and r.returncode == 0 else "跳过")

    files = sorted(p.name for p in OUT.iterdir())
    print(f"样本 {len(files)} 个：")
    for f in files:
        print("  ", f)


if __name__ == "__main__":
    main()
