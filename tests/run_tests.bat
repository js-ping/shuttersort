@echo off
chcp 65001 >nul
cd /d "%~dp0.."
title 拍摄时间改名器 · 自检

set "PY="
for %%C in (py python) do (
  if not defined PY (
    where %%C >nul 2>&1 && %%C -c "import sys;sys.exit(0 if sys.version_info>=(3,8) else 1)" >nul 2>&1 && set "PY=%%C"
  )
)

if not defined PY (
  echo   [X] 没有找到 Python 3.8 或更高版本，没法运行自检。
  echo       到 https://www.python.org/downloads/windows/ 装一个即可。
  echo.
  pause
  exit /b 1
)

echo.
echo   正在运行拍摄时间改名器自检…
echo   全程在系统临时目录里操作，不会碰你的真实文件。
echo.

%PY% -u "tests\selftest.py"
echo.
pause
