# 更新日志

本项目的版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## 1.1.0 — 2026-10-13

**Windows 版来了。** 同一份代码现在在 Windows / macOS / Linux 上跑，功能完全一致。
同时正式启用中文名「拍摄时间改名器」，英文名保持 ShutterSort 不变。

### 新增：Windows 支持

- `start.bat`：双击启动（源码模式，自动找 `py` / `python`，要求 3.8+）
- `build_exe.bat`：双击打包出 `dist\ShutterSort.exe`（单文件免安装，带自定义图标和版本信息）
- `packaging/make_ico.py`：纯标准库生成 `app.ico`（16/24/32/48/64/128/256 七个尺寸，
  小尺寸用未压缩 DIB、256 用 PNG，兼容性最好），不依赖 Pillow / ImageMagick
- `packaging/version_info.txt`：exe 的版本信息，Windows「属性 → 详细信息」里能看到中文产品名
- `tests/run_tests.bat`：双击跑自检
- **自动打包配置**（`.github/workflows/build-desktop.yml`）：推 `v*` 标签，GitHub 就在真实的
  Windows 和 macOS 机器上各打一份，统一挂到对应 Release 的附件里；也可在 Actions 页面手动触发，
  只打包不发布（产物在 Artifacts 里下载）

### 新增：macOS 现成安装包

- Release 上直接提供 `ShutterSort-macOS-arm64.zip`，解压拖进「应用程序」即可用，
  不需要装 Python（此前 macOS 用户只能下源码跑）
- `packaging/build_app.command` 打完 `.app` 后会顺手签名并压出这个 zip，
  里面附带《首次打开说明》（Gatekeeper 放行办法）
- 只支持 Apple 芯片（M1–M4）。Intel Mac 仍需走源码方式，README 里写清楚了

### 改动：跨平台适配（`src/server.py` / `src/app_main.py`）

- 用户数据目录改为按平台取：macOS `~/Library/Application Support`、Windows `%APPDATA%`、
  Linux `$XDG_DATA_HOME`（此前硬编码 macOS 路径）
- 「选择文件夹」补齐平台分支：Windows 用 PowerShell 调 .NET `FolderBrowserDialog`
  （脚本经 base64 + `-EncodedCommand` 传递，中文路径不乱码），Linux 用 `zenity` / `kdialog`
- 快速跳转栏按平台生成：Windows 列出各盘符、macOS 挂 `/Volumes`、Linux 挂 `/media` `/mnt`
- `PATH` 增强、HEIC 缩略图（新增 ImageMagick `magick` 回退）按平台分支
- 输出强制 UTF-8，修掉 Windows 上中文横幅变乱码的问题
- 打包成「无控制台」exe 时 `stdout` 为 `None` 会导致崩溃，已兜底
- 错误弹窗按平台走原生方式：Windows `MessageBoxW`、macOS `osascript`、Linux `zenity`
- 清掉 `_heic_thumb()` 里一段没用的死循环

### 改动：命名与文案

- 中文名统一为「拍摄时间改名器」（界面标题、窗口标题、终端横幅、文档）
- README 新增 Windows 快速上手（三种方式）、常见问题、项目结构；英文版同步

### 质量

- 自检仍为 49 项，全部通过；新增对 Windows 子进程 UTF-8 输出的处理，保证自检跨平台可跑

## 1.0.0 — 2026-10-08

首个公开发布版本。前身是一个未公开发布的内部工具（原名「媒体时间改名器」），本次发布做了整体重构与更名。

### 核心能力

- **时间戳解析引擎**（`src/media_time.py`，纯标准库，10 层固定优先级）
  - 自研 JPEG/TIFF/RAW EXIF 解析器（含 `OffsetTime*` 时区、`SubSecTime*` 毫秒）
  - 自研 ISOBMFF 解析：`com.apple.quicktime.creationdate` → `mvhd` → `mdhd`，只读文件头
  - 自研 HEIC/HEIF Exif item 定位（`meta` → `iinf` / `iloc`）+ TIFF 魔数扫描兜底
  - PNG `tIME` / `eXIf`、WebP EXIF / XMP 支持
  - Google Takeout `.json` 与 `.xmp` 旁车
  - 文件名解析 10 种模式，带 UUID / 长哈希 / 年份合法性误判防护
  - exiftool 自动探测：装了就作为第一优先级使用，没装也完整可用
- **本地服务 + 网页界面**（`src/server.py` / `src/static/index.html`）
  - 只监听 `127.0.0.1`，不联网、不上传
  - 并行扫描（按 CPU 核心数），实时进度
  - 预览表格带彩色「时间戳来源」标签、缩略图、筛选、排序
  - 点击行查看详情：大图 / 视频播放、完整路径、原始元数据逐条
  - 四种命名方式、自定义日期格式、前后缀、按日期归档到子文件夹
  - 改名前确认弹窗；导出 CSV 台账
- **撤销**：记录落盘 JSON，跨会话有效，可撤销任意历史记录；撤销成功自动归档防止重复使用
- **幂等**：冲突检测排除文件自身与本轮即将腾出的旧名，重复执行结果稳定

### 打包

- `packaging/build_app.command`：PyInstaller 打包为独立 macOS App（原生窗口、关窗即退出、无需装 Python）

### 质量

- `tests/selftest.py`：49 项回归自检（解析器 / 文件名规则 / 命名引擎 / HTTP 全链路 / 接口安全）

### 已知限制

- 仅中文界面
- MKV / AVI 无统一创建时间字段，只能靠文件名或文件系统时间
- App 打包仅支持 Apple Silicon（M 系列）Mac；未做公证，拷到别的 Mac 首次打开需右键 →「打开」
- Windows exe 未做代码签名，首次运行会被 SmartScreen 提示（点「更多信息」→「仍要运行」）
- Windows / Linux 上 HEIC 缩略图需要另装 ImageMagick 或 ffmpeg，否则显示占位图标（不影响改名）
