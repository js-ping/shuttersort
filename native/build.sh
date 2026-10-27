#!/bin/bash
# 构建原生版 ShutterSort.app
#
# 不需要 Xcode —— 只用 Command Line Tools 里的 swiftc 就能编出完整的 .app。
# 图标沿用 packaging/icons 下现成的那份（和 Python 版同一个 logo，保持品牌一致）。
#
# 用法：
#   ./build.sh                编译并组装 dist/ShutterSort.app（只编本机架构，日常调试用）
#   ./build.sh --universal    编出 arm64 + x86_64 的通用二进制（发布用）
#   ./build.sh --zip          额外打一个 zip
#   ./build.sh --dmg          额外打一个 dmg（带「拖到应用程序」快捷方式）
#   ./build.sh --universal --zip --dmg   发布全套
#
# 最低系统版本 14.0：界面用了 onChange(of:initial:) 等 macOS 14 的 API。
# 更老的系统（Ventura 及以下）请继续用 Python 版。
set -euo pipefail

cd "$(dirname "$0")"
NATIVE="$(pwd)"
REPO="$(dirname "$NATIVE")"
APP_NAME="ShutterSort"
DIST="$NATIVE/dist"
BUNDLE="$DIST/$APP_NAME.app"
DEPLOY_TARGET="14.0"

WANT_UNIVERSAL=0
WANT_ZIP=0
WANT_DMG=0
for arg in "$@"; do
    case "$arg" in
        --universal) WANT_UNIVERSAL=1 ;;
        --zip)       WANT_ZIP=1 ;;
        --dmg)       WANT_DMG=1 ;;
        *) echo "未知参数：$arg"; exit 2 ;;
    esac
done

# ---- 版本号从 Python 版读，单一真相源
VERSION="$(grep -E '^VERSION *= *"' "$REPO/src/server.py" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
[ -n "$VERSION" ] || { echo "读不到版本号"; exit 1; }
echo "==> 版本 $VERSION"

SWIFT_VER="$(swift --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
echo "==> 编译（Swift ${SWIFT_VER}）"
rm -rf "$DIST"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

# 编译一组源码到指定输出。$1=架构（空=本机）$2=输出路径
compile() {
    local arch="$1" out="$2"
    # bash 3.2 + set -u 下空数组展开会报 unbound，所以用字符串拼
    local targ=""
    if [ -n "$arch" ]; then
        targ="-target ${arch}-apple-macos${DEPLOY_TARGET}"
    fi
    swiftc -O -parse-as-library $targ \
        Sources/Core/*.swift Sources/UI/*.swift \
        -o "$out" \
        -framework SwiftUI -framework AppKit \
        -Xlinker -dead_strip
}

BIN="$BUNDLE/Contents/MacOS/$APP_NAME"

if [ "$WANT_UNIVERSAL" = "1" ]; then
    compile arm64 "$DIST/.build-arm64"
    echo "    arm64 ok"
    compile x86_64 "$DIST/.build-x86_64"
    echo "    x86_64 ok"
    lipo -create "$DIST/.build-arm64" "$DIST/.build-x86_64" -output "$BIN"
    rm -f "$DIST/.build-arm64" "$DIST/.build-x86_64"
    echo "==> lipo 通用二进制 $(lipo -archs "$BIN")"
else
    compile "" "$BIN"
fi

# ---- Info.plist（版本号现填）
#
# 不用 sed 替换占位符：那样每次升版本都得记得同步改 plist 里的旧字符串，
# 改漏了就悄悄打出老版本号。plutil 直接按键写入，不关心原来写的是什么。
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" \
    "$BUNDLE/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$VERSION" \
    "$BUNDLE/Contents/Info.plist"
/usr/bin/plutil -lint "$BUNDLE/Contents/Info.plist" >/dev/null

# ---- 图标
ICNS=""
for cand in "$REPO/packaging/icons/app.icns" "$REPO/packaging/icons/AppIcon.icns"; do
    [ -f "$cand" ] && ICNS="$cand" && break
done
if [ -n "$ICNS" ]; then
    cp "$ICNS" "$BUNDLE/Contents/Resources/AppIcon.icns"
    echo "==> 图标 $(basename "$ICNS")"
else
    echo "==> 没找到 icns（不影响运行，Dock 里会是默认图标）"
fi

# ---- ad-hoc 签名。
# 不签名的话 Apple Silicon 上可能直接被拦；ad-hoc 至少能让本机跑起来。
# 没有开发者证书也做不了公证，所以 Gatekeeper 仍会提示「无法验证开发者」，
# 分发说明里要写清楚怎么右键打开。
echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || echo "    （签名失败，不影响本机运行）"

# ---- 校验
if [ ! -x "$BIN" ]; then
    echo "构建失败：可执行文件不存在"; exit 1
fi
"$BIN" --version | sed 's/^/    自检：/'

SIZE=$(du -sh "$BUNDLE" | cut -f1)
echo "==> 完成：${BUNDLE}（${SIZE}）"

# ---- 发布产物命名带架构，下载的人一眼能看出是不是自己的机器
ARCH_TAG="$(lipo -archs "$BIN" | tr ' ' '-')"
[ "$ARCH_TAG" = "arm64-x86_64" ] && ARCH_TAG="universal"
[ "$ARCH_TAG" = "x86_64-arm64" ] && ARCH_TAG="universal"

if [ "$WANT_ZIP" = "1" ]; then
    ( cd "$DIST" && ditto -c -k --keepParent "$APP_NAME.app" \
        "$APP_NAME-${VERSION}-macOS-${ARCH_TAG}.zip" )
    echo "==> 已打包 $APP_NAME-${VERSION}-macOS-${ARCH_TAG}.zip"
fi

if [ "$WANT_DMG" = "1" ]; then
    STAGE="$DIST/.dmg-stage"
    rm -rf "$STAGE"; mkdir -p "$STAGE"
    cp -R "$BUNDLE" "$STAGE/"
    ln -s /Applications "$STAGE/应用程序"
    cat > "$STAGE/安装说明.txt" <<'TXT'
把左边的「拍摄时间改名器」拖到右边的「应用程序」文件夹里就装好了。

第一次打开时 macOS 会提示「无法验证开发者」（因为本工具没有花钱买苹果签名）。
解决办法：在应用上点右键 → 打开 → 再点「打开」。之后就不会再提示了。

要卸载：从「应用程序」里把它拖到废纸篓即可，不留任何后台进程和常驻服务。
TXT
    DMG="$DIST/$APP_NAME-${VERSION}-macOS-${ARCH_TAG}.dmg"
    rm -f "$DMG"
    hdiutil create -quiet -volname "拍摄时间改名器 $VERSION" \
        -srcfolder "$STAGE" -ov -format UDZO "$DMG"
    rm -rf "$STAGE"
    echo "==> 已打包 $(basename "$DMG")（$(du -sh "$DMG" | cut -f1)）"
fi
