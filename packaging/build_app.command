#!/bin/bash
# ShutterSort —— 打包成 macOS App（双击本文件即可重新打包）
# 产物：packaging/dist/ShutterSort.app
#
# 前置条件（只需一次）：
#   python3 -m pip install pyinstaller pywebview
set -e
cd "$(dirname "$0")"

# ---- 选一个装了 PyInstaller 的 Python ----
pick_python() {
  for P in "$SHUTTERSORT_PY" "$(command -v python3.13)" "$(command -v python3.12)" \
           "$(command -v python3.11)" "$(command -v python3)" /opt/homebrew/bin/python3 /usr/bin/python3; do
    [ -n "$P" ] && [ -x "$P" ] || continue
    if "$P" -c "import PyInstaller, webview" >/dev/null 2>&1; then echo "$P"; return 0; fi
  done
  return 1
}

PY="$(pick_python)" || {
  echo ""
  echo "  ✗ 找不到同时装了 PyInstaller 和 pywebview 的 Python。"
  echo "    请先执行：python3 -m pip install pyinstaller pywebview"
  echo ""
  read -n 1 -s -r -p "  按任意键关闭…"
  exit 1
}

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║      开始打包 ShutterSort.app        ║"
echo "  ╚══════════════════════════════════════╝"
echo "  Python：$PY"
echo ""

# 1) 图标（没有就现生成）
if [ ! -f "icons/app.icns" ]; then
  echo "→ 生成图标…"
  "$PY" make_icon.py
fi

# 2) 打包
echo "→ 打包（首次约 2-4 分钟）…"
"$PY" -m PyInstaller --noconfirm --clean \
  --windowed --onefile \
  --name "ShutterSort" \
  --icon "icons/app.icns" \
  --add-data "../src/static:static" \
  --osx-bundle-identifier "io.github.js-ping.shuttersort" \
  "../src/app_main.py"

# 3) 本机 ad-hoc 签名（自己用完全够，不用开发者账号）
echo "→ 签名…"
codesign --force --deep --sign - "dist/ShutterSort.app" 2>/dev/null || true

echo ""
echo "  ✔ 完成：$(pwd)/dist/ShutterSort.app"
echo ""
read -n 1 -s -r -p "  按任意键关闭…"
