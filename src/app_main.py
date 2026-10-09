"""ShutterSort · macOS 桌面 App 入口

这个文件是打包成「ShutterSort.app」后真正被执行的入口。

它做三件事：
  1. 在后台线程里启动本地服务（只监听 127.0.0.1，不联网）
  2. 用系统自带的 WebKit 开一个原生窗口，把界面装进去
  3. 窗口关掉 = 程序退出（不会在后台偷偷跑）

如果原生窗口不可用（极少数情况），会自动退回「打开默认浏览器」的方式，
功能完全一样。

用源码直接跑：
    python3 src/app_main.py            # 原生窗口
    python3 src/app_main.py --browser  # 强制用浏览器打开
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import threading
import time
import traceback
from pathlib import Path


# --------------------------------------------------------------------------
# 路径准备：把代码目录塞进 sys.path，保证源码模式和打包模式都能 import
# --------------------------------------------------------------------------

def _code_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(getattr(sys, "_MEIPASS", Path(sys.executable).resolve().parent))
    return Path(__file__).resolve().parent


_CODE = _code_dir()
if str(_CODE) not in sys.path:
    sys.path.insert(0, str(_CODE))

import server  # noqa: E402


def _alert(text: str) -> None:
    """App 模式没有终端，出错就用系统弹窗告诉用户。"""
    try:
        subprocess.run(
            ["osascript", "-e",
             'display alert "ShutterSort" message "%s" as critical' % text.replace('"', "'")],
            timeout=30, check=False,
        )
    except Exception:
        pass


def _quit_hook() -> None:
    """界面里点「退出」时走这里：关窗口 → 结束进程。"""
    try:
        import webview
        for w in list(webview.windows):
            try:
                w.destroy()
            except Exception:
                pass
    except Exception:
        pass
    time.sleep(0.3)
    os._exit(0)


def _pick_folder_native(start: str) -> str:
    """App 模式用原生 NSOpenPanel 选文件夹。

    好处：用户亲自选的文件夹，macOS 会直接授权访问，
    不会卡在「桌面/文稿/下载」的隐私保护（TCC）上。
    返回空字符串表示用户取消。
    """
    import webview
    wins = list(webview.windows)
    if not wins:
        return ""
    res = wins[0].create_file_dialog(
        webview.FOLDER_DIALOG,
        directory=start if start and os.path.isdir(start) else os.path.expanduser("~"),
    )
    if res and len(res):
        return res[0]
    return ""


def run_app() -> int:
    import webview

    try:
        httpd, port = server.make_server()
    except RuntimeError as e:
        _alert(str(e))
        return 1

    url = f"http://127.0.0.1:{port}/"
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    server.log(f"App 启动｜端口 {port}｜{server.python_info()}｜{server.EXIFTOOL.info()}")

    window = webview.create_window(
        server.APP_TITLE,
        url,
        width=1320,
        height=920,
        min_size=(1000, 660),
        background_color="#141416",
        text_select=True,
    )
    server.QUIT_HOOK = _quit_hook
    server.PICK_FOLDER_HOOK = _pick_folder_native

    try:
        webview.start()
    except Exception:
        # 原生窗口起不来 → 退回浏览器模式，功能不受影响
        server.log("原生窗口启动失败，改用浏览器\n" + traceback.format_exc())
        server.open_browser(url)
        try:
            while True:
                time.sleep(3600)
        except KeyboardInterrupt:
            pass
    server.log("App 退出")
    os._exit(0)
    return 0


def run_browser() -> int:
    return server.main()


def main() -> int:
    if "--browser" in sys.argv:
        return run_browser()
    try:
        import webview  # noqa: F401
    except Exception:
        server.log("未安装 pywebview，改用浏览器模式")
        return run_browser()
    return run_app()


if __name__ == "__main__":
    raise SystemExit(main())
