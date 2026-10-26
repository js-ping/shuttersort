#!/usr/bin/env python3
"""一键跑完 Swift 版与 Python 版的逐字段对照。

做的事：
  1. 编出对照用的命令行版本（不用 Xcode，swiftc 就够）
  2. 造一批覆盖各种格式的样本
  3. 按十来个场景各跑一遍两版，逐字段比
  4. 打印一张结果表，有任何差异就非零退出

用法：
    tests/run_parity.py                  # 造样本 + 全部场景
    tests/run_parity.py --dir ~/Pictures # 换成你自己的真实相册
    tests/run_parity.py --keep           # 保留临时产物，便于进一步排查

为什么要这么麻烦：原生版是把解析器整个重写了一遍，肉眼看着对不代表真的对。
只有逐字段零差异，才敢把它发给用户。
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
NATIVE = HERE.parent
REPO = NATIVE.parent

sys.path.insert(0, str(HERE))
import compare  # noqa: E402


def build_cli(out_dir: Path) -> Path:
    """编译对照用的 CLI。Core 一份源码，UI 一个不带 —— 输出全是纯文本。"""
    binary = out_dir / "ss-dump"
    cmd = [
        "swiftc", "-O",
        *sorted(str(p) for p in (NATIVE / "Sources" / "Core").glob("*.swift")),
        str(NATIVE / "Sources" / "CLI" / "main.swift"),
        "-o", str(binary),
    ]
    print("==> 编译对照用 CLI…")
    t0 = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr[-4000:])
        sys.exit("编译失败")
    print(f"    完成（{time.time() - t0:.1f}s）")
    return binary


def swift_dump(binary: Path, args: list) -> list:
    cmd = [str(binary), "dump", *args]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr[-3000:])
        raise RuntimeError(f"swift dump 失败：{' '.join(cmd)}")
    return [cmd, json.loads(r.stdout)]


def py_dump(args: list) -> list:
    cmd = [sys.executable, str(HERE / "pydump.py"), *args]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr[-3000:])
        raise RuntimeError(f"python dump 失败：{' '.join(cmd)}")
    return [cmd, json.loads(r.stdout)]


# 每个场景 = (名字, 参数, 允许的微秒容差)。
# 两版收同一套参数，谁多一个少一个都不行。
# 容差只给「兜底用文件时间」这一条：Python 走 float，会有 ±1µs 抖动。
def scenarios(target: str) -> list:
    d = ["--dir", target]
    return [
        ("默认（全部内置解析 + exiftool）", d, 0),
        ("不用 exiftool（纯内置解析）", d + ["--no-exiftool"], 0),
        ("仅日期命名", d + ["--pattern", "仅日期"], 0),
        ("自定义前缀后缀", d + ["--prefix", "旅行_", "--suffix", "_已整理"], 0),
        ("空前缀", d + ["--prefix", ""], 0),
        ("按日期归档", d + ["--archive"], 0),
        ("自定义时间格式", d + ["--format", "%Y-%m-%d_%H.%M.%S"], 0),
        ("非递归", d + ["--no-recursive"], 0),
        ("包含非媒体文件", d + ["--all-files"], 0),
        ("时间校正 +8 小时", d + ["--offset", "28800"], 0),
        ("时间校正 −1 天", d + ["--offset", "-86400"], 0),
        ("时间校正 +90 分钟", d + ["--offset", "5400"], 0),
        ("不解析文件名", d + ["--no-filename"], 0),
        ("兜底用文件时间", d + ["--fallback", "modified"], 1),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="", help="用这个目录当样本（默认自动造一批）")
    ap.add_argument("--keep", action="store_true", help="保留临时产物")
    ap.add_argument("--reuse", action="store_true", help="复用已有的 CLI 二进制，快速重跑")
    a = ap.parse_args()

    work = Path(tempfile.gettempdir()) / "shuttersort-parity"
    if not a.keep:
        pass  # 目录本身就复用，不清空，省得每次重编
    work.mkdir(parents=True, exist_ok=True)

    # ---- 1. CLI
    binary = work / "ss-dump"
    if a.reuse and binary.exists():
        print("==> 复用已有 CLI")
    else:
        binary = build_cli(work)

    # ---- 2. 样本
    if a.dir:
        target = str(Path(a.dir).expanduser().resolve())
        print(f"==> 样本目录：{target}")
    else:
        target = str(Path(tempfile.gettempdir()) / "shuttersort-corpus")
        if not (Path(target) / "photo_exif.jpg").exists():
            print("==> 造样本…")
            r = subprocess.run([sys.executable, str(HERE / "mkcorpus.py"),
                                "--out", target], capture_output=True, text=True)
            if r.returncode != 0:
                print(r.stdout)
                print(r.stderr[-3000:])
                sys.exit("造样本失败")
        else:
            print("==> 复用已造好的样本")
        print(f"    样本目录：{target}")

    # ---- 3. 逐场景比
    print()
    rows = []
    failed = 0
    for name, args, tol in scenarios(target):
        try:
            py_cmd, py = py_dump(args)
            sw_cmd, sw = swift_dump(binary, args)
        except Exception as e:                              # noqa: BLE001
            rows.append((name, "脚本出错", str(e)[:120]))
            failed += 1
            continue
        problems, total, tolerated = compare.diff(py, sw, micro_tolerance_us=tol)
        if tolerated:
            print(f"≈ {name}：{len(tolerated)} 处 1µs 级浮点抖动（Swift 更准，已容差放过）")
            for t in tolerated[:5]:
                print(f"   {t}")
        if problems:
            failed += 1
            rows.append((name, f"✗ {len(problems)} 处差异", f"{total} 项"))
            print(f"—— {name} 的差异明细 ——")
            for p in problems[:20]:
                print(f"   {p}")
            if len(problems) > 20:
                print(f"   …还有 {len(problems) - 20} 处")
            print()
        else:
            rows.append((name, "✓ 一致", f"{total} 项"))

    # ---- 4. 结果表
    w = max(len(r[0]) for r in rows)
    print("=" * (w + 34))
    for name, verdict, extra in rows:
        pad = " " * (w - len(name))
        print(f"  {name}{pad}  {verdict:<12}  {extra}")
    print("=" * (w + 34))
    total_items = sum(int(r[2].split()[0]) for r in rows if r[2].endswith("项"))
    print(f"  {len(rows)} 个场景 · 累计比对 {total_items} 项 · "
          f"{'全部零差异' if failed == 0 else f'{failed} 个场景有不一致'}")

    if not a.keep and not a.dir:
        pass  # 样本留着，下次重跑更快

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
