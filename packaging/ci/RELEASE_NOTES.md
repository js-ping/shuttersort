## 拍摄时间改名器 v1.2.1

把 iPhone 拍的照片、视频的**真实拍摄时间**写回文件名 ——
读的是文件里内嵌的 EXIF / 视频容器元数据，原地重命名，让文件夹自动按时间排序。
全程在本机处理，不联网、不上传任何数据。

### 这一版

- **macOS 改用 dmg 分发**：双击挂载，把 `ShutterSort.app` 拖到旁边的「应用程序」
  就装好了，不用先解压再翻 `.app`。zip 作为备用仍然保留
- **「开始改名」不再被挤出视野**：执行区改成贴住左栏底部的固定条，滚到哪儿都在，
  上面直接写着「将重命名 12 个文件 · 另外 0 个保持不动」
- **修 macOS 包版本号**：之前 `.app` 在「显示简介」里永远是 0.0.0，现在与程序版本一致

上一版（v1.2.0）的功能：勾选改名（勾了谁才改谁，全选 / 清空 / 反选，表头三态）、
拖拽进窗口定位选中、圆角收敛去 AI 味。

### 修复

- 「新文件名」列的重名提示会自己指自己（`IMG_xxx_1.png` 后面挂 `重名 → IMG_xxx_1.png`），
  现在只留一个简短的 `重名加后缀` 标签

### 下载

| 平台 | 附件 | 怎么用 |
| --- | --- | --- |
| **Windows** 10/11 64 位 | `ShutterSort.exe` | 下载后双击即用。免安装、不需要装 Python |
| **macOS** Apple 芯片（M1–M4） | `ShutterSort-macOS-arm64.dmg` | 双击挂载 → 把 App 拖到旁边的「应用程序」→ 双击 |
| **macOS** 同上（备用） | `ShutterSort-macOS-arm64.zip` | 不方便挂载磁盘映像时用：解压后把 App 拖进「应用程序」 |
| **macOS** Intel 芯片 | 没有现成包 | 用下面的源码方式，双击 `start.command` |
| **Linux** | 没有现成包 | 用下面的源码方式，双击 `start.command`，或 `python3 src/server.py` |

两个平台跑的是**完全同一份代码**，功能没有任何差别。

**没看到上面的附件？**（自动构建偶尔会抽风）三条路任选：

1. 下载 Source code → 解压 → Windows 双击 `start.bat` / macOS 双击 `start.command`
   （需要 Python 3.8+；Windows 安装时记得勾选 `Add python.exe to PATH`）
2. 自己打一份：Windows 双击 `build_exe.bat`，macOS 跑 `cd packaging && ./build_app.command`
   （各约 1–3 分钟）
3. 到本仓库 [Actions](https://github.com/js-ping/shuttersort/actions) 页面点「Run workflow」，
   跑完在当次运行的 Artifacts 里下载

### 第一次打开被系统拦下？

两个平台都会拦，因为没买代码签名证书（苹果一年 688 元，微软的还要更贵）。

- **Windows**：SmartScreen 提示「已保护你的电脑」→ 点「更多信息」→「仍要运行」
- **macOS**：提示「无法打开，因为 Apple 无法验证此 App」→ 在访达里**右键点 App → 选「打开」
  → 再点「打开」**；或者跑一行
  `xattr -dr com.apple.quarantine /Applications/ShutterSort.app`

放行只需要做一次，之后双击就正常了。压缩包里也放了一份《首次打开说明.txt》。

整个程序是纯 Python 标准库写成，源码就在 `src/` 里，可以自己核对，也可以自己打包。

### 它和普通批量改名工具的区别

- **可审计**：每个文件都标注时间是从哪一层读出来的，不是黑箱
- **可挑选**：勾选式改名，而不是"一扫描就必须整目录一起动"
- **零依赖**：纯 Python 标准库，没有 `pip install`、没有虚拟环境、没有配置文件
- **自研解析器**：TIFF/EXIF、XMP、PNG、WebP、ISOBMFF（MP4/MOV/HEIC）全部自己解析，外部工具缺了也能跑
- **幂等**：已经改好的文件再扫一次会显示「无需改动」，不会多加后缀
- **可撤销**：每次改名落盘成记录，重启之后依然能一键还原

### 数据安全

- 服务只监听 `127.0.0.1`，不联网、不上传
- 只做重命名，不改文件内容一个字节
- 改名接口对前端传来的路径**跟本次扫描结果求交集**，不在扫描列表里的路径一律拒绝
- 同名冲突自动加 `_1`/`_2`，绝不覆盖已有文件
- 55 项自检全部在系统临时目录里跑，不碰你的真实文件

完整说明见 [README](https://github.com/js-ping/shuttersort#readme) ·
更新日志见 [CHANGELOG](https://github.com/js-ping/shuttersort/blob/main/CHANGELOG.md)
