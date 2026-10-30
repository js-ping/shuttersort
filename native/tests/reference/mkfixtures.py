#!/usr/bin/env python3
"""造测试样本的工具函数 —— **只给测试用，不是产品代码**。

原先在 `tests/selftest.py` 里（那份 72 项自检测的是已经删掉的 HTTP 接口，
随 Windows/Linux 版一起移除了）。这里的几个构造器保留了，因为它们是
`mkcorpus.py` 造对照样本的基础：

- `make_tiff` / `make_jpeg`：手搓真实的 TIFF IFD 结构，包括「≤4 字节内联、
  超过 4 字节写偏移」这条真实相机遵守的规矩
- `make_png`：带 `tIME` 块
- `make_mp4_with_mvhd`：1904 纪元 UTC 秒数的极简 MP4，用来验时区换算是真的对

这些样本本身都是踩坑踩出来的：大端 TIFF、带时区偏移的 EXIF、同秒连拍
（文件名顺序故意和亚秒顺序相反）。删之前先想清楚覆盖了什么。
"""
from __future__ import annotations

import json
import struct
import zlib
from datetime import datetime
from pathlib import Path

# 视频样本用的 UTC 时刻。换回本地时间后应该等于 VIDEO_LOCAL
VIDEO_UTC = datetime(2024, 5, 6, 7, 30, 8)


def make_tiff(dt="2021:07:04 08:09:10", little=True, subsec=None):
    en = "<" if little else ">"
    head = (b"II" if little else b"MM") + struct.pack(en + "H", 42) + struct.pack(en + "I", 8)
    ifd0 = struct.pack(en + "H", 1) + struct.pack(en + "HHI", 0x8769, 4, 1) + struct.pack(en + "I", 26)
    ifd0 += struct.pack(en + "I", 0)

    raw = dt.encode() + b"\x00"
    subs = (subsec.encode() + b"\x00") if subsec else b""
    entries = [(0x9003, raw)] + ([(0x9291, subs)] if subs else [])
    # TIFF 规矩：≤4 字节的 ASCII 直接内联在 value 字段里，超过 4 字节才写偏移
    # （真实的相机就是这么写 SubSec 的，样本也得照做，否则测出来是假的）
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


def make_jpeg(dt="2021:07:04 08:09:10", xmp=None, subsec=None):
    tiff = make_tiff(dt, subsec=subsec)
    app1 = b"\xff\xe1" + struct.pack(">H", len(tiff) + 8) + b"Exif\x00\x00" + tiff
    seg = b""
    if xmp:
        body = b"http://ns.adobe.com/xap/1.0/\x00" + xmp.encode()
        seg = b"\xff\xe1" + struct.pack(">H", len(body) + 2) + body
    sof = b"\xff\xc0" + struct.pack(">H", 11) + b"\x08\x00\x10\x00\x10\x01\x01\x11\x00"
    sos = b"\xff\xda" + struct.pack(">H", 8) + b"\x01\x01\x00\x00\x3f\x00" + b"\x00" * 8
    return b"\xff\xd8" + app1 + seg + sof


def png_chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)


def make_png(y=2018, mo=11, d=23, hh=7, mm=8, ss=9):
    return (b"\x89PNG\r\n\x1a\n"
            + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 2, 0, 0, 0))
            + png_chunk(b"tIME", struct.pack(">HBBBBB", y, mo, d, hh, mm, ss))
            + png_chunk(b"IEND", b""))


def make_mp4_with_mvhd(utc_dt):
    """造一个只含 ftyp + moov/mvhd 的极简 MP4。

    mvhd 里的 creation_time 和真实现场一样是「1904 纪元的 UTC 秒数」，
    能不能正确换回本地时间，就靠这个样本兜着。
    """
    epoch = datetime(1904, 1, 1)
    secs = int((utc_dt - epoch).total_seconds())
    payload = (b"\x00\x00\x00\x00"                       # version 0 + flags
               + struct.pack(">II", secs, secs)          # creation / modification
               + struct.pack(">II", 1000, 0))            # timescale / duration
    mvhd = struct.pack(">I", 8 + len(payload)) + b"mvhd" + payload
    moov = struct.pack(">I", 8 + len(mvhd)) + b"moov" + mvhd
    ftyp = struct.pack(">I", 16) + b"ftyp" + b"isom\x00\x00\x02\x00"
    return ftyp + moov


def build_samples(root: Path) -> None:
    """造出对照测试的基础样本集。每个文件都在验证一条具体的解析路径。"""
    root.mkdir(parents=True, exist_ok=True)
    (root / "photo_exif.jpg").write_bytes(make_jpeg())
    (root / "photo_xmp.jpg").write_bytes(make_jpeg(
        xmp='<x:xmpmeta><xmp:CreateDate>2019-03-05T22:33:44</xmp:CreateDate></x:xmpmeta>'))
    (root / "shot.png").write_bytes(make_png())
    (root / "IMG_20250418_193012.jpg").write_bytes(b"\xff\xd8\xff\xd9" + b"\x00" * 64)
    (root / "DJI_20251108_164116_0042_D.MP4").write_bytes(b"\x00\x00\x00\x18ftypisom" + b"\x00" * 128)
    (root / "VID-20240125-WA0007.mp4").write_bytes(b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 32)
    (root / "Screenshot 2024-09-15 at 10.20.30.jpg").write_bytes(b"\xff\xd8\xff\xd9")
    (root / "stripped.jpg").write_bytes(b"\xff\xd8\xff\xd9")
    (root / "stripped.jpg.json").write_text(
        json.dumps({"photoTakenTime": {"timestamp": "1609459200"}}), encoding="utf-8")
    (root / "via_xmp.mp4").write_bytes(b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 32)
    (root / "via_xmp.mp4.xmp").write_text(
        "<xmp:CreateDate>2022-02-02T02:02:02</xmp:CreateDate>", encoding="utf-8")
    (root / "no_meta_at_all.jpg").write_bytes(b"\xff\xd8\xff\xd9")
    (root / "video_mvhd.mp4").write_bytes(make_mp4_with_mvhd(VIDEO_UTC))
    # 同秒连拍：文件名顺序故意和亚秒顺序相反（a 的 .42 晚于 b 的 .08）
    (root / "burst_a.jpg").write_bytes(make_jpeg("2023:09:10 12:00:00", subsec="42"))
    (root / "burst_b.jpg").write_bytes(make_jpeg("2023:09:10 12:00:00", subsec="08"))

    sub = root / "sub"
    sub.mkdir(exist_ok=True)
    (sub / "IMG_20200101000000_0001.jpg").write_bytes(b"\xff\xd8\xff\xd9")
