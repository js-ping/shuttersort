#!/bin/bash
# 拍摄时间改名器（ShutterSort）—— 打包成 macOS App（双击本文件即可重新打包）
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
echo "  =========================================="
echo "      开始打包 ShutterSort.app"
echo "      拍摄时间改名器 · macOS 版"
echo "  =========================================="
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

# 3) 把版本号写进 Info.plist
#    PyInstaller 默认写 0.0.0，不改的话「显示简介」里永远是 0.0.0，
#    用户根本分不清自己装的是哪一版。必须放在签名之前，否则封条失效。
PLIST="dist/ShutterSort.app/Contents/Info.plist"
VER="$("$PY" -c "
import pathlib, re, sys
s = pathlib.Path('../src/server.py').read_text(encoding='utf-8')
m = re.search(r'^VERSION\s*=\s*\"([^\"]+)\"', s, re.M)
print(m.group(1) if m else '0.0.0')
")"
for K in CFBundleShortVersionString CFBundleVersion; do
  /usr/libexec/PlistBuddy -c "Set :$K $VER" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$K string $VER" "$PLIST"
done
echo "  版本号已写入：$VER"

# 4) 本机 ad-hoc 签名（自己用完全够，不用开发者账号）
echo "→ 签名…"
codesign --force --deep --sign - "dist/ShutterSort.app" 2>/dev/null || true
codesign --verify --deep --strict "dist/ShutterSort.app" 2>/dev/null \
  && echo "  签名校验通过" || echo "  ! 签名校验没通过，自己用一般也没事"

# 5) 压成可以直接发出去的 zip
#    外面套一层文件夹，把「首次打开说明」一起放进去；
#    必须用 ditto，普通 zip 可能丢元数据、破坏签名封条。
echo "→ 压缩成 zip…"
ZIP="dist/ShutterSort-macOS-arm64.zip"
rm -rf "dist/_stage" "$ZIP"
mkdir -p "dist/_stage/ShutterSort-macOS"
cp -R "dist/ShutterSort.app" "dist/_stage/ShutterSort-macOS/"
if [ -f "mac/FIRST-RUN.txt" ]; then
  cp "mac/FIRST-RUN.txt" "dist/_stage/ShutterSort-macOS/首次打开说明.txt"
fi
(cd "dist/_stage" && ditto -c -k --sequesterRsrc --keepParent ShutterSort-macOS "../ShutterSort-macOS-arm64.zip")
rm -rf "dist/_stage"

# 6) 打成 dmg —— macOS 用户双击挂载、把 App 拖到「应用程序」就装好了，
#    比「解压 zip 再找 .app」顺手得多。UDZO 是压缩格式，体积和 zip 差不多。
echo "→ 打包成 dmg…"
DMG="dist/ShutterSort-macOS-arm64.dmg"
rm -rf "dist/_dmg" "$DMG"
mkdir -p "dist/_dmg"
cp -R "dist/ShutterSort.app" "dist/_dmg/"
# 放一个指向 /Applications 的软链，挂载后可以直接把 App 拖上去
ln -s /Applications "dist/_dmg/Applications"
[ -f "mac/FIRST-RUN.txt" ] && cp "mac/FIRST-RUN.txt" "dist/_dmg/首次打开说明.txt"
hdiutil create -volname "ShutterSort" -srcfolder "dist/_dmg" -ov -format UDZO -quiet "$DMG"
rm -rf "dist/_dmg"
# dmg 也签一下，双击挂载时系统检查更顺
codesign --force --sign - "$DMG" 2>/dev/null || true

echo ""
echo "  ✔ App ：$(pwd)/dist/ShutterSort.app"
echo "  ✔ dmg ：$(pwd)/$DMG        ← 发给别人用这个"
echo "  ✔ zip ：$(pwd)/$ZIP   （备用：解压后同样能拖进「应用程序」）"
echo ""
read -n 1 -s -r -p "  按任意键关闭…"
