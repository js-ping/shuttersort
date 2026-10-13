## 拍摄时间改名器 v1.1.0

把 iPhone 拍的照片、视频的**真实拍摄时间**写回文件名 ——
读的是文件里内嵌的 EXIF / 视频容器元数据，原地重命名，让文件夹自动按时间排序。
全程在本机处理，不联网、不上传任何数据。

### 这一版新增

- **Windows 支持**：同一份代码现在在 Windows / macOS / Linux 上运行，功能完全一致
- 中文名正式定为「**拍摄时间改名器**」（英文名 ShutterSort 不变）
- Windows 下「选择文件夹」走系统原生对话框，中文路径不乱码
- 新增 ImageMagick 回退，Windows / Linux 上也能出 HEIC 缩略图
- 用户数据目录（撤销记录 / 日志）按各系统规范存放
- README 中英双版重写，新增 Windows 快速上手和常见问题

### 下载

| 平台 | 怎么用 |
| --- | --- |
| **Windows** | 如果下面的附件里有 `ShutterSort.exe`，下载后双击即用 — 免安装、不需要装 Python |
| **macOS** | 下载 **Source code (zip)**，解压后双击 `start.command` |
| **Linux** | 下载 **Source code (zip)**，解压后双击 `start.command`，或 `python3 src/server.py` |

**没看到 `ShutterSort.exe` 附件？**（自动构建偶尔会抽风）三条路任选：

1. 下载 Source code → 解压 → 双击 `start.bat`
   （需要 Python 3.8+，安装时记得勾选 `Add python.exe to PATH`）
2. 下载 Source code → 解压 → 双击 `build_exe.bat`，自己打一份 exe（约 1–3 分钟）
3. 到本仓库 [Actions](https://github.com/js-ping/shuttersort/actions) 页面点「Run workflow」，
   跑完在当次运行的 Artifacts 里下载 exe

三种方式跑的是**完全同一份代码**，功能没有任何差别。

### 第一次打开被 SmartScreen 拦下？

这是没买代码签名证书的正常现象，点「更多信息」→「仍要运行」即可。
整个程序是纯 Python 标准库写成，源码就在 `src/` 里，可以自己核对，也可以自己打包。

### 它和普通批量改名工具的区别

- **可审计**：每个文件都标注时间是从哪一层读出来的，不是黑箱
- **零依赖**：纯 Python 标准库，没有 `pip install`、没有虚拟环境、没有配置文件
- **自研解析器**：TIFF/EXIF、XMP、PNG、WebP、ISOBMFF（MP4/MOV/HEIC）全部自己解析，外部工具缺了也能跑
- **幂等**：已经改好的文件再扫一次会显示「无需改动」，不会多加后缀
- **可撤销**：每次改名落盘成记录，重启之后依然能一键还原

### 数据安全

- 服务只监听 `127.0.0.1`，不联网、不上传
- 只做重命名，不改文件内容一个字节
- 同名冲突自动加 `_1`/`_2`，绝不覆盖已有文件
- 49 项自检全部在系统临时目录里跑，不碰你的真实文件

完整说明见 [README](https://github.com/js-ping/shuttersort#readme) ·
更新日志见 [CHANGELOG](https://github.com/js-ping/shuttersort/blob/main/CHANGELOG.md)
