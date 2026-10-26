## 拍摄时间改名器 v1.5.0

把 iPhone 拍的照片、视频的**真实拍摄时间**写回文件名 ——
读的是文件里内嵌的 EXIF / 视频容器元数据，原地重命名，让文件夹自动按时间排序。
全程在本机处理，不联网、不上传任何数据。

### 这一版：macOS 换成了真正的原生应用

以前 macOS 版的壳子是「Python 起一个本地服务 + 内嵌浏览器窗口」。功能没问题，
但那是网页装进窗口，不是 macOS 应用：体积大、启动慢、滚动不跟手、右键菜单不是系统的。

这一版把 macOS 端**整个重写成原生 SwiftUI 应用**。Windows 和 Linux 一行没动，
还是原来那份纯标准库 Python 代码，功能照旧。

**变化有多大**

| | 旧版（Python + 内嵌浏览器） | 新版（原生 SwiftUI） |
| --- | --- | --- |
| 体积 | 10.7 MB | 1.8 MB（Apple 芯片）/ 3.4 MB（通用） |
| 启动 | 1～2 秒（起服务、加载页面） | 秒开 |
| 扫描同一目录 | 0.82 秒 | 0.04 秒 |
| Intel Mac | 用不了 | 通用二进制，能用 |
| 需要 Python | 不需要（已打包） | 不需要 |
| 需要 exiftool | 可选 | 可选，没装就全走内置解析 |
| 需要 ffmpeg | 视频缩略图要它 | 不要了，直接抽视频第 0.5 秒的帧 |
| 界面 | 网页 | 真 macOS 控件：原生表格、原生勾选、系统右键菜单、⌘ 快捷键 |

**解析器是整个重写的，所以做了逐字段对照**

原生化最容易出的错不是界面难看，是**读错时间**——那比不能改名字更糟。
所以原生版的解析器（TIFF/EXIF、XMP、PNG、WebP、ISOBMFF 里的 MP4/MOV/HEIC，
外加文件名兜底和 Takeout 旁车）是照着 Python 版一条条重写的，然后拿同一批样本
把两边的输出**逐字段比**：

- 14 个场景（默认 / 不用 exiftool / 仅日期 / 自定义前后缀 / 归档 / 自定义格式 /
  非递归 / 含非媒体 / 三种时间校正 / 不解析文件名 / 文件时间兜底）
- 累计 **3878 项**比对，时间、亚秒、来源、新文件名、冲突标记、归档目录，全部零差异
- 唯一的例外是被容差放过的一处 1 微秒：Python 版走 `float` 换算文件修改时间，
  在 1.7e9 秒这个量级只有约 0.24µs 分辨率，会抖 ±1µs；原生版直接用 `stat` 的纳秒值，
  比 Python 版更准。这条写在测试脚本注释里，没有偷偷藏起来。

这套对照不是一次性的：`native/tests/run_parity.py` 一条命令跑完 14 个场景，
CI 里每次构建前都会跑，不一致就直接失败，不会发出去。

**和旧版互通的地方**

- 撤销记录用的是**同一个文件**（`~/Library/Application Support/ShutterSort/rename-history`），
  旧版改的名可以在新版里撤销，反过来也行
- 命名规则、时间校正、来源标注的语义完全一致，换版本不会出现「同一批照片算出不同文件名」

> **系统要求变了：macOS 14 (Sonoma) 或更新。** 界面用了 macOS 14 的 API。
> 还在用 Ventura 及更早系统的 Mac，请继续用 v1.4.0 里的 Python 版安装包（那个仍然挂着，能下）。

### 下载

| 平台 | 附件 | 怎么用 |
| --- | --- | --- |
| **Windows** 10/11 64 位 | `ShutterSort.exe` | 下载后双击即用。免安装、不需要装 Python |
| **macOS**（Apple 芯片 + Intel 通用） | `ShutterSort-1.5.0-macOS-universal.dmg` | 双击挂载 → 把 App 拖到旁边的「应用程序」→ 双击 |
| **macOS** 同上（备用） | `ShutterSort-1.5.0-macOS-universal.zip` | 不方便挂载磁盘映像时用：解压后把 App 拖进「应用程序」 |
| **macOS 13 及更早** | 没有现成包 | 用 [v1.4.0](https://github.com/js-ping/shuttersort/releases/tag/v1.4.0) 的 Python 版，或从源码跑 `start.command` |
| **Linux** | 没有现成包 | 源码方式：双击 `start.command`，或 `python3 src/server.py` |

macOS 原生版只认 macOS 14+；Windows / Linux 跑的是纯标准库 Python，功能与以前完全一致。

**没看到上面的附件？**（自动构建偶尔会抽风）三条路任选：

1. 下载 Source code → 解压 → Windows 双击 `start.bat` / macOS 双击 `start.command`
   （需要 Python 3.8+；Windows 安装时记得勾选 `Add python.exe to PATH`）
2. 自己打一份：Windows 双击 `build_exe.bat`；macOS 到 `native/` 里跑
   `./build.sh --universal --zip --dmg`（只要装了命令行开发者工具，不用装 Xcode）
3. 到本仓库 [Actions](https://github.com/js-ping/shuttersort/actions) 页面点「Run workflow」，
   跑完在当次运行的 Artifacts 里下载

### 第一次打开被系统拦下？

两个平台都会拦，因为没买代码签名证书（苹果一年 688 元，微软的还要更贵）。

- **Windows**：SmartScreen 提示「已保护你的电脑」→ 点「更多信息」→「仍要运行」
- **macOS**：提示「无法打开，因为 Apple 无法验证此 App」→ 在访达里**右键点 App → 选「打开」
  → 再点「打开」**；或者跑一行
  `xattr -dr com.apple.quarantine /Applications/ShutterSort.app`

放行只需要做一次，之后双击就正常了。dmg 里也放了一份《安装说明.txt》。

macOS 版是 ad-hoc 签名，没有公证 —— 这是没买证书的必然结果。源码全在 `native/Sources/`，
Swift 标准库 + 系统框架，没有任何第三方依赖，可以自己看、自己编。

### 它和普通批量改名工具的区别

- **可审计**：每个文件都标注时间是从哪一层读出来的，不是黑箱
- **可挑选**：整批扫、只挑几个文件、再勾选到行，三层粒度都行，而不是"一扫描就必须整目录一起动"
- **零第三方依赖**：macOS 原生版只用 Swift 与系统框架，Windows/Linux 是纯 Python 标准库，
  没有 `pip install`、没有虚拟环境、没有配置文件
- **自研解析器**：TIFF/EXIF、XMP、PNG、WebP、ISOBMFF（MP4/MOV/HEIC）全部自己解析，外部工具缺了也能跑
- **幂等**：已经改好的文件再扫一次会显示「无需改动」，不会多加后缀
- **连拍不乱**：同秒多张按亚秒排，编号跟快门一致，换机器重扫也不漂移
- **能纠错**：相机钟错了可以整体平移 ±天时分，也能按一张参考照片反推差多少
- **可撤销**：每次改名落盘成记录，重启之后依然能一键还原

### 数据安全

- **完全不联网**：原生版连本地端口都不开（旧版是 `127.0.0.1` 本地服务，现在这层也没有了）
- 只做重命名，不改文件内容一个字节，不回写任何元数据
- 改名只动勾选中的行，同名冲突自动加 `_1`/`_2`，绝不覆盖已有文件
- Python 版 72 项自检 + 原生版 14 场景逐字段对照，全部在系统临时目录里跑，不碰你的真实文件

完整说明见 [README](https://github.com/js-ping/shuttersort#readme) ·
更新日志见 [CHANGELOG](https://github.com/js-ping/shuttersort/blob/main/CHANGELOG.md)
