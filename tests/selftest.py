"""ShutterSort · 一键自检 / 回归测试

做三件事：
  1. 在临时目录里造出各种格式的样本文件（EXIF / XMP / PNG / MP4 / 旁车 / 纯文件名）
  2. 逐个验证内置解析器能否拿到预期时间
  3. 启动本地服务，跑一遍「扫描 → 预览 → 改名 → 撤销」全链路

用法：双击「run_tests.command」，或 python3 tests/selftest.py
全程在临时目录里操作，不会碰你的真实文件。
"""

from __future__ import annotations

import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROG = HERE.parent / "src"
sys.path.insert(0, str(PROG))

from media_time import (  # noqa: E402
    ExifTool, ReadOptions, format_new_name, parse_date_from_filename, probe_file,
    safe_rename_target,
)

PASS, FAIL, WARN = [], [], []


def ok(name, extra=""):
    PASS.append(name)
    print(f"  \033[32m✓\033[0m {name}" + (f"  {extra}" if extra else ""))


def bad(name, why=""):
    FAIL.append(name)
    print(f"  \033[31m✗\033[0m {name}  \033[31m{why}\033[0m")


def warn(name, why=""):
    WARN.append(name)
    print(f"  \033[33m!\033[0m {name}  {why}")


def check(name, cond, why=""):
    (ok if cond else bad)(name, "" if cond else why)


# ==========================================================================
# 样本生成
# ==========================================================================

def make_tiff(dt="2021:07:04 08:09:10", little=True):
    en = "<" if little else ">"
    head = (b"II" if little else b"MM") + struct.pack(en + "H", 42) + struct.pack(en + "I", 8)
    ifd0 = struct.pack(en + "H", 1) + struct.pack(en + "HHI", 0x8769, 4, 1) + struct.pack(en + "I", 26)
    ifd0 += struct.pack(en + "I", 0)
    raw = dt.encode() + b"\x00"
    val_off = 26 + 2 + 12 + 4
    exif = struct.pack(en + "H", 1)
    exif += struct.pack(en + "HHI", 0x9003, 2, len(raw)) + struct.pack(en + "I", val_off)
    exif += struct.pack(en + "I", 0) + raw
    return head + ifd0 + exif


def make_jpeg(dt="2021:07:04 08:09:10", xmp=None):
    tiff = make_tiff(dt)
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


def build_samples(root: Path) -> None:
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

    sub = root / "sub"
    sub.mkdir(exist_ok=True)
    (sub / "IMG_20200101000000_0001.jpg").write_bytes(b"\xff\xd8\xff\xd9")


# ==========================================================================
# 第一段：解析器单元测试
# ==========================================================================

EXPECT = {
    "photo_exif.jpg": "2021-07-04 08:09:10",
    "photo_xmp.jpg": "2019-03-05 22:33:44",
    "shot.png": "2018-11-23 07:08:09",
    "IMG_20250418_193012.jpg": "2025-04-18 19:30:12",
    "DJI_20251108_164116_0042_D.MP4": "2025-11-08 16:41:16",
    "VID-20240125-WA0007.mp4": "2024-01-25 00:00:00",
    "Screenshot 2024-09-15 at 10.20.30.jpg": "2024-09-15 00:00:00",
    "stripped.jpg": "2021-01-01 08:00:00",
    "via_xmp.mp4": "2022-02-02 02:02:02",
}


def test_parser(root: Path) -> None:
    print("\n\033[1m[1/4] 内置解析器 —— 不依赖任何外部命令\033[0m")
    opts = ReadOptions(use_exiftool=False, parse_filename=True,
                       read_xmp_sidecar=True, read_takeout_json=True, fallback="skip")
    for name, want in EXPECT.items():
        p = root / name
        r = probe_file(p, opts)
        got = r.dt.strftime("%Y-%m-%d %H:%M:%S") if r.dt else "None"
        check(f"{name} → {want}", got == want, f"实际 {got}（来源 {r.source}）")

    r = probe_file(root / "no_meta_at_all.jpg", opts)
    check("无元数据文件被正确跳过", r.dt is None and r.source == "缺失", f"实际 {r.source}")

    r = probe_file(root / "sub/IMG_20200101000000_0001.jpg", opts)
    check("子目录文件名解析", r.dt is not None and r.dt.year == 2020, str(r.dt))

    # 文件名规则表
    cases = {
        "DJI_20251108_164116_0042_D.MP4": (2025, 11, 8, 16, 41, 16),
        "DJI_FLY_20230102_030405_x.jpg": (2023, 1, 2, 3, 4, 5),
        "IMG_20250418_193012.jpg": (2025, 4, 18, 19, 30, 12),
        "20251111_184839.png": (2025, 11, 11, 18, 48, 39),
        "2025-11-08_16-41-16.mp4": (2025, 11, 8, 16, 41, 16),
        "IMG-20240125-WA0001.jpg": (2024, 1, 25, 0, 0, 0),
        "VID-20240125-WA0007.mp4": (2024, 1, 25, 0, 0, 0),
    }
    for fn, want in cases.items():
        dt, src = parse_date_from_filename(fn)
        got = (dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second) if dt else None
        check(f"文件名规则 {fn}", got == want, f"实际 {got}")

    dt, _ = parse_date_from_filename("c39d5b1e-77a4-4f2c-9c1a-1b2c3d4e5f60.png")
    check("UUID 文件名不被误判为时间", dt is None)


def test_naming() -> None:
    print("\n\033[1m[2/4] 命名规则引擎\033[0m")
    import datetime as dt
    d = dt.datetime(2024, 5, 6, 15, 30, 8)
    cases = [
        (("仅日期", "", "", "%Y-%m-%d_%H-%M-%S"), "2024-05-06_15-30-08.jpg"),
        (("日期_原名", "", "", "%Y-%m-%d_%H-%M-%S"), "2024-05-06_15-30-08_IMG_1.jpg"),
        (("原名_日期", "", "", "%Y-%m-%d_%H-%M-%S"), "IMG_1_2024-05-06_15-30-08.jpg"),
        (("仅原名", "旅行_", "", "%Y-%m-%d_%H-%M-%S"), "旅行_IMG_1.jpg"),
        (("仅日期", "", "_ok", "%Y%m%d_%H%M%S"), "20240506_153008_ok.jpg"),
        (("仅日期", "IMG_", "", "%Y%m%d_%H%M%S"), "IMG_20240506_153008.jpg"),
        (("日期_原名", "IMG_", "", "%Y%m%d_%H%M%S"), "IMG_20240506_153008_IMG_1.jpg"),
    ]
    for (pat, pre, suf, fmt), want in cases:
        got = format_new_name(d, "IMG_1.jpg", fmt, pre, suf, pat)
        check(f"{pat} {fmt} → {want}", got == want, f"实际 {got}")

    check("无时间戳时返回 None", format_new_name(None, "a.jpg", "%Y", "", "", "仅日期") is None)

    tmp = Path(tempfile.mkdtemp())
    (tmp / "a.jpg").write_text("x")
    used = set()
    n1 = safe_rename_target(tmp, "a.jpg", used)
    n2 = safe_rename_target(tmp, "a.jpg", used)
    n3 = safe_rename_target(tmp, "a.jpg", used)
    check("重名自动加序号且互不重复", len({n1, n2, n3}) == 3, f"实际 {[n1, n2, n3]}")
    check("重名首个为 a_1.jpg（因 a.jpg 已存在）", n1 == "a_1.jpg", f"实际 {n1}")
    n4 = safe_rename_target(tmp, "brand_new.jpg", set())
    check("无冲突时保持原名", n4 == "brand_new.jpg", f"实际 {n4}")
    shutil.rmtree(tmp, ignore_errors=True)


# ==========================================================================
# 第二段：HTTP 全链路
# ==========================================================================

def free_port(start=8931):
    import socket
    for p in range(start, start + 80):
        with socket.socket() as s:
            try:
                s.bind(("127.0.0.1", p))
                return p
            except OSError:
                continue
    return 0


def http(url, data=None, timeout=60):
    req = urllib.request.Request(url, method="POST" if data is not None else "GET")
    body = None
    if data is not None:
        req.add_header("Content-Type", "application/json")
        body = json.dumps(data).encode()
    with urllib.request.urlopen(req, body, timeout=timeout) as r:
        return json.loads(r.read().decode())


def test_http(root: Path) -> None:
    print("\n\033[1m[3/4] HTTP 服务全链路\033[0m")
    port = free_port()
    if not port:
        bad("启动服务", "找不到可用端口")
        return
    env = dict(os.environ)
    proc = subprocess.Popen(
        [sys.executable, "-u", str(PROG / "server.py"), "--no-browser"],
        cwd=str(PROG), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
    )
    # server 会从 8787 起找端口，这里直接读它的 stdout
    url_base = None
    t0 = time.time()
    real_port = None
    try:
        while time.time() - t0 < 12:
            line = proc.stdout.readline().decode(errors="ignore")
            if not line:
                if proc.poll() is not None:
                    break
                continue
            if "界面地址" in line:
                real_port = int(line.strip().rsplit(":", 1)[1].rstrip("/"))
                break
        if not real_port:
            bad("服务启动", "12 秒内未拿到监听端口")
            return
        url_base = f"http://127.0.0.1:{real_port}"
        ok("服务已启动", url_base)

        info = http(url_base + "/api/info")
        check("/api/info 返回环境信息", info.get("ok") and "python" in info,
              str(info)[:80])

        br = http(url_base + "/api/browse?path=" + str(root))
        check("/api/browse 能列目录", br.get("ok") and any(d["name"] == "sub" for d in br["dirs"]),
              str([d["name"] for d in br.get("dirs", [])])[:80])

        scan = http(url_base + "/api/scan", {
            "folder": str(root), "recursive": True, "onlyMedia": True,
            "useExiftool": False, "parseFilename": True,
            "readXmp": True, "readJson": True, "fallback": "skip",
        })
        job = scan.get("job")
        check("/api/scan 创建任务", bool(job), str(scan)[:100])
        if not job:
            return

        rows, since, done = [], 0, False
        t0 = time.time()
        while time.time() - t0 < 40:
            st = http(f"{url_base}/api/scan/{job}?since={since}")
            rows += st.get("rows", [])
            since = st.get("nextIndex", since)
            if st.get("error"):
                bad("扫描过程", st["error"])
                return
            if st.get("done"):
                done = True
                break
            time.sleep(0.25)
        check("扫描完成", done and len(rows) >= 10, f"共 {len(rows)} 个文件")
        if not done:
            return

        by_name = {r["name"]: r for r in rows}
        check("扫描结果含 EXIF 时间",
              by_name.get("photo_exif.jpg", {}).get("ts") == "2021-07-04 08:09:10",
              str(by_name.get("photo_exif.jpg", {}).get("ts")))
        check("扫描结果含子目录文件", any(r["dir"].endswith("sub") for r in rows),
              str(sum(1 for r in rows if r["dir"].endswith("sub"))))
        check("无元数据文件被跳过", not by_name.get("no_meta_at_all.jpg", {}).get("ts"))

        opts = {"format": "%Y-%m-%d_%H-%M-%S", "pattern": "仅日期",
                "prefix": "", "suffix": "", "archive": False,
                "archiveFormat": "%Y/%Y-%m", "onlyRenamable": True}
        pv = http(url_base + "/api/preview", {"job": job, "options": opts})
        check("/api/preview 返回计划", pv.get("ok") and pv["stats"]["rename"] >= 8,
              str(pv.get("stats")))
        pv2 = http(url_base + "/api/preview", {"job": job, "options": dict(opts, prefix="P_")})
        sample = [x for x in pv2["plan"] if x["status"] == "ok"][0]
        check("前缀参数生效", sample["newName"].startswith("P_"), sample["newName"])

        # 实际改名
        rn = http(url_base + "/api/rename", {"job": job, "options": opts})
        check("改名执行成功", rn.get("ok") and rn["renamed"] >= 8,
              f"renamed={rn.get('renamed')} errors={rn.get('errors')} {rn.get('errs')}")
        check("生成了撤销记录", bool(rn.get("log")), str(rn.get("log")))

        renamed_file = root / "2021-07-04_08-09-10.jpg"
        check("磁盘上确实出现新文件名", renamed_file.exists(),
              str(sorted(p.name for p in root.iterdir())[:12]))

        # 再扫一次，确认新名字不再需要改名
        scan2 = http(url_base + "/api/scan", {"folder": str(root), "recursive": True,
                                              "onlyMedia": True, "useExiftool": False,
                                              "parseFilename": True, "readXmp": True,
                                              "readJson": True, "fallback": "skip"})
        job2, since, rows2, done2 = scan2["job"], 0, [], False
        t0 = time.time()
        while time.time() - t0 < 40:
            st = http(f"{url_base}/api/scan/{job2}?since={since}")
            rows2 += st.get("rows", [])
            since = st.get("nextIndex", since)
            if st.get("done"):
                done2 = True
                break
            time.sleep(0.25)
        pv3 = http(url_base + "/api/preview", {"job": job2, "options": opts})
        check("改名后再扫描 → 幂等（无需改动）",
              pv3["stats"]["rename"] == 0 and pv3["stats"]["same"] >= 8,
              str(pv3["stats"]))

        # 撤销
        hist = http(url_base + "/api/history")
        check("/api/history 列出记录", hist.get("ok") and len(hist["items"]) >= 1,
              str(len(hist.get("items", []))))
        un = http(url_base + "/api/undo", {"file": rn["log"]})
        check("撤销成功", un.get("ok") and un["undone"] >= 8,
              f"undone={un.get('undone')} failed={un.get('failed')} {un.get('errs')}")
        check("文件名已还原", (root / "photo_exif.jpg").exists(),
              str(sorted(p.name for p in root.iterdir())[:12]))

        # 归档模式
        arch = http(url_base + "/api/preview", {"job": job2, "options": dict(opts, archive=True,
                                                                            archiveFormat="%Y/%Y-%m")})
        arc_ok = arch["plan"][0]["targetDir"] != arch["plan"][0]["dir"]
        check("归档模式生成子目录路径", arc_ok,
              f"{arch['plan'][0]['dir']} → {arch['plan'][0]['targetDir']}")

        # 安全：/api/undo 拒绝路径穿越
        try:
            http(url_base + "/api/undo", {"file": "../../etc/passwd"})
            bad("撤销接口拒绝路径穿越")
        except urllib.error.HTTPError as e:
            check("撤销接口拒绝路径穿越", e.code == 400, f"code={e.code}")

    except Exception as e:
        bad("HTTP 全链路", f"{type(e).__name__}: {e}")
    finally:
        try:
            http(url_base + "/api/quit", {}) if url_base else None
        except Exception:
            pass
        try:
            proc.terminate()
            proc.wait(timeout=5)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass


# ==========================================================================
# 收尾
# ==========================================================================

def main() -> int:
    print("\033[1m" + "=" * 62 + "\033[0m")
    print("\033[1m  ShutterSort · 自检报告\033[0m")
    print("\033[1m" + "=" * 62 + "\033[0m")
    print(f"  解释器：{sys.version.split()[0]}")
    et = ExifTool()
    print(f"  exiftool：{et.info()}")

    tmp = Path(tempfile.mkdtemp(prefix="mt_selftest_"))
    try:
        build_samples(tmp)
        test_parser(tmp)
        test_naming()
        test_http(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("\n\033[1m[4/4] 结果汇总\033[0m")
    print("=" * 62)
    print(f"  \033[32m通过 {len(PASS)}\033[0m   \033[31m失败 {len(FAIL)}\033[0m   \033[33m警告 {len(WARN)}\033[0m")
    if FAIL:
        print("\n  失败项：")
        for f in FAIL:
            print(f"    · {f}")
    print("=" * 62)
    print("\n  自检结束。临时文件已清理，你的真实文件没有被触碰。\n")
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
