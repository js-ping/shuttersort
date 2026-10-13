@echo off
chcp 65001 >nul
cd /d "%~dp0"
title 拍摄时间改名器 ShutterSort
cls

echo.
echo   ======================================================
echo       拍 摄 时 间 改 名 器   ( ShutterSort )
echo       把 iPhone 的拍摄时间写回文件名
echo       数据全部在本机处理，不联网、不上传
echo   ======================================================
echo.

rem ---- 找一个可用的 Python 3.8+（全部用标准库，无需安装任何依赖） ----
rem 优先用官方启动器 py，它装在哪都能找到；其次才是 PATH 里的 python
set "PY="
for %%C in (py python) do (
  if not defined PY (
    where %%C >nul 2>&1 && %%C -c "import sys;sys.exit(0 if sys.version_info>=(3,8) else 1)" >nul 2>&1 && set "PY=%%C"
  )
)

if not defined PY (
  echo   [X] 没有找到 Python 3.8 或更高版本。
  echo.
  echo       解决办法：
  echo         1. 打开 https://www.python.org/downloads/windows/
  echo         2. 下载 "Windows installer (64-bit)" 并安装
  echo         3. 安装第一屏务必勾选 "Add python.exe to PATH"
  echo         4. 装完后重新双击本文件
  echo.
  echo       不想装 Python？直接下载免安装的 ShutterSort.exe 即可：
  echo         https://github.com/js-ping/shuttersort/releases
  echo.
  pause
  exit /b 1
)

echo   使用解释器：%PY%
echo   正在启动本地服务，浏览器会自动打开界面…
echo   关闭本窗口 = 退出程序。
echo.

%PY% -u "src\server.py"

echo.
pause
