#!/bin/bash
# ShutterSort —— 双击本文件运行回归自检（47 项）
cd "$(dirname "$0")/.." || exit 1

PY="$(command -v python3)"
echo ""
echo "  正在运行 ShutterSort 自检…"
echo "  全程在系统临时目录里操作，不会碰你的真实文件。"
echo ""
exec "$PY" -u "tests/selftest.py"
