# 更新日志

本项目的版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

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
- Windows / Linux 未经验证
