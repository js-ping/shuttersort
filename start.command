#!/bin/bash
# ShutterSort —— 双击本文件即可启动（源码模式）
cd "$(dirname "$0")" || exit 1

clear
echo ""
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║                   S h u t t e r S o r t          ║"
echo "  ║   按最可靠的拍摄时间重命名照片与视频（中文界面）  ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo ""

# 找一个可用的 Python 3（3.8+，全部用标准库，无需安装任何依赖）
PY=""
for c in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 python3; do
  if command -v "$c" >/dev/null 2>&1; then
    if "$c" -c 'import sys; sys.exit(0 if sys.version_info>=(3,8) else 1)' 2>/dev/null; then
      PY="$c"; break
    fi
  fi
done

if [ -z "$PY" ]; then
  echo "  ✗ 没有找到 Python 3.8 或更高版本。"
  echo ""
  echo "    解决办法（任选其一）："
  echo "    1) 打开「终端」输入： xcode-select --install   然后重新双击本文件"
  echo "    2) 到 python.org 下载安装 Python 3 后重试"
  echo ""
  read -n 1 -s -r -p "  按任意键关闭…"
  exit 1
fi

echo "  使用解释器：$PY  ($("$PY" -V 2>&1))"
echo "  正在启动本地服务，浏览器会自动打开界面…"
echo "  关闭本窗口 = 退出程序。"
echo ""

exec "$PY" -u "src/server.py"
