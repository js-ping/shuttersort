#!/usr/bin/env python3
"""命名引擎的参考实现 —— **只给测试用，不是产品代码**。

原先是 `src/server.py` 里的一小部分（本地 HTTP 服务那一整套已经随 Windows/Linux 版
一起删掉了）。`native/tests/pydump.py` 要靠它产出「Python 版会给出什么答案」，
再和 Swift 版逐字段比对。保存下来是为了守住一件事：

    原生版的解析与命名，必须和跑了两年的 Python 实现给出完全一样的结果。

抽出来的只有三样：遍历文件、算目标文件名、exiftool 批量调用。
任何一处改动都应该先问问「Swift 版那边是不是也该改」。
"""
from __future__ import annotations

import datetime as _dt
import sys
from pathlib import Path
from typing import Any, Dict, List

sys.path.insert(0, str(Path(__file__).resolve().parent))

from media_time import (            # noqa: E402
    ExifTool, format_new_name, is_media, safe_rename_target,
)

EXIFTOOL = ExifTool()


def iter_files(folder: Path, recursive: bool, only_media: bool):
    """遍历目录。跳过隐藏文件、旁车文件（.xmp/.json/.aae/.txt）和非媒体文件。"""
    try:
        it = folder.rglob("*") if recursive else folder.iterdir()
    except Exception:
        return
    for p in it:
        try:
            if not p.is_file():
                continue
            if p.name.startswith("."):
                continue
            if p.suffix.lower() in (".xmp", ".json", ".aae", ".txt"):
                continue
            if only_media and not is_media(p):
                continue
            yield p
        except Exception:
            continue


def build_plan(rows: List[Dict[str, Any]], opts: Dict[str, Any]) -> List[Dict[str, Any]]:
    """根据扫描结果计算目标文件名（服务端权威计算，前端传参不改结果）。"""
    fmt = (opts.get("format") or "%Y%m%d_%H%M%S").strip() or "%Y%m%d_%H%M%S"
    prefix = opts.get("prefix") if opts.get("prefix") is not None else "IMG_"
    suffix = opts.get("suffix") or ""
    pattern = opts.get("pattern") or "仅日期"
    archive = bool(opts.get("archive"))
    archive_fmt = (opts.get("archiveFormat") or "%Y/%Y-%m").strip() or "%Y/%Y-%m"
    only_renamable = bool(opts.get("onlyRenamable", True))

    # 时间校正：相机时区设错、出国忘了调时钟，整批整体平移。
    # 只作用于「算新文件名」这一步，绝不回写文件里的元数据 —— 那是另一个量级的风险。
    try:
        offset = int(opts.get("offsetSeconds") or 0)
    except (TypeError, ValueError):
        offset = 0
    if abs(offset) > 86400 * 3660:      # ±10 年，再夸张就当作误输入
        offset = 0
    shift = _dt.timedelta(seconds=offset)

    used: Dict[str, set] = {}
    plan: List[Dict[str, Any]] = []

    # 第一轮：算出每个文件的目标目录与目标名，并记录哪些旧名字会被腾出来
    staged: List[tuple] = []
    vacating: set = set()
    for r in rows:
        src = Path(r["path"])
        dt = None
        # 优先用带亚秒的 tsIso：连拍校正之后要保住先后关系。
        for raw_ts, pat in ((r.get("tsIso"), "%Y-%m-%d %H:%M:%S.%f"),
                            (r.get("ts"), "%Y-%m-%d %H:%M:%S")):
            if not raw_ts:
                continue
            try:
                dt = _dt.datetime.strptime(raw_ts, pat)
                break
            except Exception:
                dt = None
        if dt is not None and offset:
            dt = dt + shift

        new_name = format_new_name(dt, r["name"], fmt, prefix, suffix, pattern)
        target_dir = src.parent
        if new_name and archive and dt:
            try:
                sub = dt.strftime(archive_fmt)
                if sub:
                    target_dir = src.parent / sub
            except Exception:
                target_dir = src.parent
        staged.append((r, new_name, target_dir, dt))
        if new_name and not (new_name == src.name and target_dir == src.parent):
            vacating.add(str(src))

    # 第二轮：消解冲突（排除文件自身与本轮腾出的旧名，保证重复执行结果一致）
    for r, new_name, target_dir, dt in staged:
        src = Path(r["path"])
        item = dict(r)
        # 校正后的时间单独带一份；ts / tsIso 保留原始值，便于对照「改之前是多少」。
        if dt is not None:
            shifted_ts = dt.strftime("%Y-%m-%d %H:%M:%S")
            if dt.microsecond:
                shifted_ts += ".%06d" % dt.microsecond
        else:
            shifted_ts = r.get("ts") or ""
        item["tsShifted"] = shifted_ts
        if new_name is None:
            item.update({"newName": "", "targetDir": str(target_dir), "status": "skip",
                         "statusText": "跳过（无时间戳）", "conflict": ""})
            if not only_renamable:
                plan.append(item)
            continue

        key = str(target_dir)
        used.setdefault(key, set())
        ignore = set(vacating)
        ignore.add(str(src))
        uniq = safe_rename_target(target_dir, new_name, used[key], ignore)
        conflict = "" if uniq == new_name else "重名加后缀"
        unchanged = (uniq == src.name and target_dir == src.parent)
        item.update({
            "newName": uniq,
            "targetDir": str(target_dir),
            "status": "same" if unchanged else "ok",
            "statusText": "无需改动" if unchanged else "待改名",
            "conflict": conflict,
        })
        plan.append(item)

    plan.sort(key=lambda x: (x["status"] != "ok", x.get("tsShifted") or ""))
    return plan
