"""拍摄时间改名器（ShutterSort）· 本地后端服务

只监听 127.0.0.1，不对外网开放，不联网、不上传任何数据。
所有文件读写都在你本机完成。

三种运行方式：
  · macOS / Linux 源码模式：双击 start.command，或 python3 src/server.py
  · Windows 源码模式：双击 start.bat
  · 打包模式：双击 ShutterSort.app（macOS）/ ShutterSort.exe（Windows），
    打包入口是 src/app_main.py，会开原生窗口而不是浏览器标签页。
"""

from __future__ import annotations

import base64
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


def _user_state_dir() -> Path:
    """跨平台的「用户数据目录」，用来放撤销记录和运行日志。

    macOS   → ~/Library/Application Support/ShutterSort
    Windows → %APPDATA%\\ShutterSort
    Linux   → $XDG_DATA_HOME/ShutterSort（默认 ~/.local/share/ShutterSort）
    """
    home = Path.home()
    if sys.platform == "darwin":
        return home / "Library" / "Application Support" / "ShutterSort"
    if sys.platform.startswith("win"):
        base = os.environ.get("APPDATA") or os.environ.get("LOCALAPPDATA")
        return (Path(base) if base else home / "AppData" / "Roaming") / "ShutterSort"
    xdg = os.environ.get("XDG_DATA_HOME")
    return (Path(xdg) if xdg else home / ".local" / "share") / "ShutterSort"


if FROZEN:
    # 打包后：静态资源在 sys._MEIPASS，用户数据写到系统标准的用户目录
    BASE = Path(getattr(sys, "_MEIPASS", Path(sys.executable).resolve().parent))
    ROOT = Path(sys.executable).resolve().parent
    STATE = _user_state_dir()
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
    """双击启动时进程的 PATH 往往极简，补上几个常见目录，
    这样 ffmpeg / exiftool / magick 这些「可选增强工具」才找得到。

    注意：这些工具全都不是必需的，缺了也能跑 —— 内置解析器已经覆盖常用格式。"""
    if sys.platform.startswith("win"):
        sysroot = os.environ.get("SystemRoot") or r"C:\Windows"
        progfiles = os.environ.get("ProgramFiles") or r"C:\Program Files"
        extra = [
            str(Path(sysroot) / "System32"),
            str(Path(sysroot) / "System32" / "WindowsPowerShell" / "v1.0"),
            str(Path(progfiles) / "ffmpeg" / "bin"),
            r"C:\ffmpeg\bin",
        ]
    elif sys.platform == "darwin":
        extra = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
                 "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    else:
        extra = ["/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
                 "/snap/bin"]
    parts = [p for p in (os.environ.get("PATH") or "").split(os.pathsep) if p]
    for p in extra:
        if p and p not in parts and Path(p).is_dir():
            parts.append(p)
    os.environ["PATH"] = os.pathsep.join(parts)


def pick_folder_windows(start: str = "") -> str:
    """Windows 原生「选择文件夹」对话框。

    Windows 没有 osascript，用 PowerShell 调 .NET 的 FolderBrowserDialog 顶上。
    中文路径直接拼进命令行会被代码页转坏，所以脚本用 base64(UTF-16LE) 经
    -EncodedCommand 传过去，彻底绕开编码问题。

    返回选中的路径；用户取消、或系统里找不到 PowerShell 时返回空字符串。
    """
    ps = (shutil.which("powershell") or shutil.which("powershell.exe")
          or shutil.which("pwsh") or shutil.which("pwsh.exe"))
    if not ps:
        return ""
    probe = ""
    try:
        if start and os.path.isdir(start):
            probe = start
    except Exception:
        probe = ""
    script = (
        "Add-Type -AssemblyName System.Windows.Forms | Out-Null\n"
        "$dlg = New-Object System.Windows.Forms.FolderBrowserDialog\n"
        "$dlg.Description = '请选择要整理的文件夹'\n"
        "$dlg.ShowNewFolderButton = $true\n"
        + (("$dlg.SelectedPath = '%s'\n" % probe.replace("'", "''")) if probe else "")
        + "if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) "
          "{ [Console]::Out.Write($dlg.SelectedPath) }\n"
    )
    enc = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    try:
        r = subprocess.run(
            [ps, "-NoProfile", "-NonInteractive", "-STA", "-EncodedCommand", enc],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600, check=False,
        )
        if r.returncode == 0:
            return r.stdout.decode("utf-8", "replace").strip()
    except Exception as e:
        log("Windows 选择框失败：%s" % e)
    return ""


def pick_files_windows(start: str = "") -> List[str]:
    """Windows 原生「选择文件」对话框（可多选）。

    和选文件夹一样，脚本走 base64(UTF-16LE) + -EncodedCommand，
    避免中文路径被控制台代码页转坏。返回绝对路径列表。
    """
    ps = (shutil.which("powershell") or shutil.which("powershell.exe")
          or shutil.which("pwsh") or shutil.which("pwsh.exe"))
    if not ps:
        return []
    probe = ""
    try:
        if start and os.path.isdir(start):
            probe = start
    except Exception:
        probe = ""
    script = (
        "Add-Type -AssemblyName System.Windows.Forms | Out-Null\n"
        "$dlg = New-Object System.Windows.Forms.OpenFileDialog\n"
        "$dlg.Title = '选择要处理的照片或视频'\n"
        "$dlg.Multiselect = $true\n"
        "$dlg.Filter = '媒体文件|*.jpg;*.jpeg;*.png;*.heic;*.heif;*.webp;*.gif;*.bmp;*.tif;*.tiff;"
        "*.mp4;*.mov;*.m4v;*.avi;*.mkv;*.3gp|所有文件|*.*'\n"
        + (("$dlg.InitialDirectory = '%s'\n" % probe.replace("'", "''")) if probe else "")
        + "if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) "
          "{ $dlg.FileNames | ForEach-Object { [Console]::Out.WriteLine($_) } }\n"
    )
    enc = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    try:
        r = subprocess.run(
            [ps, "-NoProfile", "-NonInteractive", "-STA", "-EncodedCommand", enc],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600, check=False,
        )
        if r.returncode == 0:
            return [x.strip() for x in r.stdout.decode("utf-8", "replace").splitlines() if x.strip()]
    except Exception as e:
        log("Windows 选文件失败：%s" % e)
    return []


def _bookmarks() -> List[Path]:
    """界面上「快速跳转」的那一排位置（不存在的不显示）。"""
    home = Path.home()
    items = [home, home / "Desktop", home / "Downloads", home / "Pictures"]
    if sys.platform.startswith("win"):
        items += [home / "Videos", home / "OneDrive"]
        for letter in "DEFGHIJ":                      # 其余盘符
            d = Path("%s:\\" % letter)
            if d.exists():
                items.append(d)
    elif sys.platform == "darwin":
        items += [home / "Movies", Path("/Volumes")]
    else:
        items += [home / "Videos", Path("/media"), Path("/mnt")]
    seen, out = set(), []
    for p in items:
        key = str(p).rstrip("\\/") or str(p)
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


def platform_label() -> str:
    if sys.platform == "darwin":
        return "macOS"
    if sys.platform.startswith("win"):
        return "Windows"
    return "Linux"


def native_picker_available() -> bool:
    """当前环境能不能弹出「系统原生」的选文件夹对话框。"""
    if PICK_FOLDER_HOOK is not None:
        return True
    if sys.platform == "darwin":
        return shutil.which("osascript") is not None
    if sys.platform.startswith("win"):
        return bool(shutil.which("powershell") or shutil.which("pwsh"))
    return bool(shutil.which("zenity") or shutil.which("kdialog"))


_augment_path()
ensure_dir(RUNLOG)
ensure_dir(STATE)

sys.path.insert(0, str(BASE))
from media_time import (  # noqa: E402
    ExifTool, ReadOptions, format_new_name, is_media, probe_file,
    safe_rename_target, human_size, python_info,
)

APP_TITLE = "拍摄时间改名器"
APP_NAME_EN = "ShutterSort"
VERSION = "1.4.0"

# 由 app_main.py 注入：App 模式下用原生窗口关闭程序 / 弹系统选择框
QUIT_HOOK: Optional[Callable[[], None]] = None
PICK_FOLDER_HOOK: Optional[Callable[[str], str]] = None
# 选文件（可多选），返回绝对路径列表；空列表表示用户取消
PICK_FILES_HOOK: Optional[Callable[[str], List[str]]] = None

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
        # 两种来源：扫一个文件夹，或者只是用户点名的那几个文件。
        # 点名模式下不再按扩展名过滤 —— 用户自己挑的，就该出现在列表里；
        # 真的没有时间戳的会以「无时间戳」出现，比"选了却没反应"清楚。
        picked = job.get("files") or []
        if picked:
            files = []
            for raw in picked:
                p = Path(raw)
                try:
                    if p.is_file() and not p.name.startswith("."):
                        files.append(p)
                except OSError:
                    continue
        else:
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

    # 按时间排，同秒时再用亚秒、文件 mtime、文件名兜底 —— 连拍（同一秒好几张）
    # 的顺序才跟快门一致，_1 _2 的编号也才不会随目录顺序漂移。
    # tsIso 是定宽 ISO，字典序就是时间序；没有时间的用 "9999" 沉到最后。
    rows.sort(key=lambda r: (r["tsIso"] or "9999", r["mtime"] or 0, r["name"].lower()))
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
    staged: List[Tuple[Dict[str, Any], Optional[str], Path, Optional[_dt.datetime]]] = []
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
        # 校正后的时间单独带一份，界面用它显示、也用它排序；
        # ts / tsIso 保留原始值，便于对照「改之前是多少」。
        # 亚秒跟着一起带出来 —— 连拍在校正后仍然看得出先后。
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
        # newName 存的已经是消解后的最终名，这里再说一遍名字就成了「X → X」的自指
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
                    "titleEn": APP_NAME_EN,
                    "version": VERSION,
                    "python": python_info(),
                    "exiftool": EXIFTOOL.info(),
                    "exiftoolAvailable": EXIFTOOL.available,
                    "ffmpeg": shutil.which("ffmpeg") is not None,
                    "platform": sys.platform,
                    "platformLabel": platform_label(),
                    "nativePicker": native_picker_available(),
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
            if path == "/api/pick-files":
                return self._pick_files()
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
        books = [{"name": (x.name or str(x)), "path": str(x)}
                 for x in _bookmarks() if x.exists()]
        return self._json({
            "ok": True,
            "current": str(p),
            "parent": str(p.parent) if p.parent != p else None,
            "dirs": dirs,
            "books": books,
        })

    def _pick_folder(self):
        """弹出「选择文件夹」，各平台走各自的原生方式。

        统一约定：用户取消 / 系统不支持 → 返回空路径（前端会退回到手动输入框）。
        """
        body = self._body()
        start = body.get("start") or str(Path.home())

        # App 模式：pywebview 的原生对话框（macOS 的 NSOpenPanel 最稳，不会有权限弹窗）
        if PICK_FOLDER_HOOK is not None:
            try:
                picked = PICK_FOLDER_HOOK(start)
                return self._json({"ok": True, "path": picked or "", "supported": True})
            except Exception as e:
                log("原生选择框失败：%s" % e)

        if sys.platform == "darwin":
            script = (f'POSIX path of (choose folder with prompt "选择要整理的文件夹" '
                      f'default location POSIX file "{start}")')
            try:
                p = subprocess.run(["osascript", "-e", script], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, timeout=300, check=False)
                if p.returncode == 0:
                    return self._json({"ok": True, "supported": True,
                                       "path": p.stdout.decode().strip().rstrip("/")})
                return self._json({"ok": True, "path": "", "supported": True})
            except Exception as e:
                return self._err(f"调用系统选择框失败：{e}")

        if sys.platform.startswith("win"):
            try:
                return self._json({"ok": True, "supported": True,
                                   "path": pick_folder_windows(start)})
            except Exception as e:
                return self._err(f"调用系统选择框失败：{e}")

        # Linux：有 zenity / kdialog 就用，都没有就明说「不支持」，
        # 让前端提示用户直接把路径粘到输入框里（功能一点不少）。
        for tool, args in (("zenity", ["--file-selection", "--directory", "--title=选择要整理的文件夹"]),
                           ("kdialog", ["--getexistingdirectory", start])):
            if shutil.which(tool):
                try:
                    p = subprocess.run([tool] + args, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, timeout=300, check=False)
                    if p.returncode == 0:
                        return self._json({"ok": True, "supported": True,
                                           "path": p.stdout.decode().strip()})
                    return self._json({"ok": True, "path": "", "supported": True})
                except Exception as e:
                    return self._err(f"调用系统选择框失败：{e}")
        return self._json({"ok": True, "path": "", "supported": False})

    def _pick_files(self):
        """弹出「选择文件」（可多选），返回绝对路径数组。

        用户取消 → 空数组。系统不支持 → supported: false，前端提示改用拖拽/手输。
        """
        body = self._body()
        start = body.get("start") or str(Path.home())

        if PICK_FILES_HOOK is not None:
            try:
                got = PICK_FILES_HOOK(start)
                return self._json({"ok": True, "paths": list(got or []), "supported": True})
            except Exception as e:
                log("原生选文件失败：%s" % e)

        if sys.platform == "darwin":
            script = (
                'set theFiles to choose file with prompt "选择要处理的照片或视频" '
                'with multiple selections allowed\n'
                'set out to ""\n'
                'repeat with f in theFiles\n'
                '  set out to out & (POSIX path of f) & linefeed\n'
                'end repeat\n'
                'return out'
            )
            try:
                p = subprocess.run(["osascript", "-e", script], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, timeout=600, check=False)
                if p.returncode != 0:
                    return self._json({"ok": True, "paths": [], "supported": True})
                lines = [x.strip() for x in p.stdout.decode("utf-8", "replace").splitlines()]
                return self._json({"ok": True, "supported": True,
                                   "paths": [x for x in lines if x]})
            except Exception as e:
                return self._err(f"调用系统选择框失败：{e}")

        if sys.platform.startswith("win"):
            try:
                return self._json({"ok": True, "supported": True,
                                   "paths": pick_files_windows(start)})
            except Exception as e:
                return self._err(f"调用系统选择框失败：{e}")

        if shutil.which("zenity"):
            try:
                p = subprocess.run(
                    ["zenity", "--file-selection", "--multiple",
                     "--separator=\n", "--title=选择要处理的文件"],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600, check=False)
                if p.returncode == 0:
                    lines = [x.strip() for x in p.stdout.decode("utf-8", "replace").splitlines()]
                    return self._json({"ok": True, "supported": True,
                                       "paths": [x for x in lines if x]})
                return self._json({"ok": True, "paths": [], "supported": True})
            except Exception as e:
                return self._err(f"调用系统选择框失败：{e}")
        return self._json({"ok": True, "paths": [], "supported": False})

    # ---------- 扫描 ----------
    def _scan_start(self):
        """开始扫描。两种来源：

        - 传 `folder`：扫这个目录（可递归），老行为
        - 传 `files`：只处理点名的这些文件，来自「选择文件」或拖拽
        """
        body = self._body()
        picked = body.get("files")

        if picked is not None:
            if not isinstance(picked, list):
                return self._err("files 必须是数组")
            paths: List[str] = []
            for raw in picked:
                try:
                    p = Path(str(raw)).expanduser()
                    if p.is_file():
                        paths.append(str(p.resolve()))
                except (OSError, ValueError):
                    continue
            paths = list(dict.fromkeys(paths))          # 拖拽时可能重复
            if not paths:
                return self._err("这些路径里没有可读取的文件（如果拖进来的是文件夹，"
                                 "请用「选择文件夹」）")
            if len(paths) == 1:
                folder = str(Path(paths[0]).parent)
            else:
                try:
                    folder = os.path.commonpath([str(Path(x).parent) for x in paths])
                except ValueError:                      # Windows 跨盘符，没有公共父目录
                    folder = ""
            seed = "|".join(paths)
        else:
            folder = (body.get("folder") or "").strip()
            if not folder:
                return self._err("请先选择文件夹")
            fp = Path(folder).expanduser()
            if not fp.exists() or not fp.is_dir():
                return self._err(f"目录不存在：{fp}")
            folder = str(fp)
            paths = []
            seed = folder

        job_id = hashlib.md5(f"{seed}{time.time()}".encode()).hexdigest()[:12]
        job = {
            "id": job_id,
            "folder": folder,
            "files": paths,
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
            "mode": "files" if job.get("files") else "folder",
            "fileCount": len(job.get("files") or []),
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

        # 只处理用户勾选的那些文件。
        # 关键：拿前端的路径去跟扫描结果求交集，而不是直接信任 —— 否则等于
        # 给了一个"重命名本机任意文件"的接口。
        only = body.get("paths")
        if only is not None:
            if not isinstance(only, list):
                return self._err("paths 必须是数组")
            wanted = {str(p) for p in only}
            plan = [x for x in plan if x["path"] in wanted]
            if not plan:
                return self._err("没有选中任何文件")

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
        """HEIC/HEIF 缩略图。

        浏览器基本都不认 HEIC，所以得借外部工具转一张 JPEG 出来：
        macOS 自带 sips；Windows / Linux 上装了 ImageMagick（magick）或 ffmpeg 也行。
        三个都没有就返回 415，界面会显示占位图标 —— 不影响改名。
        """
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
            if not done and shutil.which("magick"):
                try:
                    r = subprocess.run(["magick", str(p), "-resize", "320x320", str(out)],
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
    # Windows 打包成「无控制台」的 exe 时，stdout/stderr 会是 None，
    # 直接 print 会抛异常 —— 先补一个黑洞流顶上。
    for name in ("stdout", "stderr"):
        if getattr(sys, name, None) is None:
            try:
                setattr(sys, name, open(os.devnull, "w", encoding="utf-8"))
            except Exception:
                pass
    # Windows 的终端默认是 GBK，中文会变乱码 —— 强制用 UTF-8 输出
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]
        except Exception:
            pass

    try:
        httpd, port = make_server()
    except RuntimeError as e:
        print(e)
        return 1
    url = f"http://127.0.0.1:{port}/"

    print("=" * 58)
    print(f"  {APP_TITLE}  ( {APP_NAME_EN} )  v{VERSION}")
    print(f"  平台：{platform_label()}   ·   {python_info()}")
    print("=" * 58)
    print(f"  界面地址：{url}")
    print(f"  exiftool：{EXIFTOOL.info()}")
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
