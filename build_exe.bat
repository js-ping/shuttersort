@echo off
chcp 65001 >nul
cd /d "%~dp0"
title 打包 ShutterSort.exe
cls

echo.
echo   ======================================================
echo       打包 ShutterSort.exe（Windows 免安装单文件）
echo   ======================================================
echo.

rem ---- 找一个可用的 Python 3.8+ ----
set "PY="
for %%C in (py python) do (
  if not defined PY (
    where %%C >nul 2>&1 && %%C -c "import sys;sys.exit(0 if sys.version_info>=(3,8) else 1)" >nul 2>&1 && set "PY=%%C"
  )
)

if not defined PY (
  echo   [X] 没有找到 Python 3.8 或更高版本。
  echo       到 https://www.python.org/downloads/windows/ 装一个，记得勾选
  echo       "Add python.exe to PATH"，然后重新双击本文件。
  echo.
  pause
  exit /b 1
)

echo   使用解释器：%PY%
echo.

echo   [1/4] 安装打包工具（第一次会比较慢）…
%PY% -m pip install --upgrade pip
%PY% -m pip install --upgrade pyinstaller pywebview pythonnet

echo.
echo   [2/4] 准备图标…
if not exist "packaging\icons\app.ico" %PY% "packaging\make_ico.py"

echo.
echo   [3/4] 打包中（首次约 1-3 分钟）…
%PY% -m PyInstaller --noconfirm --clean ^
  --windowed --onefile ^
  --name "ShutterSort" ^
  --icon "packaging\icons\app.ico" ^
  --version-file "packaging\version_info.txt" ^
  --add-data "src\static;static" ^
  --collect-all webview ^
  --collect-all pythonnet ^
  --collect-all clr_loader ^
  --hidden-import clr ^
  "src\app_main.py"

if not exist "dist\ShutterSort.exe" (
  echo.
  echo   [X] 打包失败，请把上面的报错信息发出来。
  echo.
  pause
  exit /b 1
)

echo.
echo   [4/4] 完成！
echo.
echo   产物：%CD%\dist\ShutterSort.exe
echo   这个 exe 是单文件免安装的，可以直接发给别人用。
echo.
pause
