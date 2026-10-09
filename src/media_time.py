"""媒体拍摄时间解析引擎。

设计目标
--------
1. **零第三方依赖**：全部用 Python 标准库实现，不需要 pip install 任何东西。
2. **可选的 exiftool 增强**：如果系统里装了 exiftool，会自动用它做第一层提取，
   覆盖度更高；没装也完全能用。
3. **决定论**：每种格式的时间戳来源固定优先级，结果可复现、可审计。
4. **可解释**：每个结果都带 source 字符串，界面上能看到"这个时间是哪儿来的"。

时间戳优先级（从高到低）
------------------------
  1. exiftool（若可用）
  2. 容器内嵌元数据：ISOBMFF(MP4/MOV/HEIC)  creationdate → mvhd → mdhd
  3. XMP（JPEG/PNG/WebP 内嵌）xmp:CreateDate / photoshop:DateCreated
  4. EXIF（JPEG/TIFF/RAW/WebP）DateTimeOriginal → DateTimeDigitized → DateTime
  5. PNG tIME chunk
  6. Google Takeout .json 旁车文件
  7. .xmp 旁车文件
  8. 文件名解析（Deep 模式）
  9. 文件系统时间（可选兜底）
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import re
import struct
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# --------------------------------------------------------------------------
# 常量
# --------------------------------------------------------------------------

EPOCH_1904 = _dt.datetime(1904, 1, 1, tzinfo=_dt.timezone.utc)

IMAGE_EXTS = {
    ".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff", ".gif",
    ".heic", ".heif", ".avif",
    ".arw", ".nef", ".cr2", ".cr3", ".dng", ".rw2", ".orf", ".srw", ".raf", ".pef",
    ".jfif", ".jpe",
}
VIDEO_EXTS = {
    ".mp4", ".mov", ".m4v", ".mkv", ".avi", ".wmv", ".webm",
    ".3gp", ".3g2", ".mts", ".m2ts", ".mpg", ".mpeg", ".m2v", ".flv", ".ts",
}
MEDIA_EXTS = IMAGE_EXTS | VIDEO_EXTS

DATE_FORMATS = (
    "%Y:%m:%d %H:%M:%S",
    "%Y-%m-%d %H:%M:%S",
    "%Y/%m/%d %H:%M:%S",
    "%Y-%m-%dT%H:%M:%S",
    "%Y:%m:%d %H:%M:%S.%f",
    "%Y-%m-%d %H:%M:%S.%f",
    "%Y-%m-%dT%H:%M:%S.%f",
    "%Y:%m:%d %H:%M",
    "%Y-%m-%d %H:%M",
    "%Y-%m-%d",
    "%Y:%m:%d",
)

TZ_RX = re.compile(r"([+-])(\d{2}):?(\d{2})$")


# --------------------------------------------------------------------------
# 时间字符串解析
# --------------------------------------------------------------------------

def parse_datetime_any(s: Any) -> Optional[_dt.datetime]:
    """把各种风格的日期字符串解析成 datetime（带时区的转成本地朴素时间）。"""
    if s is None:
        return None
    if isinstance(s, _dt.datetime):
        return to_local_naive(s)
    s = str(s).strip()
    if not s:
        return None

    s = re.sub(r"\s+", " ", s)
    # 去掉结尾的 "Z"
    if s.endswith("Z"):
        s = s[:-1].strip()

    for fmt in DATE_FORMATS:
        try:
            return _dt.datetime.strptime(s, fmt)
        except ValueError:
            continue

    # 带时区偏移量：自己算，保证 3.9 也能用
    m = TZ_RX.search(s)
    if m:
        base = s[: m.start()].strip()
        for fmt in DATE_FORMATS:
            try:
                dt = _dt.datetime.strptime(base, fmt)
            except ValueError:
                continue
            sign = 1 if m.group(1) == "+" else -1
            off = sign * (int(m.group(2)) * 60 + int(m.group(3)))
            tz = _dt.timezone(_dt.timedelta(minutes=off))
            return to_local_naive(dt.replace(tzinfo=tz))
    return None


def to_local_naive(dt: _dt.datetime) -> _dt.datetime:
    """带时区的 datetime → 本机时区的朴素 datetime。"""
    if dt.tzinfo is None:
        return dt
    try:
        return dt.astimezone().replace(tzinfo=None)
    except Exception:
        return dt.replace(tzinfo=None)


def _apply_subsec(dt: Optional[_dt.datetime], subsec: Any) -> Optional[_dt.datetime]:
    if dt is None or subsec is None:
        return dt
    txt = str(subsec).strip()
    if not txt.isdigit():
        return dt
    try:
        micro = int((txt + "000000")[:6])
        return dt.replace(microsecond=micro)
    except Exception:
        return dt


# --------------------------------------------------------------------------
# 随机读取封装
# --------------------------------------------------------------------------

class _Reader:
    """统一的内存 / 文件随机读取接口，offset 一律是"文件绝对偏移"。"""

    def __init__(self, data: Optional[bytes] = None, path: Optional[Path] = None):
        self._data = data
        self._fh = None
        if data is not None:
            self.size = len(data)
        else:
            assert path is not None
            self._fh = open(str(path), "rb")
            self._fh.seek(0, os.SEEK_END)
            self.size = self._fh.tell()

    def read_at(self, off: int, n: int) -> bytes:
        if off < 0 or off >= self.size or n <= 0:
            return b""
        n = min(n, self.size - off)
        if self._data is not None:
            return self._data[off: off + n]
        self._fh.seek(off)
        return self._fh.read(n)

    def u16(self, off: int, big: bool = True) -> Optional[int]:
        b = self.read_at(off, 2)
        return int.from_bytes(b, "big" if big else "little") if len(b) == 2 else None

    def u32(self, off: int, big: bool = True) -> Optional[int]:
        b = self.read_at(off, 4)
        return int.from_bytes(b, "big" if big else "little") if len(b) == 4 else None

    def close(self) -> None:
        if self._fh is not None:
            try:
                self._fh.close()
            except Exception:
                pass
            self._fh = None

    def __enter__(self) -> "_Reader":
        return self

    def __exit__(self, *a) -> None:
        self.close()


# --------------------------------------------------------------------------
# TIFF / EXIF 解析
# --------------------------------------------------------------------------

_TYPE_SIZE = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8}
_TAG_NAME = {
    0x010F: "Make", 0x0110: "Model", 0x0112: "Orientation",
    0x0132: "DateTime", 0x8769: "ExifIFD", 0x8825: "GPSIFD",
    0x9003: "DateTimeOriginal", 0x9004: "DateTimeDigitized",
    0x9000: "ExifVersion", 0x9010: "OffsetTime",
    0x9011: "OffsetTimeOriginal", 0x9012: "OffsetTimeDigitized",
    0x9290: "SubSecTime", 0x9291: "SubSecTimeOriginal", 0x9292: "SubSecTimeDigitized",
    0xA002: "PixelXDimension", 0xA003: "PixelYDimension",
    0x013B: "Artist", 0x8298: "Copyright",
}
_EXIF_TEXT_TAGS = (
    "DateTimeOriginal", "DateTimeDigitized", "DateTime",
    "OffsetTimeOriginal", "OffsetTimeDigitized", "OffsetTime",
    "SubSecTimeOriginal", "SubSecTimeDigitized", "SubSecTime",
    "Make", "Model", "Orientation", "PixelXDimension", "PixelYDimension",
)


class TiffError(Exception):
    pass


def parse_tiff(reader: _Reader, tiff_off: int, max_ifd: int = 6) -> Dict[str, str]:
    """解析 TIFF 头（EXIF 也走这里），返回 {标签名: 字符串值}。"""
    head = reader.read_at(tiff_off, 8)
    if len(head) < 8:
        raise TiffError("TIFF 头不完整")
    if head[:2] == b"II":
        big = False
    elif head[:2] == b"MM":
        big = True
    else:
        raise TiffError("字节序标识非法")
    if reader.u16(tiff_off + 2, big) != 42:
        raise TiffError("TIFF magic 非法")

    out: Dict[str, str] = {}
    visited = set()
    queue: List[Tuple[int, int]] = [(reader.u32(tiff_off + 4, big) or 0, 0)]

    while queue:
        off, depth = queue.pop(0)
        if off is None or off in visited or depth > max_ifd or off <= 0:
            continue
        visited.add(off)

        cnt_b = reader.read_at(tiff_off + off, 2)
        if len(cnt_b) < 2:
            continue
        count = int.from_bytes(cnt_b, "big" if big else "little")
        if count <= 0 or count > 4096:
            continue

        entries = reader.read_at(tiff_off + off + 2, count * 12)
        for i in range(count):
            e = entries[i * 12: i * 12 + 12]
            if len(e) < 12:
                break
            tag = int.from_bytes(e[0:2], "big" if big else "little")
            typ = int.from_bytes(e[2:4], "big" if big else "little")
            num = int.from_bytes(e[4:8], "big" if big else "little")
            size = _TYPE_SIZE.get(typ, 1) * num
            payload = e[8:12] if size <= 4 else reader.read_at(
                tiff_off + int.from_bytes(e[8:12], "big" if big else "little"), min(size, 65535)
            )

            if tag in (0x8769, 0x8825):
                if size >= 4:
                    sub = int.from_bytes(payload[:4], "big" if big else "little")
                    queue.append((sub, depth + 1))
                continue

            name = _TAG_NAME.get(tag)
            if name is None or name in out:
                continue

            if typ in (2, 7):  # ASCII / UNDEFINED
                txt = payload.split(b"\x00")[0]
                try:
                    out[name] = txt.decode("utf-8", errors="ignore").strip()
                except Exception:
                    out[name] = ""
            elif typ in (1, 3, 4):
                w = _TYPE_SIZE[typ]
                if size >= w and payload:
                    out[name] = str(int.from_bytes(payload[:w], "big" if big else "little"))
            elif typ in (5, 9, 10):
                if len(payload) >= 8:
                    num_v = int.from_bytes(payload[:4], "big" if big else "little")
                    den_v = int.from_bytes(payload[4:8], "big" if big else "little") or 1
                    out[name] = str(num_v / den_v)

    return out


def _scan_tiff_magic(reader: _Reader, limit: int = 4 << 20) -> List[int]:
    """暴力扫描 TIFF 头（用于 HEIC 等不便定位的容器）。"""
    data = reader.read_at(0, min(limit, reader.size))
    hits: List[int] = []
    for magic in (b"Exif\x00\x00", b"II*\x00", b"MM\x00*"):
        start = 0
        while True:
            i = data.find(magic, start)
            if i < 0:
                break
            hits.append(i + (6 if magic.startswith(b"Exif") else 0))
            start = i + 1
            if len(hits) > 8:
                break
    return hits


# --------------------------------------------------------------------------
# ISOBMFF（MP4 / MOV / HEIC / AVIF）
# --------------------------------------------------------------------------

_FULL_BOXES = {b"meta", b"iinf", b"iloc", b"pitm", b"keys", b"hdlr", b"dref", b"stsd"}


def _iter_boxes(reader: _Reader, start: int, end: int):
    off = start
    guard = 0
    while off + 8 <= end and guard < 4096:
        guard += 1
        hdr = reader.read_at(off, 8)
        if len(hdr) < 8:
            return
        size = int.from_bytes(hdr[0:4], "big")
        typ = hdr[4:8]
        header = 8
        if size == 1:
            big = reader.read_at(off + 8, 8)
            if len(big) < 8:
                return
            size = int.from_bytes(big, "big")
            header = 16
        elif size == 0:
            size = end - off
        if size < header or off + size > end:
            return
        yield typ, off + header, off + size
        off += size


def _find_boxes(reader: _Reader, start: int, end: int, path: List[bytes], depth: int = 0):
    """深度优先查找指定路径的 box，yield (path, content_start, content_end)。"""
    if depth > 8:
        return
    for typ, cs, ce in _iter_boxes(reader, start, end):
        if path and typ != path[0]:
            continue
        rest = path[1:] if path else []
        if not rest:
            yield typ, cs, ce
        else:
            inner_start = cs + 4 if typ in _FULL_BOXES else cs
            for item in _find_boxes(reader, inner_start, ce, rest, depth + 1):
                yield item


def _parse_time_box(reader: _Reader, cs: int) -> Optional[_dt.datetime]:
    """解析 mvhd / mdhd 的创建时间。"""
    vf = reader.read_at(cs, 4)
    if len(vf) < 4:
        return None
    version = vf[0]
    if version == 1:
        raw = reader.read_at(cs + 4, 8)
        if len(raw) < 8:
            return None
        secs = int.from_bytes(raw, "big")
    else:
        raw = reader.read_at(cs + 4, 4)
        if len(raw) < 4:
            return None
        secs = int.from_bytes(raw, "big")
    if secs <= 0 or secs > 0xFFFFFFFF:
        return None
    try:
        dt = EPOCH_1904 + _dt.timedelta(seconds=secs)
    except Exception:
        return None
    # 明显早于 1970 的当作无效值
    if dt.year < 1970 or dt.year > 2200:
        return None
    return to_local_naive(dt)


def _parse_mdhd(reader: _Reader, cs: int) -> Optional[_dt.datetime]:
    return _parse_time_box(reader, cs)


def _parse_keys(reader: _Reader, cs: int, ce: int) -> List[str]:
    names: List[str] = []
    vf = reader.read_at(cs, 4)
    if len(vf) < 4:
        return names
    version = vf[0]
    off = cs + 4
    if version >= 1:
        cnt = reader.u32(off)
        off += 4
    else:
        b = reader.read_at(off, 2)
        cnt = int.from_bytes(b, "big") if len(b) == 2 else 0
        off += 2
    if not cnt or cnt > 1024:
        return names
    for _ in range(cnt):
        if off + 8 > ce:
            break
        size = reader.u32(off)
        if not size or size < 8:
            break
        raw = reader.read_at(off + 8, size - 8)
        names.append(raw.decode("utf-8", errors="ignore"))
        off += size
    return names


def _parse_ilst(reader: _Reader, cs: int, ce: int, keys: Optional[List[str]] = None) -> Dict[str, str]:
    """从 ilst 里取出字符串型元数据（如 com.apple.quicktime.creationdate / ©day）。"""
    out: Dict[str, str] = {}
    for typ, ics, ice in _iter_boxes(reader, cs, ce):
        label = None
        idx = int.from_bytes(typ, "big")
        if keys and 1 <= idx <= len(keys):
            label = keys[idx - 1]
        else:
            label = typ.decode("latin-1", errors="ignore")
        for dtyp, dcs, dce in _iter_boxes(reader, ics, ice):
            if dtyp != b"data":
                continue
            head = reader.read_at(dcs, 8)
            if len(head) < 8:
                continue
            payload = reader.read_at(dcs + 8, min(dce - dcs - 8, 512))
            if not payload:
                continue
            try:
                txt = payload.decode("utf-8", errors="ignore").strip()
            except Exception:
                continue
            if txt and label not in out:
                out[label] = txt
    return out


@dataclass
class IsoResult:
    created_by: Optional[_dt.datetime] = None
    created_str: str = ""
    mvhd: Optional[_dt.datetime] = None
    mdhd: Optional[_dt.datetime] = None
    ilst: Dict[str, str] = field(default_factory=dict)
    duration_s: Optional[float] = None
    handler: str = ""
    exif: Dict[str, str] = field(default_factory=dict)


def parse_isobmff(reader: _Reader, deep_exif: bool = True) -> IsoResult:
    res = IsoResult()
    top = list(_iter_boxes(reader, 0, reader.size))

    moov: Optional[Tuple[int, int]] = None
    meta_top: Optional[Tuple[int, int]] = None
    for typ, cs, ce in top:
        if typ == b"moov" and moov is None:
            moov = (cs, ce)
        elif typ == b"meta" and meta_top is None:
            meta_top = (cs, ce)

    # ---- moov 内的时间 ----
    if moov:
        mcs, mce = moov
        for typ, cs, ce in _iter_boxes(reader, mcs, mce):
            if typ == b"mvhd" and res.mvhd is None:
                res.mvhd = _parse_time_box(reader, cs)
            elif typ == b"trak":
                for t2, c2, e2 in _iter_boxes(reader, cs, ce):
                    if t2 != b"mdia":
                        continue
                    for t3, c3, e3 in _iter_boxes(reader, c2, e2):
                        if t3 == b"mdhd" and res.mdhd is None:
                            res.mdhd = _parse_mdhd(reader, c3)
                        elif t3 == b"hdlr" and not res.handler:
                            raw = reader.read_at(c3 + 8, 4)
                            res.handler = raw.decode("latin-1", errors="ignore").strip()

        # ilst（两种位置：moov/meta 与 moov/udta/meta）
        keys: List[str] = []
        for mp, mcs2, mce2 in _find_boxes(reader, mcs, mce, [b"meta"]):
            inner = mcs2 + 4
            for kp, kcs, kce in _iter_boxes(reader, inner, mce2):
                if kp == b"keys":
                    keys = _parse_keys(reader, kcs, kce)
            for ip, ics, ice in _iter_boxes(reader, inner, mce2):
                if ip == b"ilst":
                    res.ilst.update(_parse_ilst(reader, ics, ice, keys))
        for mp, mcs2, mce2 in _find_boxes(reader, mcs, mce, [b"udta", b"meta"]):
            inner = mcs2 + 4
            for ip, ics, ice in _iter_boxes(reader, inner, mce2):
                if ip == b"ilst":
                    res.ilst.update(_parse_ilst(reader, ics, ice, keys))

        # duration
        try:
            for typ, cs, ce in _iter_boxes(reader, mcs, mce):
                if typ != b"mvhd":
                    continue
                vf = reader.read_at(cs, 4)
                if vf and vf[0] == 1:
                    ts = reader.u32(cs + 20) or 0
                    dur = int.from_bytes(reader.read_at(cs + 24, 8), "big")
                else:
                    ts = reader.u32(cs + 12) or 0
                    dur = reader.u32(cs + 16) or 0
                if ts:
                    res.duration_s = dur / ts
                break
        except Exception:
            pass

    # ---- creationdate 字符串 ----
    for key in sorted(res.ilst.keys()):
        if "creationdate" in key.lower() or key in ("\xa9day", "\xa9DAY"):
            res.created_str = res.ilst[key]
            break

    # ---- HEIC / AVIF：从 meta 里找 Exif item ----
    if deep_exif and meta_top and res.created_str == "" and res.mvhd is None:
        res.exif = _heic_exif(reader, meta_top[0], meta_top[1])

    return res


def _heic_exif(reader: _Reader, meta_start: int, meta_end: int) -> Dict[str, str]:
    """在 HEIC/AVIF 的 meta box 中定位 Exif item 并解析。"""
    inner = meta_start + 4
    item_ids: Dict[int, str] = {}
    iloc: Dict[int, Tuple[int, int]] = {}

    for typ, cs, ce in _iter_boxes(reader, inner, meta_end):
        if typ == b"iinf":
            vf = reader.read_at(cs, 4)
            if len(vf) < 4:
                continue
            off = cs + 4
            if vf[0] >= 1:
                cnt = reader.u32(off) or 0
                off += 4
            else:
                b = reader.read_at(off, 2)
                cnt = int.from_bytes(b, "big") if len(b) == 2 else 0
                off += 2
            for _ in range(min(cnt, 512)):
                for ityp, ics, ice in _iter_boxes(reader, off, ce):
                    if ityp != b"infe":
                        continue
                    hd = reader.read_at(ics, 12)
                    if len(hd) < 12:
                        continue
                    ver = hd[0]
                    if ver >= 2:
                        iid = int.from_bytes(hd[4:6], "big")
                        itype = hd[8:12].decode("latin-1", errors="ignore").strip()
                    else:
                        iid = int.from_bytes(hd[4:6], "big")
                        itype = "?" + hd[8:12].decode("latin-1", errors="ignore").strip()
                    item_ids[iid] = itype.strip()
                    off = ice
                    break
                else:
                    break
        elif typ == b"iloc":
            iloc = _parse_iloc(reader, cs, ce)

    for iid, itype in item_ids.items():
        if itype.lower() != "exif" or iid not in iloc:
            continue
        off, length = iloc[iid]
        if off <= 0 or length <= 8 or off + length > reader.size:
            continue
        # payload 前 4 字节是到 TIFF 头的偏移
        hdr = reader.read_at(off, 4)
        if len(hdr) < 4:
            continue
        delta = int.from_bytes(hdr, "big")
        tiff_off = off + 4 + delta
        if not 0 < delta < 4096:
            tiff_off = off + 4
        for cand in (tiff_off, off + 4, off + 6, off):
            try:
                got = parse_tiff(reader, cand)
                if got:
                    return got
            except Exception:
                continue

    # 兜底：暴力扫描
    for cand in _scan_tiff_magic(reader):
        try:
            got = parse_tiff(reader, cand)
            if got.get("DateTimeOriginal") or got.get("DateTime"):
                return got
        except Exception:
            continue
    return {}


def _parse_iloc(reader: _Reader, cs: int, ce: int) -> Dict[int, Tuple[int, int]]:
    """解析 iloc，返回 {item_id: (绝对偏移, 长度)}（仅支持 construction_method=0）。"""
    out: Dict[int, Tuple[int, int]] = {}
    vf = reader.read_at(cs, 4)
    if len(vf) < 4:
        return out
    version = vf[0]
    off = cs + 4
    b = reader.read_at(off, 2)
    if len(b) < 2:
        return out
    sizes = b[0]
    if version < 2:
        b2 = reader.read_at(off + 2, 2)
        if len(b2) < 2:
            return out
        cnt = int.from_bytes(b2, "big")
        off += 4
    else:
        cnt = reader.u32(off + 2) or 0
        off += 6

    offset_size = sizes >> 4
    length_size = sizes & 0xF
    b3 = reader.read_at(off, 2)
    if len(b3) < 2:
        return out
    base_offset_size = b3[0] >> 4
    index_size = b3[1] if version in (1, 2) else 0
    off += 2

    def take(n: int) -> int:
        nonlocal off
        if n == 0:
            return 0
        raw = reader.read_at(off, n)
        off += n
        return int.from_bytes(raw, "big")

    for _ in range(min(cnt, 1024)):
        if off >= ce:
            break
        if version < 2:
            iid = take(2)
        else:
            iid = take(4)
        if version in (1, 2):
            take(2)  # construction_method
        take(2)  # data_reference_index
        base_offset = take(base_offset_size)
        ext_count = take(2)
        for _e in range(min(ext_count, 8)):
            if index_size:
                take(index_size)
            eoff = take(offset_size)
            elen = take(length_size)
            if eoff and elen and iid not in out:
                out[iid] = (base_offset + eoff, elen)
    return out


# --------------------------------------------------------------------------
# 各容器格式的定位
# --------------------------------------------------------------------------

def _read_head(reader: _Reader, n: int = 64) -> bytes:
    return reader.read_at(0, min(n, reader.size))


def detect_kind(reader: _Reader) -> str:
    """按魔数判断真实格式（比扩展名可靠）。"""
    h = _read_head(reader, 32)
    if len(h) < 4:
        return "unknown"
    if h[:2] == b"\xff\xd8":
        return "jpeg"
    if h[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if h[:4] == b"RIFF" and h[8:12] == b"WEBP":
        return "webp"
    if h[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if h[:2] in (b"II", b"MM") and len(h) >= 4 and h[2:4] in (b"*\x00", b"\x00*"):
        return "tiff"
    if h[:4] in (b"\x00\x00\x00\x18", b"\x00\x00\x00\x1c", b"\x00\x00\x00\x20") or h[4:8] in (
        b"ftyp", b"moov", b"mdat", b"free", b"wide", b"skip", b"styp",
    ):
        brand = h[8:12] if len(h) >= 12 else b""
        if brand in (b"heic", b"heix", b"hevc", b"hevx", b"mif1", b"msf1", b"heim", b"heis"):
            return "heic"
        if brand in (b"avif", b"avis"):
            return "avif"
        return "isobmff"
    if h[:4] == b"\x1a\x45\xdf\xa3":
        return "matroska"
    if h[:4] == b"RIFF" and h[8:12] == b"AVI ":
        return "avi"
    return "unknown"


def read_jpeg(reader: _Reader) -> Tuple[Dict[str, str], str]:
    """返回 (EXIF 标签, XMP 文本)。"""
    exif: Dict[str, str] = {}
    xmp = ""
    off = 2
    guard = 0
    while off + 4 <= reader.size and guard < 512:
        guard += 1
        b = reader.read_at(off, 4)
        if len(b) < 4:
            break
        if b[0] != 0xFF:
            off += 1
            continue
        marker = b[1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            off += 2
            continue
        if marker == 0xDA:  # SOS，之后是压缩数据
            break
        seg_len = int.from_bytes(b[2:4], "big")
        if seg_len < 2:
            break
        body_off = off + 4
        body_len = seg_len - 2
        if marker == 0xE1:
            head = reader.read_at(body_off, 32)
            if head[:6] == b"Exif\x00\x00":
                try:
                    exif = parse_tiff(reader, body_off + 6)
                except Exception:
                    pass
            elif head[:28].lower().startswith(b"http://ns.adobe.com/xap/1.0/"):
                xmp = reader.read_at(body_off + 29, min(body_len - 29, 1 << 20)).decode("utf-8", errors="ignore")
        off += 2 + seg_len
    return exif, xmp


def read_png(reader: _Reader) -> Tuple[Dict[str, str], str, Optional[_dt.datetime]]:
    exif: Dict[str, str] = {}
    xmp = ""
    ttime: Optional[_dt.datetime] = None
    off = 8
    guard = 0
    while off + 8 <= reader.size and guard < 2048:
        guard += 1
        hdr = reader.read_at(off, 8)
        if len(hdr) < 8:
            break
        length = int.from_bytes(hdr[0:4], "big")
        ctype = hdr[4:8]
        data_off = off + 8
        if length > reader.size:
            break
        if ctype == b"tIME" and length >= 7:
            d = reader.read_at(data_off, 7)
            try:
                ttime = _dt.datetime(
                    int.from_bytes(d[0:2], "big"), d[2], d[3], d[4], d[5], min(d[6], 59)
                )
            except Exception:
                ttime = None
        elif ctype in (b"iTXt", b"tEXt") and not xmp:
            raw = reader.read_at(data_off, min(length, 1 << 20))
            i = raw.find(b"<x:xmpmeta")
            if i >= 0:
                xmp = raw[i:].decode("utf-8", errors="ignore")
        elif ctype == b"eXIf":
            try:
                exif = parse_tiff(reader, data_off)
            except Exception:
                pass
        if ctype == b"IEND":
            break
        off = data_off + length + 4
    return exif, xmp, ttime


def read_webp(reader: _Reader) -> Tuple[Dict[str, str], str]:
    exif: Dict[str, str] = {}
    xmp = ""
    off = 12
    guard = 0
    while off + 8 <= reader.size and guard < 256:
        guard += 1
        hdr = reader.read_at(off, 8)
        if len(hdr) < 8:
            break
        ctype = hdr[0:4]
        length = int.from_bytes(hdr[4:8], "little")
        data_off = off + 8
        if length > reader.size:
            break
        if ctype == b"EXIF":
            head = reader.read_at(data_off, 8)
            base = data_off + 6 if head[:6] == b"Exif\x00\x00" else data_off
            try:
                exif = parse_tiff(reader, base)
            except Exception:
                pass
        elif ctype == b"XMP ":
            xmp = reader.read_at(data_off, min(length, 1 << 20)).decode("utf-8", errors="ignore")
        off = data_off + length + (length & 1)
    return exif, xmp


# --------------------------------------------------------------------------
# XMP
# --------------------------------------------------------------------------

_XMP_RX = [
    re.compile(r'xmp:CreateDate\s*=\s*"([^"]+)"', re.I),
    re.compile(r"<xmp:CreateDate>\s*([^<]+?)\s*</xmp:CreateDate>", re.I),
    re.compile(r'photoshop:DateCreated\s*=\s*"([^"]+)"', re.I),
    re.compile(r"<photoshop:DateCreated>\s*([^<]+?)\s*</photoshop:DateCreated>", re.I),
    re.compile(r'xmp:DateCreated\s*=\s*"([^"]+)"', re.I),
    re.compile(r'<exif:DateTimeOriginal>\s*([^<]+?)\s*</exif:DateTimeOriginal>', re.I),
]


def parse_xmp_for_date(text: str) -> Optional[_dt.datetime]:
    if not text:
        return None
    for rx in _XMP_RX:
        m = rx.search(text)
        if m:
            dt = parse_datetime_any(m.group(1))
            if dt:
                return dt
    return None


# --------------------------------------------------------------------------
# 旁车文件（sidecar）
# --------------------------------------------------------------------------

def sidecar_paths(p: Path) -> Tuple[Optional[Path], Optional[Path]]:
    """返回 (xmp旁车, takeout json旁车)。"""
    xmp = None
    for cand in (p.with_suffix(p.suffix + ".xmp"), p.with_suffix(".xmp")):
        if cand.exists():
            xmp = cand
            break
    js = None
    for cand in (p.with_suffix(p.suffix + ".json"), p.with_suffix(".json")):
        if cand.exists() and cand != p:
            js = cand
            break
    return xmp, js


def parse_takeout_json_for_date(path: Path) -> Optional[_dt.datetime]:
    try:
        obj = json.loads(path.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        return None
    if not isinstance(obj, dict):
        return None
    # Google Takeout 结构
    for key in ("photoTakenTime", "creationTime", "modificationTime"):
        node = obj.get(key)
        if isinstance(node, dict) and node.get("timestamp"):
            try:
                return _dt.datetime.fromtimestamp(int(node["timestamp"]))
            except Exception:
                pass
    # 有些变体直接放 ISO 字符串
    for key in ("dateTaken", "captureDate", "date", "timestamp"):
        v = obj.get(key)
        if isinstance(v, str):
            dt = parse_datetime_any(v)
            if dt:
                return dt
        elif isinstance(v, (int, float)):
            try:
                return _dt.datetime.fromtimestamp(int(v))
            except Exception:
                pass
    return None


# --------------------------------------------------------------------------
# 文件名解析（Deep 模式）
# --------------------------------------------------------------------------

_TS_END = r"(?=$|[_\-. \)\[（(])"

FILENAME_PATTERNS: List[Tuple[str, re.Pattern]] = [
    ("DJI Fly", re.compile(r"DJI[_-]?FLY[_-]((?:19|20)\d{6})[_-](\d{6})" + _TS_END, re.I)),
    ("DJI", re.compile(r"DJI[_-]((?:19|20)\d{6})[_-](\d{6})" + _TS_END, re.I)),
    ("IMG_/VID_", re.compile(r"(?:IMG|VID)[-_]?((?:19|20)\d{6})[_-](\d{6})" + _TS_END, re.I)),
    ("PXL/微信/相机", re.compile(r"(?:PXL|MVIMG|mmexport|wx_camera)[_-]?((?:19|20)\d{6})[_-]?(\d{6})?" + _TS_END, re.I)),
    ("通用 YYYYMMDD_HHMMSS", re.compile(r"((?:19|20)\d{6})[_-](\d{6})" + _TS_END)),
    # 连续 14 位：IMG_20200101000000 / 微信、QQ 导出常见
    ("连续 YYYYMMDDHHMMSS", re.compile(r"((?:19|20)\d{12})" + _TS_END)),
    ("通用 YYYY-MM-DD_HH-MM-SS",
     re.compile(r"((?:19|20)\d{2})[-_.](\d{2})[-_.](\d{2})[ _T-](\d{2})[-_.:](\d{2})[-_.:](\d{2})" + _TS_END)),
    ("WhatsApp IMG", re.compile(r"IMG-((?:19|20)\d{6})-WA\d+" + _TS_END, re.I)),
    ("WhatsApp VID", re.compile(r"VID-((?:19|20)\d{6})-WA\d+" + _TS_END, re.I)),
    ("中文日期", re.compile(r"((?:19|20)\d{2})年(\d{1,2})月(\d{1,2})日")),
    ("截图", re.compile(r"(?:Screenshot|屏幕快照|截屏)[ _-]*((?:19|20)\d{2})[-_.]?(\d{2})[-_.]?(\d{2})[ _-]*(\d{2})?[-_.:]?(\d{2})?[-_.:]?(\d{2})?", re.I)),
]

UUID_STEM_RX = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I
)
HASH_STEM_RX = re.compile(r"^[0-9a-f]{16,}$", re.I)


def parse_date_from_filename(name: str) -> Tuple[Optional[_dt.datetime], str]:
    base = Path(name).stem
    if UUID_STEM_RX.match(base) or HASH_STEM_RX.match(base):
        return None, "missing"
    for label, rx in FILENAME_PATTERNS:
        m = rx.search(base)
        if not m:
            continue
        g = m.groups()
        try:
            if label in ("DJI Fly", "DJI", "IMG_/VID_", "通用 YYYYMMDD_HHMMSS"):
                return _dt.datetime.strptime(g[0] + (g[1] or "000000"), "%Y%m%d%H%M%S"), f"文件名·{label}"
            if label == "连续 YYYYMMDDHHMMSS":
                dt = _dt.datetime.strptime(g[0], "%Y%m%d%H%M%S")
                if not (1990 <= dt.year <= 2100):
                    continue
                return dt, f"文件名·{label}"
            if label == "PXL/微信/相机":
                ymd = g[0]
                hms = g[1] if len(g) > 1 and g[1] else "000000"
                return _dt.datetime.strptime(ymd + hms, "%Y%m%d%H%M%S"), f"文件名·{label}"
            if label == "通用 YYYY-MM-DD_HH-MM-SS":
                return _dt.datetime(int(g[0]), int(g[1]), int(g[2]), int(g[3]), int(g[4]), int(g[5])), f"文件名·{label}"
            if label in ("WhatsApp IMG", "WhatsApp VID"):
                return _dt.datetime.strptime(g[0], "%Y%m%d"), f"文件名·{label}"
            if label == "中文日期":
                return _dt.datetime(int(g[0]), int(g[1]), int(g[2])), f"文件名·{label}"
            if label == "截图":
                y, mo, d = int(g[0]), int(g[1]), int(g[2])
                hh = int(g[3]) if g[3] else 0
                mm = int(g[4]) if g[4] else 0
                ss = int(g[5]) if g[5] else 0
                return _dt.datetime(y, mo, d, hh, mm, ss), f"文件名·{label}"
        except Exception:
            continue
    return None, "missing"


# --------------------------------------------------------------------------
# exiftool 增强层（可选）
# --------------------------------------------------------------------------

EXIFTOOL_TAGS = [
    "EXIF:DateTimeOriginal", "EXIF:CreateDate", "EXIF:ModifyDate",
    "XMP:CreateDate", "XMP:DateCreated", "XMP:MetadataDate",
    "QuickTime:CreateDate", "QuickTime:MediaCreateDate",
    "QuickTime:TrackCreateDate", "QuickTime:ContentCreateDate",
    "QuickTime:CreationDate", "Keys:CreationDate",
    "Composite:SubSecDateTimeOriginal", "Composite:DateTimeCreated",
    "PNG:CreationTime", "RIFF:DateTimeOriginal",
    "DateTimeOriginal", "CreateDate", "MediaCreateDate", "CreationDate",
]


class ExifTool:
    """可选增强：系统装了 exiftool 就用它批量提取，覆盖度更高。"""

    def __init__(self) -> None:
        self.cmd: Optional[str] = None
        self.version = ""
        self._probe()

    def _probe(self) -> None:
        for cand in ("exiftool", "/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"):
            try:
                p = subprocess.run([cand, "-ver"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                   timeout=10, check=False)
                if p.returncode == 0:
                    self.cmd = cand
                    self.version = p.stdout.decode(errors="ignore").strip()
                    return
            except Exception:
                continue

    @property
    def available(self) -> bool:
        return self.cmd is not None

    def info(self) -> str:
        return f"exiftool v{self.version}" if self.available else "未检测到（使用内置解析器）"

    def batch(self, paths: List[str]) -> Dict[str, Dict[str, str]]:
        if not self.cmd or not paths:
            return {}
        out: Dict[str, Dict[str, str]] = {}
        chunk = 120
        for i in range(0, len(paths), chunk):
            part = paths[i: i + chunk]
            args = [self.cmd, "-j", "-G", "-s", "-charset", "utf8"]
            args += ["-" + t for t in EXIFTOOL_TAGS]
            args += part
            try:
                p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                   timeout=180, check=False)
                arr = json.loads(p.stdout.decode("utf-8", errors="replace") or "[]")
            except Exception:
                continue
            for d in arr if isinstance(arr, list) else []:
                sf = str(d.get("SourceFile") or "")
                if sf:
                    out[os.path.normpath(sf)] = d
        return out


# --------------------------------------------------------------------------
# 主入口
# --------------------------------------------------------------------------

@dataclass
class ReadOptions:
    use_exiftool: bool = True
    parse_filename: bool = True
    read_xmp_sidecar: bool = True
    read_takeout_json: bool = True
    fallback: str = "skip"          # skip | created | modified
    deep_exif: bool = True


@dataclass
class Probe:
    dt: Optional[_dt.datetime] = None
    source: str = "缺失"
    exif: Dict[str, str] = field(default_factory=dict)
    duration_s: Optional[float] = None
    kind: str = ""
    note: str = ""


def _exiftool_dt(md: Dict[str, str]) -> Tuple[Optional[_dt.datetime], str, str]:
    for tag in EXIFTOOL_TAGS:
        v = md.get(tag)
        if not v:
            continue
        dt = parse_datetime_any(v)
        if dt:
            # 秒以下精度
            for sk in ("EXIF:SubSecTimeOriginal", "SubSecTimeOriginal", "EXIF:SubSecTimeDigitized"):
                if md.get(sk):
                    dt = _apply_subsec(dt, md[sk])
                    break
            return dt, f"exiftool·{tag}", str(v)
    return None, "", ""


def probe_file(path: Path, opts: ReadOptions, exiftool_md: Optional[Dict[str, str]] = None) -> Probe:
    """对单个文件求最佳拍摄时间。"""
    res = Probe()
    try:
        with _Reader(path=path) as rd:
            kind = detect_kind(rd)
            res.kind = kind

            # ---- 0) exiftool 优先 ----
            if opts.use_exiftool and exiftool_md:
                dt, src, raw = _exiftool_dt(exiftool_md)
                if dt:
                    res.dt, res.source = dt, src
                    res.exif = {k.split(":")[-1]: str(v) for k, v in exiftool_md.items()
                                if not k.startswith("SourceFile")}
                    return res

            # ---- 1) 容器内嵌 ----
            if kind in ("isobmff", "heic", "avif"):
                iso = parse_isobmff(rd, deep_exif=opts.deep_exif)
                res.duration_s = iso.duration_s
                for key in sorted(iso.ilst.keys()):
                    if "creationdate" in key.lower() or key in ("\xa9day", "\xa9DAY"):
                        dt = parse_datetime_any(iso.ilst[key])
                        if dt:
                            res.dt, res.source = dt, f"内嵌·{key.strip() or '元数据'}"
                            res.exif.update(iso.exif)
                            return res
                if iso.mvhd:
                    res.dt, res.source = iso.mvhd, "内嵌·mvhd 创建时间"
                    res.exif.update(iso.exif)
                    return res
                if iso.mdhd:
                    res.dt, res.source = iso.mdhd, "内嵌·mdhd 媒体创建时间"
                    return res
                if iso.exif:
                    dt = _exif_dict_dt(iso.exif)
                    if dt[0]:
                        res.dt, res.source, res.exif = dt[0], "内嵌·HEIF Exif", iso.exif
                        res.note = dt[1]
                        return res

            # ---- 2) JPEG ----
            elif kind == "jpeg":
                exif, xmp = read_jpeg(rd)
                res.exif = exif
                if xmp:
                    dt = parse_xmp_for_date(xmp)
                    if dt:
                        res.dt, res.source = dt, "内嵌·XMP"
                        return res
                dt, note = _exif_dict_dt(exif)
                if dt:
                    res.dt, res.source, res.note = dt, "内嵌·EXIF", note
                    return res

            # ---- 3) PNG ----
            elif kind == "png":
                exif, xmp, ttime = read_png(rd)
                res.exif = exif
                if xmp:
                    dt = parse_xmp_for_date(xmp)
                    if dt:
                        res.dt, res.source = dt, "内嵌·XMP"
                        return res
                dt, note = _exif_dict_dt(exif)
                if dt:
                    res.dt, res.source, res.note = dt, "内嵌·eXIf", note
                    return res
                if ttime:
                    res.dt, res.source = ttime, "内嵌·PNG tIME"
                    return res

            # ---- 4) WebP ----
            elif kind == "webp":
                exif, xmp = read_webp(rd)
                res.exif = exif
                if xmp:
                    dt = parse_xmp_for_date(xmp)
                    if dt:
                        res.dt, res.source = dt, "内嵌·XMP"
                        return res
                dt, note = _exif_dict_dt(exif)
                if dt:
                    res.dt, res.source, res.note = dt, "内嵌·EXIF", note
                    return res

            # ---- 5) TIFF 系（含 RAW）----
            elif kind == "tiff":
                try:
                    exif = parse_tiff(rd, 0)
                except Exception:
                    exif = {}
                res.exif = exif
                dt, note = _exif_dict_dt(exif)
                if dt:
                    res.dt, res.source, res.note = dt, "内嵌·EXIF", note
                    return res

        # ---- 6) 旁车文件 ----
        if opts.read_takeout_json:
            xmp_p, js_p = sidecar_paths(path)
            if js_p is not None:
                dt = parse_takeout_json_for_date(js_p)
                if dt:
                    res.dt, res.source = dt, "旁车·Google Takeout JSON"
                    return res
        if opts.read_xmp_sidecar:
            xmp_p, _ = sidecar_paths(path)
            if xmp_p is not None:
                try:
                    dt = parse_xmp_for_date(xmp_p.read_text(encoding="utf-8", errors="ignore"))
                except Exception:
                    dt = None
                if dt:
                    res.dt, res.source = dt, "旁车·XMP"
                    return res

        # ---- 7) 文件名 ----
        if opts.parse_filename:
            dt, src = parse_date_from_filename(path.name)
            if dt:
                res.dt, res.source = dt, src
                return res

        # ---- 8) 文件系统兜底 ----
        st = path.stat()
        if opts.fallback == "created":
            ts = getattr(st, "st_birthtime", st.st_ctime)
            res.dt, res.source = _dt.datetime.fromtimestamp(ts), "文件系统·创建时间"
            return res
        if opts.fallback == "modified":
            res.dt, res.source = _dt.datetime.fromtimestamp(st.st_mtime), "文件系统·修改时间"
            return res

        res.source = "缺失"
        res.note = _missing_hint(path)
        return res

    except Exception as e:  # noqa: BLE001
        res.source = "缺失"
        res.note = f"读取失败：{type(e).__name__}"
        return res


def _exif_dict_dt(exif: Dict[str, str]) -> Tuple[Optional[_dt.datetime], str]:
    """按优先级从 EXIF 字典取时间。"""
    if not exif:
        return None, ""
    order = ["DateTimeOriginal", "DateTimeDigitized", "DateTime"]
    for key in order:
        if not exif.get(key):
            continue
        dt = parse_datetime_any(exif[key])
        if not dt:
            continue
        off_key = {"DateTimeOriginal": "OffsetTimeOriginal",
                   "DateTimeDigitized": "OffsetTimeDigitized",
                   "DateTime": "OffsetTime"}[key]
        sub_key = {"DateTimeOriginal": "SubSecTimeOriginal",
                   "DateTimeDigitized": "SubSecTimeDigitized",
                   "DateTime": "SubSecTime"}[key]
        off = exif.get(off_key)
        if off:
            try:
                m = TZ_RX.search(off.strip())
                if m:
                    sign = 1 if m.group(1) == "+" else -1
                    minutes = sign * (int(m.group(2)) * 60 + int(m.group(3)))
                    dt = to_local_naive(dt.replace(tzinfo=_dt.timezone(_dt.timedelta(minutes=minutes))))
            except Exception:
                pass
        dt = _apply_subsec(dt, exif.get(sub_key))
        note = f"{key}={exif[key]}"
        if off:
            note += f" 时区={off}"
        return dt, note
    return None, ""


def _missing_hint(path: Path) -> str:
    stem = path.stem
    if UUID_STEM_RX.match(stem):
        return "文件名是 UUID 格式，通常表示已被导出/处理过，元数据可能被剥离；可开启「文件时间兜底」"
    if HASH_STEM_RX.match(stem):
        return "文件名是哈希串，常见于聊天软件导出，元数据多已剥离"
    if stem.isdigit() and len(stem) >= 8:
        return "文件名是纯数字编号，不含日期信息，且文件内没有可用元数据；可开启「文件时间兜底」或跳过"
    return ""


# --------------------------------------------------------------------------
# 文件名生成
# --------------------------------------------------------------------------

PATTERN_CHOICES = ["仅日期", "日期_原名", "仅原名", "原名_日期"]


def format_new_name(dt: Optional[_dt.datetime], original_name: str, fmt: str,
                    prefix: str, suffix: str, pattern: str) -> Optional[str]:
    base, ext = os.path.splitext(original_name)
    if pattern == "仅原名":
        return f"{prefix}{base}{suffix}{ext}"
    if dt is None:
        return None
    try:
        stamp = dt.strftime(fmt)
    except Exception:
        stamp = ""
    if not stamp:
        return None
    if pattern == "日期_原名":
        return f"{prefix}{stamp}_{base}{suffix}{ext}"
    if pattern == "原名_日期":
        return f"{prefix}{base}_{stamp}{suffix}{ext}"
    return f"{prefix}{stamp}{suffix}{ext}"


def safe_rename_target(folder: Path, filename: str, used: set,
                       ignore: Optional[set] = None) -> str:
    """冲突时自动加 _1 _2 …，保证目标名唯一。

    ignore 里的完整路径表示"不算占用"——用于排除：
      · 文件自己（目标名 == 当前名时应当判定为"无需改动"）
      · 本轮即将被改名腾出的旧文件名
    """
    ignore = ignore or set()

    def taken(name: str) -> bool:
        if name in used:
            return True
        full = folder / name
        if not full.exists():
            return False
        return str(full) not in ignore

    if not taken(filename):
        used.add(filename)
        return filename
    stem, ext = os.path.splitext(filename)
    i = 1
    while True:
        cand = f"{stem}_{i}{ext}"
        if not taken(cand):
            used.add(cand)
            return cand
        i += 1


def is_media(path: Path) -> bool:
    return path.suffix.lower() in MEDIA_EXTS


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024.0
    return f"{n:.1f} TB"


def python_info() -> str:
    return f"Python {sys.version.split()[0]}"
