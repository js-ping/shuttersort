#!/bin/bash
# 编译并跑界面快照工具
#
# 把真实的 SwiftUI 视图离屏渲染成 PNG —— 不用开窗口、不怕锁屏、能在 CI 上跑。
# 用来核对：侧栏四张卡、表格单元格（列宽够不够）、五个弹窗、深浅色。
#
# 局限：Table / List 是 AppKit 撑着的，离屏渲染会是空白，那两处只能看真窗口。
#
# 用法：
#   tests/snapshots.sh                      # 造样本后渲染浅色
#   tests/snapshots.sh --dark               # 深色
#   tests/snapshots.sh --corpus ~/Pictures  # 换成自己的照片
set -euo pipefail

cd "$(dirname "$0")/.."
NATIVE="$(pwd)"
REPO="$(dirname "$NATIVE")"
BIN_DIR="${TMPDIR:-/tmp}/shuttersort-snapshots"
mkdir -p "$BIN_DIR"

CORPUS=""
DARK=""
OUT="$BIN_DIR/out"
while [ $# -gt 0 ]; do
    case "$1" in
        --corpus) CORPUS="$2"; shift 2 ;;
        --out)    OUT="$2"; shift 2 ;;
        --dark)   DARK="--dark"; shift ;;
        --light)  DARK=""; shift ;;
        *) echo "未知参数：$1"; exit 2 ;;
    esac
done

if [ -z "$CORPUS" ]; then
    CORPUS="${TMPDIR:-/tmp}/shuttersort-corpus"
    if [ ! -f "$CORPUS/photo_exif.jpg" ]; then
        echo "==> 造样本"
        python3 tests/mkcorpus.py --out "$CORPUS" >/dev/null
    fi
fi

echo "==> 编译快照工具"
# App.swift 里有 @main，和这里的顶层代码冲突，所以单独排除掉
UI_SOURCES=$(ls Sources/UI/*.swift | grep -v 'App.swift' | tr '\n' ' ')
swiftc -O \
    Sources/Core/*.swift $UI_SOURCES tests/snapshots.swift \
    -o "$BIN_DIR/snapshots" \
    -framework SwiftUI -framework AppKit

echo "==> 渲染"
"$BIN_DIR/snapshots" --corpus "$CORPUS" --out "$OUT" $DARK
echo "==> 输出目录：$OUT"
ls -1 "$OUT"
