"""ShutterSort · 本地后端服务

只监听 127.0.0.1，不对外网开放，不联网、不上传任何数据。
所有文件读写都在你本机完成。

两种运行方式：
  · 源码模式：./start.command，或 python3 src/server.py
  · 打包模式：双击 ShutterSort.app（入口是 src/app_main.py）
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import json
import mimetypes
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

# --------------------------------------------------------------------------
# 运行环境适配（源码运行 / PyInstaller 打包运行）
# --------------------------------------------------------------------------

FROZEN = bool(getattr(sys, "frozen", False))

if FROZEN:
    # 打包后：静态资源在 sys._MEIPASS，用户数据写到 ~/Library/Application Support
    BASE = Path(getattr(sys, "_MEIPASS", Path(sys.executable).resolve().parent))
    ROOT = Path(sys.executable).resolve().parent
    STATE = Path.home() / "Library" / "Application Support" / "ShutterSort"
else:
    BASE = Path(__file__).resolve().parent
    ROOT = BASE.parent
    STATE = ROOT

STATIC = BASE / "static"
RUNLOG = STATE / "rename-history"
LOGFILE = STATE / "runtime.log"


def ensure_dir(p: Path) -> Path:
    """稳妥地创建目录：已存在或创建失败都不应让程序崩溃。"""
    try:
        if not p.is_dir():
            p.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    return p


def log(msg: str) -> None:
    """把异常/事件写进日志文件（App 模式没有终端，只能靠文件排查）。"""
    try:
        ensure_dir(LOGFILE.parent)
        with open(LOGFILE, "a", encoding="utf-8") as f:
            f.write(f"[{_dt.datetime.now():%Y-%m-%d %H:%M:%S}] {msg}\n")
    except Exception:
        pass


def _augment_path() -> None:
    """从 Finder 双击启动时 PATH 极简，补上 Homebrew 等常见目录，
    这样 ffmpeg / exiftool / sips 这些外部增强工具才找得到。"""
    extra = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
             "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    parts = [p for p in (os.environ.get("PATH") or "").split(os.pathsep) if p]
    for p in extra:
        if p not in parts and Path(p).is_dir():
            parts.append(p)
    os.environ["PATH"] = os.pathsep.join(parts)


_augment_path()
ensure_dir(RUNLOG)
ensure_dir(STATE)

sys.path.insert(0, str(BASE))
from media_time import (  # noqa: E402
    ExifTool, ReadOptions, format_new_name, is_media, probe_file,
    safe_rename_target, human_size, python_info,
)

APP_TITLE = "ShutterSort"
VERSION = "1.0.0"

# 由 app_main.py 注入：App 模式下用原生窗口关闭程序 / 弹系统选择框
QUIT_HOOK: Optional[Callable[[], None]] = None
PICK_FOLDER_HOOK: Optional[Callable[[str], str]] = None

EXIFTOOL = ExifTool()
THUMB_DIR = Path(tempfile.gettempdir()) / "mt_renamer_thumbs"
ensure_dir(THUMB_DIR)

_JOBS: Dict[str, Dict[str, Any]] = {}
_JOBS_LOCK = threading.Lock()


# ==========================================================================
# 扫描任务
# ==========================================================================

def _iter_files(folder: Path, recursive: bool, only_media: bool):
    try:
        it = folder.rglob("*") if recursive else folder.iterdir()
    except Exception:
        return
    for p in it:
        try:
            if not p.is_file():
                continue
            name = p.name
            if name.startswith("."):
                continue
            if p.suffix.lower() in (".xmp", ".json", ".aae", ".txt"):
                continue
            if only_media and not is_media(p):
                continue
            yield p
        except Exception:
            continue


def _run_scan(job: Dict[str, Any]) -> None:
    folder = Path(job["folder"])
    opts = ReadOptions(
        use_exiftool=job["use_exiftool"] and EXIFTOOL.available,
        parse_filename=job["parse_filename"],
        read_xmp_sidecar=job["read_xmp_sidecar"],
        read_takeout_json=job["read_takeout_json"],
        fallback=job["fallback"],
        deep_exif=True,
    )

    try:
        files = list(_iter_files(folder, job["recursive"], job["only_media"]))
    except Exception as e:
        job["error"] = f"读取目录失败：{e}"
        job["done"] = True
        return

    files.sort(key=lambda p: str(p).lower())
    job["total"] = len(files)

    exif_map: Dict[str, Dict[str, str]] = {}
    if opts.use_exiftool and files:
        job["stage"] = "正在用 exiftool 批量读取元数据…"
        try:
            exif_map = EXIFTOOL.batch([str(p) for p in files])
        except Exception:
            exif_map = {}
    job["stage"] = "正在解析每个文件…"

    workers = min(16, max(4, (os.cpu_count() or 4) * 2))
    rows: List[Dict[str, Any]] = []

    def work(p: Path) -> Dict[str, Any]:
        try:
            st = p.stat()
            size = st.st_size
            mtime = st.st_mtime
        except Exception:
            size, mtime = 0, 0.0
        pr = probe_file(p, opts, exif_map.get(os.path.normpath(str(p))))
        return {
            "path": str(p),
            "dir": str(p.parent),
            "name": p.name,
            "ext": p.suffix.lower(),
            "size": size,
            "sizeText": human_size(size),
            "mtime": mtime,
            "ts": pr.dt.strftime("%Y-%m-%d %H:%M:%S") if pr.dt else "",
            "tsIso": pr.dt.isoformat(sep=" ") if pr.dt else "",
            "source": pr.source,
            "kind": pr.kind,
            "note": pr.note,
            "duration": round(pr.duration_s, 1) if pr.duration_s else None,
            "exif": pr.exif,
        }

    with ThreadPoolExecutor(max_workers=workers) as pool:
        for i, row in enumerate(pool.map(work, files), 1):
            if job["cancel"]:
                break
            rows.append(row)
            job["rows"] = rows
            job["processed"] = i

    rows.sort(key=lambda r: (r["ts"] or "9999"), reverse=False)
    job["rows"] = rows
    job["stage"] = "完成"
    job["done"] = True
    job["finished_at"] = time.time()


# ==========================================================================
# 改名执行
# ==========================================================================

def build_plan(rows: List[Dict[str, Any]], opts: Dict[str, Any]) -> List[Dict[str, Any]]:
    """根据扫描结果重新计算目标文件名（服务端权威计算，前端传参不改结果）。"""
    fmt = (opts.get("format") or "%Y%m%d_%H%M%S").strip() or "%Y%m%d_%H%M%S"
    prefix = opts.get("prefix") if opts.get("prefix") is not None else "IMG_"
    suffix = opts.get("suffix") or ""
    pattern = opts.get("pattern") or "仅日期"
    archive = bool(opts.get("archive"))
    archive_fmt = (opts.get("archiveFormat") or "%Y/%Y-%m").strip() or "%Y/%Y-%m"
    only_renamable = bool(opts.get("onlyRenamable", True))

    used: Dict[str, set] = {}
    plan: List[Dict[str, Any]] = []

    # 第一轮：算出每个文件的目标目录与目标名，并记录哪些旧名字会被腾出来
    staged: List[Tuple[Dict[str, Any], Optional[str], Path, Optional[_dt.datetime]]] = []
    vacating: set = set()
    for r in rows:
        src = Path(r["path"])
        dt = None
        if r.get("ts"):
            try:
                dt = _dt.datetime.strptime(r["ts"], "%Y-%m-%d %H:%M:%S")
            except Exception:
                dt = None

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
        conflict = "" if uniq == new_name else f"重名 → {uniq}"
        unchanged = (uniq == src.name and target_dir == src.parent)
        item.update({
            "newName": uniq,
            "targetDir": str(target_dir),
            "status": "same" if unchanged else "ok",
            "statusText": "无需改动" if unchanged else "待改名",
            "conflict": conflict,
        })
        plan.append(item)

    plan.sort(key=lambda x: (x["status"] != "ok", x.get("ts") or ""))
    return plan


def _write_undo_log(pairs: List[Dict[str, str]], meta: Dict[str, Any]) -> Optional[str]:
    if not pairs:
        return None
    stamp = _dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    fn = RUNLOG / f"改名记录_{stamp}.json"
    data = {
        "time": _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "count": len(pairs),
        "meta": meta,
        "pairs": pairs,
    }
    fn.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    return fn.name


# ==========================================================================
# HTTP
# ==========================================================================

class Handler(BaseHTTPRequestHandler):
    server_version = "MediaTimeRenamer/1.0"
    protocol_version = "HTTP/1.1"

    # ---------- 工具方法 ----------
    def log_message(self, fmt, *args):  # 静音默认日志
        pass

    def _send(self, code: int, body: bytes, ctype: str = "application/json; charset=utf-8",
              extra: Optional[Dict[str, str]] = None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _json(self, obj: Any, code: int = 200):
        self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"))

    def _err(self, msg: str, code: int = 400):
        self._json({"ok": False, "error": msg}, code)

    def _body(self) -> Dict[str, Any]:
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return {}

    def _query(self) -> Dict[str, str]:
        q = urllib.parse.urlparse(self.path).query
        return {k: v[0] for k, v in urllib.parse.parse_qs(q).items()}

    # ---------- 路由 ----------
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        try:
            if path in ("/", "/index.html"):
                return self._file(STATIC / "index.html")
            if path == "/favicon.ico":
                return self._send(204, b"", "image/x-icon")
            if path.startswith("/static/"):
                rel = path[len("/static/"):]
                target = (STATIC / rel).resolve()
                if not str(target).startswith(str(STATIC.resolve())):
                    return self._err("非法路径", 403)
                return self._file(target)
            if path == "/api/info":
                return self._json({
                    "ok": True,
                    "title": APP_TITLE,
                    "version": VERSION,
                    "python": python_info(),
                    "exiftool": EXIFTOOL.info(),
                    "exiftoolAvailable": EXIFTOOL.available,
                    "ffmpeg": shutil.which("ffmpeg") is not None,
                    "platform": sys.platform,
                    "app": FROZEN,
                    "home": str(Path.home()),
                    "desktop": str(Path.home() / "Desktop"),
                    "runlog": str(RUNLOG),
                    "logfile": str(LOGFILE),
                    "cwd": str(ROOT),
                })
            if path == "/api/browse":
                return self._browse()
            if path == "/api/history":
                return self._history()
            if path == "/api/thumb":
                return self._thumb()
            if path.startswith("/api/scan/"):
                return self._scan_status(path.split("/")[3])
            if path == "/api/media":
                return self._media()
            return self._err("未知路径", 404)
        except Exception as e:
            log("GET %s 出错\n%s" % (self.path, traceback.format_exc()))
            return self._err(f"{type(e).__name__}: {e}", 500)

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        try:
            if path == "/api/pick-folder":
                return self._pick_folder()
            if path == "/api/scan":
                return self._scan_start()
            if path == "/api/cancel":
                return self._scan_cancel()
            if path == "/api/preview":
                return self._preview()
            if path == "/api/rename":
                return self._rename()
            if path == "/api/undo":
                return self._undo()
            if path == "/api/reveal":
                return self._reveal()
            if path == "/api/quit":
                self._json({"ok": True})
                if QUIT_HOOK is not None:
                    threading.Thread(target=QUIT_HOOK, daemon=True).start()
                else:
                    threading.Thread(target=lambda: (time.sleep(0.3), os._exit(0)), daemon=True).start()
                return
            return self._err("未知接口", 404)
        except Exception as e:
            log("POST %s 出错\n%s" % (self.path, traceback.format_exc()))
            return self._err(f"{type(e).__name__}: {e}", 500)

    # ---------- 静态文件 ----------
    def _file(self, p: Path):
        if not p.exists() or not p.is_file():
            return self._err("文件不存在", 404)
        ctype = mimetypes.guess_type(str(p))[0] or "application/octet-stream"
        if p.suffix in (".html", ".htm"):
            ctype = "text/html; charset=utf-8"
        elif p.suffix in (".js",):
            ctype = "application/javascript; charset=utf-8"
        elif p.suffix in (".css",):
            ctype = "text/css; charset=utf-8"
        return self._send(200, p.read_bytes(), ctype)

    # ---------- 目录浏览 ----------
    def _browse(self):
        q = self._query()
        raw = q.get("path") or str(Path.home())
        p = Path(raw).expanduser()
        if not p.exists() or not p.is_dir():
            p = Path.home()
        dirs = []
        try:
            for c in sorted(p.iterdir(), key=lambda x: x.name.lower()):
                if c.is_dir() and not c.name.startswith("."):
                    try:
                        n = sum(1 for _ in c.iterdir())
                    except Exception:
                        n = -1
                    dirs.append({"name": c.name, "path": str(c), "count": n})
        except PermissionError:
            pass
        books = [{"name": x.name, "path": str(x)} for x in (
            Path.home(), Path.home() / "Desktop", Path.home() / "Downloads",
            Path.home() / "Pictures", Path.home() / "Movies", Path("/Volumes"),
        ) if x.exists()]
        return self._json({
            "ok": True,
            "current": str(p),
            "parent": str(p.parent) if p.parent != p else None,
            "dirs": dirs,
            "books": books,
        })

    def _pick_folder(self):
        body = self._body()
        start = body.get("start") or str(Path.home())
        # App 模式：优先用 pywebview 的原生 NSOpenPanel（不会有权限弹窗）
        if PICK_FOLDER_HOOK is not None:
            try:
                picked = PICK_FOLDER_HOOK(start)
                return self._json({"ok": True, "path": picked or ""})
            except Exception as e:
                log("原生选择框失败：%s" % e)
        if sys.platform == "darwin":
            script = f'POSIX path of (choose folder with prompt "选择要整理的文件夹" default location POSIX file "{start}")'
            try:
                p = subprocess.run(["osascript", "-e", script], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, timeout=300, check=False)
                if p.returncode == 0:
                    return self._json({"ok": True, "path": p.stdout.decode().strip().rstrip("/")})
                return self._json({"ok": True, "path": ""})
            except Exception as e:
                return self._err(f"调用系统选择框失败：{e}")
        return self._json({"ok": True, "path": ""})

    # ---------- 扫描 ----------
    def _scan_start(self):
        body = self._body()
        folder = (body.get("folder") or "").strip()
        if not folder:
            return self._err("请先选择文件夹")
        fp = Path(folder).expanduser()
        if not fp.exists() or not fp.is_dir():
            return self._err(f"目录不存在：{fp}")

        job_id = hashlib.md5(f"{fp}{time.time()}".encode()).hexdigest()[:12]
        job = {
            "id": job_id,
            "folder": str(fp),
            "recursive": bool(body.get("recursive", True)),
            "only_media": bool(body.get("onlyMedia", True)),
            "use_exiftool": bool(body.get("useExiftool", True)),
            "parse_filename": bool(body.get("parseFilename", True)),
            "read_xmp_sidecar": bool(body.get("readXmp", True)),
            "read_takeout_json": bool(body.get("readJson", True)),
            "fallback": body.get("fallback") or "skip",
            "rows": [],
            "total": 0,
            "processed": 0,
            "stage": "准备中…",
            "done": False,
            "cancel": False,
            "error": "",
            "started": time.time(),
        }
        with _JOBS_LOCK:
            # 旧任务标记取消
            for k, v in _JOBS.items():
                if not v["done"]:
                    v["cancel"] = True
            _JOBS[job_id] = job
        threading.Thread(target=_run_scan, args=(job,), daemon=True).start()
        return self._json({"ok": True, "job": job_id})

    def _scan_status(self, job_id: str):
        job = _JOBS.get(job_id)
        if not job:
            return self._err("任务不存在", 404)
        q = self._query()
        since = int(q.get("since") or 0)
        rows = job["rows"][since:]
        renamable = sum(1 for r in job["rows"] if r["ts"])
        return self._json({
            "ok": True,
            "job": job_id,
            "folder": job["folder"],
            "total": job["total"],
            "processed": job["processed"],
            "stage": job["stage"],
            "done": job["done"],
            "error": job["error"],
            "renamable": renamable,
            "missing": len(job["rows"]) - renamable,
            "nextIndex": since + len(rows),
            "rows": rows,
        })

    def _scan_cancel(self):
        body = self._body()
        job = _JOBS.get(body.get("job") or "")
        if job:
            job["cancel"] = True
        return self._json({"ok": True})

    # ---------- 预览（仅重算命名，不重新读元数据）----------
    def _preview(self):
        body = self._body()
        job = _JOBS.get(body.get("job") or "")
        if not job:
            return self._err("任务不存在，请重新扫描")
        plan = build_plan(job["rows"], body.get("options") or {})
        return self._json({
            "ok": True,
            "plan": plan,
            "stats": {
                "total": len(plan),
                "rename": sum(1 for x in plan if x["status"] == "ok"),
                "same": sum(1 for x in plan if x["status"] == "same"),
                "skip": sum(1 for x in plan if x["status"] == "skip"),
            },
        })

    # ---------- 执行改名 ----------
    def _rename(self):
        body = self._body()
        job = _JOBS.get(body.get("job") or "")
        if not job:
            return self._err("任务不存在，请重新扫描")
        options = body.get("options") or {}
        plan = build_plan(job["rows"], options)
        todo = [x for x in plan if x["status"] == "ok"]
        if body.get("dryRun"):
            return self._json({"ok": True, "dryRun": True, "count": len(todo), "plan": plan})

        renamed, skipped, errors = 0, 0, 0
        pairs: List[Dict[str, str]] = []
        errs: List[str] = []

        for item in plan:
            if item["status"] != "ok":
                skipped += 1
                continue
            src = Path(item["path"])
            dst_dir = Path(item["targetDir"])
            dst = dst_dir / item["newName"]
            try:
                if not src.exists():
                    skipped += 1
                    continue
                if dst.exists() and src.resolve() != dst.resolve():
                    errors += 1
                    errs.append(f"目标已存在：{dst.name}")
                    continue
                if dst_dir != src.parent:
                    ensure_dir(dst_dir)
                src.rename(dst)
                pairs.append({"from": str(src), "to": str(dst), "name": src.name})
                renamed += 1
            except Exception as e:  # noqa: BLE001
                errors += 1
                if len(errs) < 20:
                    errs.append(f"{src.name}：{e}")

        log_name = _write_undo_log(pairs, {
            "folder": job["folder"],
            "options": options,
            "renamed": renamed,
        })

        # 更新内存行，让前端不用重扫也能看到新状态
        moved = {p["from"]: p["to"] for p in pairs}
        for r in job["rows"]:
            new_path = moved.get(r["path"])
            if new_path:
                r["path"] = new_path
                r["name"] = Path(new_path).name
                r["dir"] = str(Path(new_path).parent)

        return self._json({
            "ok": True, "renamed": renamed, "skipped": skipped,
            "errors": errors, "errs": errs, "log": log_name,
        })

    # ---------- 撤销 ----------
    def _history(self):
        items = []
        for f in sorted(RUNLOG.glob("改名记录_*.json"), reverse=True)[:60]:
            try:
                d = json.loads(f.read_text(encoding="utf-8"))
                items.append({
                    "file": f.name, "time": d.get("time", ""), "count": d.get("count", 0),
                    "folder": (d.get("meta") or {}).get("folder", ""),
                    "renamed": (d.get("meta") or {}).get("renamed", 0),
                })
            except Exception:
                continue
        return self._json({"ok": True, "items": items})

    def _undo(self):
        body = self._body()
        fn = body.get("file") or ""
        if fn and "/" in fn:
            return self._err("非法文件名")
        log = RUNLOG / fn if fn else None
        if not log or not log.exists():
            logs = sorted(RUNLOG.glob("改名记录_*.json"), reverse=True)
            log = logs[0] if logs else None
        if not log or not log.exists():
            return self._err("没有可撤销的记录")

        try:
            data = json.loads(log.read_text(encoding="utf-8"))
        except Exception as e:
            return self._err(f"记录文件损坏：{e}")

        undone, failed = 0, 0
        errs: List[str] = []
        for pair in reversed(data.get("pairs", [])):
            src = Path(pair["to"])
            dst = Path(pair["from"])
            try:
                if not src.exists():
                    failed += 1
                    continue
                if dst.exists():
                    failed += 1
                    if len(errs) < 20:
                        errs.append(f"原位置已被占用：{dst.name}")
                    continue
                ensure_dir(dst.parent)
                src.rename(dst)
                undone += 1
            except Exception as e:  # noqa: BLE001
                failed += 1
                if len(errs) < 20:
                    errs.append(f"{src.name}：{e}")

        # 撤销成功后归档该记录，避免重复撤销
        if undone and not failed:
            try:
                log.rename(log.with_suffix(".json.done"))
            except Exception:
                pass
        return self._json({"ok": True, "undone": undone, "failed": failed, "errs": errs,
                           "log": log.name})

    # ---------- 缩略图 / 原图 ----------
    def _thumb(self):
        q = self._query()
        raw = q.get("path") or ""
        p = Path(raw)
        if not raw or not p.exists() or not p.is_file():
            return self._err("文件不存在", 404)
        ext = p.suffix.lower()
        if ext in (".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".heif", ".bmp"):
            if ext in (".heic", ".heif"):
                return self._heic_thumb(p)
            if p.stat().st_size > 12 * 1024 * 1024:
                return self._err("图片过大", 413)
            ctype = mimetypes.guess_type(str(p))[0] or "image/jpeg"
            return self._send(200, p.read_bytes(), ctype)
        if ext in (".mp4", ".mov", ".m4v", ".mkv", ".webm", ".avi", ".3gp", ".mts"):
            return self._video_thumb(p)
        return self._err("不支持预览", 415)

    def _video_thumb(self, p: Path):
        ff = shutil.which("ffmpeg")
        if not ff:
            return self._err("未安装 ffmpeg", 415)
        key = hashlib.md5(f"{p}{p.stat().st_mtime}".encode()).hexdigest()
        out = THUMB_DIR / f"{key}.jpg"
        if not out.exists():
            try:
                subprocess.run(
                    [ff, "-y", "-ss", "0.5", "-i", str(p), "-frames:v", "1",
                     "-vf", "scale=320:-2", "-q:v", "5", str(out)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=25, check=False,
                )
            except Exception:
                pass
        if out.exists():
            return self._send(200, out.read_bytes(), "image/jpeg")
        return self._err("无法生成缩略图", 415)

    def _heic_thumb(self, p: Path):
        for cmd in (["sips", "-s", "format", "jpeg", "-Z", "320", str(p), "--out"],
                    ):
            pass
        key = hashlib.md5(f"heic{p}{p.stat().st_mtime}".encode()).hexdigest()
        out = THUMB_DIR / f"{key}.jpg"
        if not out.exists():
            done = False
            if shutil.which("sips"):
                try:
                    r = subprocess.run(["sips", "-s", "format", "jpeg", "-Z", "320",
                                        str(p), "--out", str(out)],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       timeout=25, check=False)
                    done = r.returncode == 0 and out.exists()
                except Exception:
                    done = False
            if not done and shutil.which("ffmpeg"):
                try:
                    subprocess.run(["ffmpeg", "-y", "-i", str(p), "-frames:v", "1",
                                    "-vf", "scale=320:-2", "-q:v", "5", str(out)],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=25, check=False)
                except Exception:
                    pass
        if out.exists():
            return self._send(200, out.read_bytes(), "image/jpeg")
        return self._err("无法生成 HEIC 预览", 415)

    def _media(self):
        """原图/原视频直出（用于详情预览）。"""
        q = self._query()
        p = Path(q.get("path") or "")
        if not p.exists() or not p.is_file():
            return self._err("文件不存在", 404)
        if p.stat().st_size > 60 * 1024 * 1024:
            return self._err("文件过大", 413)
        ctype = mimetypes.guess_type(str(p))[0] or "application/octet-stream"
        return self._send(200, p.read_bytes(), ctype)

    # ---------- 在 Finder 中显示 ----------
    def _reveal(self):
        body = self._body()
        target = body.get("path") or ""
        p = Path(target)
        if not p.exists():
            return self._err("路径不存在")
        if sys.platform == "darwin":
            if p.is_dir():
                subprocess.Popen(["open", str(p)])
            else:
                subprocess.Popen(["open", "-R", str(p)])
        elif sys.platform.startswith("win"):
            if p.is_dir():
                os.startfile(str(p))  # type: ignore[attr-defined]
            else:
                subprocess.Popen(["explorer", "/select,", str(p)])
        else:
            subprocess.Popen(["xdg-open", str(p if p.is_dir() else p.parent)])
        return self._json({"ok": True})


# ==========================================================================
# 启动
# ==========================================================================

def free_port(start: int = 8787) -> int:
    for port in range(start, start + 60):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    return 0


def make_server(port: int = 0):
    """创建（但不启动）本地 HTTP 服务，返回 (httpd, port)。"""
    p = port or free_port()
    if not p:
        raise RuntimeError("找不到可用端口，请关闭一些程序后重试。")
    httpd = ThreadingHTTPServer(("127.0.0.1", p), Handler)
    httpd.daemon_threads = True
    return httpd, p


def open_browser(url: str) -> None:
    try:
        if sys.platform == "darwin":
            subprocess.Popen(["open", url])
        elif sys.platform.startswith("win"):
            os.startfile(url)  # type: ignore[attr-defined]
        else:
            subprocess.Popen(["xdg-open", url])
    except Exception:
        pass


def main() -> int:
    try:
        httpd, port = make_server()
    except RuntimeError as e:
        print(e)
        return 1
    url = f"http://127.0.0.1:{port}/"

    print("=" * 58)
    print(f"  {APP_TITLE} v{VERSION}")
    print("=" * 58)
    print(f"  界面地址：{url}")
    print(f"  {python_info()}   |   {EXIFTOOL.info()}")
    print("  数据全部在本机处理，不联网、不上传。")
    print("  关闭本窗口即退出程序。")
    print("=" * 58)

    if "--no-browser" not in sys.argv:
        threading.Thread(target=lambda: (time.sleep(0.8), open_browser(url)), daemon=True).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n已退出。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
