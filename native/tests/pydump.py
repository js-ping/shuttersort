#!/usr/bin/env python3
"""和 native 版的 dump 输出同构 JSON，用于对照。

刻意不复用 server.py 的 _run_scan（它带线程池和 job 状态），
这里直接调 probe_file + build_plan，保证两边比的是同一层语义。
"""
import argparse
import json
import os
import sys
from pathlib import Path

# 默认按本文件位置反推仓库（native/tests/pydump.py → 仓库根），
# 这样仓库换了位置、被 clone 到别的机器上都不用改代码。
REPO = Path(os.environ.get(
    "SHUTTERSORT_REPO",
    str(Path(__file__).resolve().parents[2])))
if not (REPO / "src" / "media_time.py").exists():
    sys.exit(f"找不到仓库：{REPO}（用 SHUTTERSORT_REPO 指定）")
sys.path.insert(0, str(REPO / "src"))

import media_time as mt          # noqa: E402
import server                    # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir")
    ap.add_argument("--file", action="append", default=[])
    ap.add_argument("--format", default="%Y%m%d_%H%M%S")
    ap.add_argument("--prefix", default="IMG_")
    ap.add_argument("--suffix", default="")
    ap.add_argument("--pattern", default="仅日期")
    ap.add_argument("--archive", action="store_true")
    ap.add_argument("--archive-format", default="%Y/%Y-%m")
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--no-recursive", action="store_true")
    ap.add_argument("--all-files", action="store_true")
    ap.add_argument("--no-exiftool", action="store_true")
    ap.add_argument("--no-filename", action="store_true")
    ap.add_argument("--fallback", default="skip")
    a = ap.parse_args()

    if a.file:
        files = [Path(p) for p in a.file]
    elif a.dir:
        files = list(server._iter_files(Path(a.dir),
                                        not a.no_recursive,
                                        not a.all_files))
    else:
        sys.exit("需要 --dir 或 --file")

    opts = mt.ReadOptions(
        use_exiftool=not a.no_exiftool and server.EXIFTOOL.available,
        parse_filename=not a.no_filename,
        read_xmp_sidecar=True,
        read_takeout_json=True,
        fallback=a.fallback,
        deep_exif=True,
    )

    files.sort(key=lambda p: str(p).lower())

    exif_map = {}
    if opts.use_exiftool and files:
        exif_map = server.EXIFTOOL.batch([str(p) for p in files])

    rows = []
    for p in files:
        try:
            st = p.stat()
            size = st.st_size
            mtime = st.st_mtime
        except Exception:
            size, mtime = 0, 0.0
        pr = mt.probe_file(p, opts, exif_map.get(os.path.normpath(str(p))))
        rows.append({
            "path": str(p),
            "dir": str(p.parent),
            "name": p.name,
            "ext": p.suffix.lower(),
            "size": size,
            "sizeText": mt.human_size(size),
            "mtime": mtime,
            "ts": pr.dt.strftime("%Y-%m-%d %H:%M:%S") if pr.dt else "",
            "tsIso": pr.dt.isoformat(sep=" ") if pr.dt else "",
            "source": pr.source,
            "kind": pr.kind,
            "note": pr.note,
            "duration": round(pr.duration_s, 1) if pr.duration_s else None,
            "exif": pr.exif,
        })

    rows.sort(key=lambda r: (r["tsIso"] or "9999", r["mtime"] or 0, r["name"].lower()))

    plan = server.build_plan(rows, {
        "format": a.format,
        "prefix": a.prefix,
        "suffix": a.suffix,
        "pattern": a.pattern,
        "archive": a.archive,
        "archiveFormat": a.archive_format,
        "offsetSeconds": a.offset,
        "onlyRenamable": False,
    })

    out = {
        "rows": [{
            "path": r["path"], "name": r["name"], "ts": r["ts"],
            "tsIso": r["tsIso"], "source": r["source"],
            "kind": r["kind"], "size": r["size"],
        } for r in rows],
        "plan": [{
            "path": x["path"], "name": x["name"], "newName": x["newName"],
            "targetDir": x["targetDir"], "status": x["status"],
            "conflict": x["conflict"], "tsShifted": x.get("tsShifted", ""),
        } for x in plan],
    }
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()
