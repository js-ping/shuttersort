#!/usr/bin/env python3
"""逐字段比对 Swift 版与 Python 版的输出。

两种用法：
    compare.py <python.json> <swift.json>          # 手工比一对
    被 run_parity.py import 当作库用（diff 函数）

任何一处不一致都会打印出来。解析器是重写的，只有这个比对面过零差异，
才敢把原生版交给用户。

关于 1 微秒的例外：Python 产品版在「回退到文件修改时间」这条路上走的是
`datetime.fromtimestamp(float)`，float64 在 1.7e9 这个量级只有约 0.24µs
分辨率，会出现 ±1µs 的抖动（实测：真实 488410.513µs，Python 给 488410，
Swift 给 488411）。这不是原生版的错，是原生版更准。所以容差只在明确
开启时生效，而且会把被容差放过的地方列出来，绝不静默吞掉。
"""
import json
import sys

FIELDS_ROWS = ["path", "name", "ts", "tsIso", "source", "kind", "size"]
FIELDS_PLAN = ["path", "name", "newName", "targetDir", "status", "conflict", "tsShifted"]
TIME_FIELDS = {"ts", "tsIso", "tsShifted"}


def _to_micro(stamp):
    """把 'YYYY-MM-DD HH:MM:SS[.ffffff]' 换算成「从 1970 起的整数微秒」。

    只做整数运算，避免又引入一层浮点误差。
    """
    if not stamp:
        return None
    try:
        head, _, frac = stamp.partition(".")
        y, mo, d = (int(x) for x in head[:10].split("-"))
        hh, mi, ss = (int(x) for x in head[11:19].split(":"))
        # 民用历法换算成天数（Howard Hinnant 的 days_from_civil）
        y -= mo <= 2
        era = (y if y >= 0 else y - 399) // 400
        yoe = y - era * 400
        doy = (153 * (mo + (-3 if mo > 2 else 9)) + 2) // 5 + d - 1
        doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
        days = era * 146097 + doe - 719468
        micro = int((frac + "000000")[:6]) if frac else 0
        return ((days * 24 + hh) * 60 + mi) * 60_000_000 + ss * 1_000_000 + micro
    except Exception:                                       # noqa: BLE001
        return None


def _within_micro(a, b, tolerance):
    if a == b:
        return False
    if tolerance <= 0:
        return False
    ma, mb = _to_micro(a), _to_micro(b)
    if ma is None or mb is None:
        return False
    return abs(ma - mb) <= tolerance


def diff(a, b, micro_tolerance_us=0):
    """返回 (差异列表, 比对项数, 被容差放过的地方)。差异列表为空即一致。"""
    problems = []
    tolerated = []
    for section, fields in (("rows", FIELDS_ROWS), ("plan", FIELDS_PLAN)):
        ra, rb = a[section], b[section]
        if len(ra) != len(rb):
            problems.append(f"{section} 数量不同：python={len(ra)} swift={len(rb)}")
        for i, (x, y) in enumerate(zip(ra, rb)):
            for f in fields:
                va, vb = x.get(f), y.get(f)
                if va == vb:
                    continue
                if f in TIME_FIELDS and _within_micro(va, vb, micro_tolerance_us):
                    tolerated.append(f"{section}[{i}].{f}  python={va!r} swift={vb!r}")
                    continue
                problems.append(
                    f"{section}[{i}].{f}\n    python: {va!r}\n    swift : {vb!r}")
    total = len(a["rows"]) * len(FIELDS_ROWS) + len(a["plan"]) * len(FIELDS_PLAN)
    return problems, total, tolerated


def main():
    a = json.load(open(sys.argv[1], encoding="utf-8"))
    b = json.load(open(sys.argv[2], encoding="utf-8"))
    problems, total, tolerated = diff(a, b)
    for t in tolerated:
        print(f"≈ {t}")
    if not problems:
        print(f"✓ 完全一致 —— {len(a['rows'])} 行 × {len(FIELDS_ROWS)} 字段"
              f" + {len(a['plan'])} 条计划 × {len(FIELDS_PLAN)} 字段，共 {total} 项")
        sys.exit(0)
    for p in problems:
        print(f"✗ {p}")
    print(f"\n共 {len(problems)} 处差异（比对 {total} 项）")
    sys.exit(1)


if __name__ == "__main__":
    main()
