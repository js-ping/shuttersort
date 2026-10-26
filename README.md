<div align="center">

# 拍摄时间改名器

**ShutterSort · 把 iPhone 的拍摄时间写回文件名。**

用 iPhone 拍的照片和视频，导出到电脑后名字永远是一串看不出来时间的流水号 ——  
读回文件内嵌的真实拍摄时间，原地重命名，让整个文件夹自动按时间排序。

![License: MIT](https://img.shields.io/badge/License-MIT-8a63d2.svg)

![macOS](https://img.shields.io/badge/macOS-14%2B%20%E5%8E%9F%E7%94%9F%20SwiftUI-000000.svg)

![Python](https://img.shields.io/badge/Python-3.8%2B-3776ab.svg)

![Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen.svg)

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg)

![Tests](https://img.shields.io/badge/self--test-72%20pass-brightgreen.svg)

简体中文 · [English](README.en.md)

</div>

---

用 iPhone 拍的照片和视频，导出到电脑、移动硬盘或云端之后，名字是一串看不出时间的流水号：

```
IMG_8734.HEIC
IMG_8734.MOV
IMG_8741.HEIC
```

名字里没有时间。几百上千张堆在一个文件夹里，按文件名排序就是一团乱麻 ——  
想找「上个月在老家拍的那张」，只能一张张双击点开看。

拍摄时间改名器只做一件事：**把文件名换成真实拍摄时间**。

```
IMG_8734.HEIC   →  IMG_20240506_153008.HEIC
IMG_8734.MOV    →  IMG_20240506_153012.MOV
IMG_8741.HEIC   →  IMG_20240506_154421.HEIC
```

改完之后，文件夹自动按拍摄时间排序，跟手机相册里看到的时间线一致。  
文件名本身就是时间，搜索、备份、跨设备同步全都顺畅了。

## 它和普通批量改名工具的区别

| 能力                                      | 普通批量改名工具 |             拍摄时间改名器             |
| --------------------------------------- | :------: | :-----------------------------: |
| 读取照片拍摄时间（EXIF / XMP / PNG / HEIC / RAW） |    部分    |                ✅                |
| 读取视频拍摄时间（MP4 / MOV 容器内嵌时间）              |   多数不支持  |                ✅                |
| 读取聊天软件导出的文件（从文件名解析）                     |   基本不支持  |                ✅                |
| 读取 Google Takeout 导出（`.json` 旁车）        |    不支持   |                ✅                |
| **告诉你时间是哪儿来的**                          |    不告诉   |         ✅ 每个文件都标注来源，可核对         |
| **只改挑中的那几个文件**（勾选 / 选文件 / 拖拽导入）          |   少有支持   |    ✅ 勾了谁才动谁，也能只扫点名的几个文件   |
| 撤销                                      |  多数只支持当次 |          ✅ 记录落盘，重启后仍可撤销         |
| 重复执行结果稳定（幂等）                            |   常出问题   |                ✅                |
| **同秒连拍按亚秒排先后**                          |    按读取顺序  |      ✅ 读 `SubSecTime`，编号跟快门一致      |
| **时间校正**（相机钟错 / 忘了调时区）                 |   少有支持   |     ✅ ±天时分，还能按参考文件反推差多少     |
| 安装依赖                                    |   要装一堆包  | ✅ **零第三方依赖**（macOS 原生 / 其它平台纯标准库） |
| 平台                                      |  多半只支持一个 | ✅ Windows / macOS / Linux，macOS 为原生应用 |

## 界面

**预览——改名字之前先看清楚，此时文件还没有被改动：**

![拍摄时间改名器主界面](screenshots/01-main.png)

**范围自己定**：整批扫一个文件夹，还是只点名几个文件，随你。

- 第 1 张卡里「选择文件夹」和「选择文件」并排。选文件走系统原生对话框，
  按住 ⌘ / Ctrl 可以一次点多个，也能跨文件夹混着选
- 选完路径框会清空，换成「已选 N 个文件 · 分布在 M 个文件夹」的提示条，
  右边「清空」一键重选；文件模式下不再按扩展名过滤 —— 你亲手挑的就该出现在列表里
- 也可以把文件从访达／资源管理器直接**拖进窗口**，拖几次追加几次；
  如果当前是文件夹模式、拖进来的文件又本来就在这个目录里，会退化成「把这几行选中」

**改哪几个也由你决定**：每行前面有勾选框，勾了才动，没勾的原封不动。

- 扫描完默认全选，想整批改就直接点「开始改名」，跟以前一样
- 工具条上是「已选 N / M 个待改名」，配 **全选 / 清空 / 反选**，
  作用范围只跟着**当前筛选出来的行**走 —— 筛完再全选，不会把看不见的一起改了
- 从访达／资源管理器把文件拖进窗口，会按文件名自动定位并勾选，
  同名文件再用字节大小二次区分；拖进来的东西不在列表里会明确告诉你
- 表头复选框三态：全选 / 半选 / 全不选

每个文件都带一个彩色「时间戳来源」标签，一眼看出整批数据的质量分布：  
`EXIF:DateTimeOriginal` 是照片内嵌的拍摄时间，`QuickTime:CreateDate` 是视频容器内嵌时间，  
`文件名 PXL/微信/相机` 是从文件名里还原出来的，`旁车 Google Takeout JSON` 来自导出时附带的 `.json`，  
灰色「缺失」代表元数据被处理掉了（聊天软件转发件）——默认跳过，**绝不瞎猜**。

**点任意一行，查看这个时间的出处和原始元数据：**

![文件详情](screenshots/02-detail.png)

**动手前二次确认，列出目录数、命名参数、冲突数和样例：**

![改名确认](screenshots/03-confirm.png)

**每次改名都落盘成撤销记录，重启之后依然可以一键还原：**

![改名记录可撤销](screenshots/04-history.png)

**相机时钟错了也不怕——左栏第 4 张卡整体平移时间，只改文件名、不动元数据：**

![时间校正](screenshots/05-correction.png)

## 快速开始

### Windows

**方式一：下载免安装的 exe（最省事）**

到 [Releases](https://github.com/js-ping/shuttersort/releases) 下载 `ShutterSort.exe`，双击即用。  
单文件、免安装、电脑上不需要装 Python。

> 第一次打开如果被 SmartScreen 拦下，点「更多信息」→「仍要运行」。  
> 这是没买代码签名证书的正常现象 —— 整个程序纯 Python 标准库写成，  
> 源码就在 `src/` 里，不放心可以自己用 `build_exe.bat` 打一份。

**方式二：从源码跑**

要求：Windows 10/11 + Python 3.8 以上。到 [python.org](https://www.python.org/downloads/windows/)  
下载安装时，**第一屏记得勾选 `Add python.exe to PATH`**，然后：

```bat
git clone https://github.com/js-ping/shuttersort.git
cd shuttersort
start.bat
```

双击 `start.bat` 也行。会弹出一个命令行窗口，浏览器自动打开操作界面。

**方式三：自己打包成 exe**

双击 `build_exe.bat`，会自动装好 PyInstaller、生成图标、打包出 `dist\ShutterSort.exe`。  
仓库里还带了 [自动打包配置](.github/workflows/build-desktop.yml)：推一个 `v*` 标签，  
GitHub 就会开真实的 Windows 和 macOS 机器各打一份，自动挂到对应的 Release 附件里；  
也可以到 Actions 页面手动点「Run workflow」，只打包不发布（产物在 Artifacts 里下载）。

### macOS

**方式一：下载原生应用（最省事）**

到 [Releases](https://github.com/js-ping/shuttersort/releases) 下载
`ShutterSort-<版本>-macOS-universal.dmg`，双击挂载，把 App 拖到旁边的「应用程序」就装好了。

- 这是**原生 SwiftUI 应用**，不是把网页塞进窗口。1.8 MB（Apple 芯片）/ 3.4 MB（通用二进制），秒开
- **Apple 芯片和 Intel 芯片都能用**（通用二进制）
- 不需要装 Python，不需要 exiftool，不需要 ffmpeg
- 系统要求 **macOS 14 (Sonoma) 或更新**

不想挂载磁盘映像的话，同一个 Release 里也有 `.zip`，解压后同样拖进「应用程序」。

> 第一次打开如果提示「无法打开，因为 Apple 无法验证此 App」：
> 在访达里**右键点 App → 选「打开」→ 再点「打开」**就放行了，只需一次。  
> 或者跑 `xattr -dr com.apple.quarantine /Applications/ShutterSort.app`。  
> 这是没买苹果开发者签名的正常现象，dmg 里也附了一份《安装说明.txt》。

**macOS 13 及更早系统**：原生版用不了，请下
[v1.4.0](https://github.com/js-ping/shuttersort/releases/tag/v1.4.0) 的 Python 版安装包，
或者走下面的源码方式。

**方式二：从源码跑**

要求：Python 3.8+（macOS 自带）。走的是原来的 Python 版界面，功能与原生版一致。

```bash
git clone https://github.com/js-ping/shuttersort.git
cd shuttersort
./start.command          # 双击这个文件也行
```

**方式三：自己编原生版**

只要能跑 `swiftc` 就行（`xcode-select --install` 装命令行开发者工具即可，**不需要 Xcode**）：

```bash
cd native
./build.sh --universal --zip --dmg
```

跑完在 `native/dist/` 里得到三样：可以直接双击的 `ShutterSort.app`、
发给别人的 `ShutterSort-<版本>-macOS-universal.dmg` 和同名 `.zip`。

想验证「原生版和 Python 版读出来的时间一模一样」，再跑一条：

```bash
python3 native/tests/run_parity.py
```

会自动造一批覆盖各种格式的样本（含 HEIC、WebP、大端 TIFF、带时区偏移的 EXIF、子目录同秒冲突），
然后 14 个场景逐字段对照，任何一个字段不一致都会报错退出。

### Linux

```bash
git clone https://github.com/js-ping/shuttersort.git
cd shuttersort
./start.command          # 或 python3 src/server.py
```

### 三个平台都一样

**没有 `pip install`，没有虚拟环境，没有配置文件。** macOS 原生版只用 Swift 与系统框架，
Windows / Linux 是纯 Python 标准库。  
唯一的差别是「选文件夹」对话框和 HEIC 缩略图会调用各自系统的现成工具，见下。

### 可选增强（全都可以不装）

| 工具                    | 作用                                     | 没装会怎样          |
| --------------------- | -------------------------------------- | -------------- |
| `exiftool`            | 第一优先级的元数据提取，覆盖度最高                      | 自动改用内置解析器，功能完整 |
| `ffmpeg`              | 视频缩略图预览；HEIC 缩略图（备用，Windows / Linux 需要）    | 显示 🎬 图标，不影响改名 |
| `magick`（ImageMagick） | HEIC 缩略图（Windows / Linux 上不装它就只能看占位图标） | 显示占位图标，不影响改名   |

> **macOS 原生版这三个全都不用装**：缩略图走系统 ImageIO（HEIC/HEIF/RAW/TIFF 全认）
> 和 AVFoundation（视频抽第 0.5 秒的帧），exiftool 装了会更准、不装也完整。

```bash
brew install exiftool ffmpeg                     # macOS
winget install exiftool ffmpeg                   # Windows
sudo apt install libimage-exiftool-perl ffmpeg imagemagick   # Debian / Ubuntu
```

> **「选择文件夹」和「选择文件」对话框**用的是各系统自带的能力：macOS 走 `osascript`，  
> Windows 走 PowerShell + .NET（`OpenFileDialog { Multiselect = $true }`，中文路径不乱码），  
> Linux 走 `zenity` / `kdialog`。打包成 App / exe 之后直接走 pywebview 的原生对话框。  
> 都没有时界面会退回到手动输入路径或直接拖拽，功能不受影响。

## 工作原理：时间戳优先级

程序按固定顺序一层层往下找，**第一个成功的就是最终结果**。  
界面上每个文件都标注用了哪一层，这让改名结果**可审计、可复现**。

|  顺序 | 来源                            | 说明                                                                                          |
| :-: | ----------------------------- | ------------------------------------------------------------------------------------------- |
|  1  | **exiftool**（若已安装）            | 覆盖度最高的标准元数据提取                                                                               |
|  2  | **容器内嵌时间**（MP4/MOV/HEIC）      | `com.apple.quicktime.creationdate` → `mvhd` → `mdhd`，UTC 自动换算本机时区                           |
|  3  | **XMP**（JPEG/PNG/WebP 内嵌）     | `xmp:CreateDate`、`photoshop:DateCreated`                                                    |
|  4  | **EXIF**（JPEG/TIFF/RAW/WebP）  | `DateTimeOriginal` → `DateTimeDigitized` → `DateTime`，支持 `OffsetTime*` 时区与 `SubSecTime*` 毫秒 |
|  5  | **PNG `tIME` 块**              | 手机截图的救命稻草                                                                                   |
|  6  | **Google Takeout `.json` 旁车** | Google 相册导出附带的准确拍摄时间                                                                        |
|  7  | **`.xmp` 旁车**                 | 修图软件写在与图片同名的 `.xmp` 里                                                                       |
|  8  | **文件名解析**                     | 10 种常见命名模式，见下表                                                                              |
|  9  | **文件系统时间**（需手动开启兜底）           | 明确提示：这是文件落盘时间，不是拍摄时间                                                                        |
|  10 | 都没有                           | 跳过并标记「无时间戳」，**绝不瞎猜**                                                                        |

### 内置解析器

不装 exiftool 也完整可用，因为核心格式全部是自研二进制解析（纯标准库）：

- **JPEG/TIFF/RAW EXIF**：自研 TIFF/IFD 遍历，支持 ARW / NEF / CR2 / DNG / RW2 / ORF / SRW 等 TIFF 系 RAW
- **ISOBMFF（MP4/MOV/HEIC/AVIF）**：自研 box 结构解析，`keys` + `ilst` 取 QuickTime 创建时间，回退 `mvhd` / `mdhd`
- **HEIC/HEIF**：自研 `meta` → `iinf` / `iloc` 定位 Exif item，另有 TIFF 魔数扫描兜底
- **PNG / WebP**：自研 chunk 解析（`tIME` / `eXIf` / EXIF / XMP chunk）

### 文件名识别（10 种模式）

| 格式           | 例子                                                |
| ------------ | ------------------------------------------------- |
| DJI Fly      | `dji_fly_20251108_164116_0042_D.MP4`              |
| DJI          | `DJI_20251108_164116_0042_D.MP4`                  |
| IMG_ / VID\_ | `IMG_20250418_193012.jpg`                         |
| 连续 14 位      | `IMG_20200101000000_0001.jpg`                     |
| 通用           | `20251111_184839.png` / `2025-11-08_16-41-16.mp4` |
| WhatsApp     | `IMG-20240125-WA0001.jpg`                         |
| 截图           | `Screenshot 2024-09-15 at 10.20.30.jpg`           |
| 中文日期         | `2024年5月6日 活动.jpg`                                |
| 微信 / 相机      | `PXL_20240506_153008123.jpg`                      |

> **纯数字编号不会被误判**。`1000000034.jpg` 这种不构成合法日期的名字，程序会认出来并跳过；  
> UUID、长哈希文件名同理，另外还有年份合法性校验兜底。

## 命名规则

**默认输出：`IMG_20261012_122123.jpg`** —— 前缀 `IMG_` + 日期格式 `%Y%m%d_%H%M%S`，  
两项都能在界面上改（前缀留空就变成 `20261012_122123.jpg`）。

| 命名方式    | 结果示例（下表示例不含前缀）                 |
| ------- | ------------------------------ |
| 仅日期（默认） | `20240506_153008.jpg`          |
| 日期_原名   | `20240506_153008_IMG_8734.jpg` |
| 原名_日期   | `IMG_8734_20240506_153008.jpg` |
| 仅原名     | `IMG_8734.jpg`（只加前后缀）          |

> 加上默认前缀 `IMG_` 之后，「仅日期」的实际结果就是 `IMG_20261012_122123.jpg`。

日期格式支持 `%Y %m %d %H %M %S %j` 等占位符，可以自定义（例如 `%Y年%m月%d日`），  
也支持 **按日期归档到子文件夹**（如 `2024/2024-05/`）。

冲突处理：目标名已存在时自动加 `_1`、`_2` 后缀；冲突检测会排除「文件自身」和「本轮即将腾出的旧名」，  
所以**重复执行结果稳定**——已经改好的文件再次扫描时会显示「无需改动」，不会被再改一次。

### 同秒连拍按亚秒排序

连拍一秒能拍好几张，全都落在同一秒里。程序会读 EXIF 的 `SubSecTimeOriginal`（毫秒/微秒部分），  
同一秒内按亚秒先后排，所以谁拿 `_1` 谁拿 `_2` 跟快门顺序一致，不会随文件夹的读取顺序漂移。  
表格里的时间会带 3 位小字显示亚秒，一眼能看出先后。

没有亚秒信息时（部分安卓机不写）用文件修改时间兜底，再不行用文件名兜底 —— 三级排序，结果始终稳定。

### 时间校正（不改元数据）

相机时区设错、出国忘了调时钟、或者拷来一批时间全错的老照片，文件名会跟着错。勾上「时间校正」，  
填 `天 / 时 / 分` 三个框（负数就是往前拨），所有文件名按校正后的时间生成。

不确定差多少？选中一行可疑文件点「不知道差多少？用选中行反推…」，直接填这张照片**真实拍摄时间**，  
程序自动算出偏移量填回去 —— 比手动试快得多。

> ⚠️ **校正只影响生成的文件名，绝不改写文件的 EXIF 元数据**。原值始终保留，随时能推回去重来。  
> 表格里校正过的行会带一个橙色偏移标签（如 `+8h`），鼠标悬停可看原始时间。

## 数据安全与隐私

- ❌ **不联网**。服务只监听 `127.0.0.1`，外部无法访问
- ❌ **不上传**任何文件、文件名或元数据
- ❌ **不修改文件内容**。只做重命名（勾选归档时多做一步移动）
- ✅ 改名和撤销都有冲突保护，绝不覆盖已有文件
- ✅ 全部 72 项自检都在系统临时目录里跑，不碰真实文件
- ✅ Windows 的 exe 由公开的 GitHub Actions 构建，构建过程可查

## 性能

| 规模            | 表现                      |
| ------------- | ----------------------- |
| 100 张照片       | 1 秒以内                   |
| 10 000 个文件    | 20–60 秒（取决于硬盘速度）        |
| 单个 4 GB 4K 视频 | 只读文件头的 box 结构（几百字节），毫秒级 |

并行扫描默认按 CPU 核心数自动决定并发数；视频只读文件头，不整读进内存。  
界面表格最多渲染 1500 行保证流畅，改名仍然作用于全部文件。

## 项目结构

```
ShutterSort/
├── native/                    ← macOS 原生版（SwiftUI，v1.5.0 起）
│   ├── build.sh               ← 一条命令编出 .app + zip + dmg
│   ├── Sources/Core/          ← 时间戳解析引擎（Swift 重写，含 TIFF/EXIF/ISOBMFF 解析）
│   ├── Sources/UI/            ← SwiftUI 界面（三栏、表格、五个弹窗、说明书）
│   ├── Sources/CLI/           ← 对照测试用的命令行入口
│   └── tests/run_parity.py    ← 原生版 vs Python 版逐字段对照（14 个场景）
├── start.command / start.bat  ← 双击启动（macOS·Linux / Windows，Python 版）
├── build_exe.bat              ← 双击打包出 Windows 免安装 exe
├── src/
│   ├── media_time.py          ← 时间戳解析引擎（Python 版，Windows / Linux 在用）
│   ├── server.py              ← 本地服务 + 全部接口
│   ├── app_main.py            ← 窗口入口（Windows .exe 用）
│   └── static/index.html      ← 界面（单文件，无构建步骤）
├── tests/
│   ├── selftest.py            ← 72 项回归自检
│   └── run_tests.command/.bat ← 双击跑自检
├── packaging/                 ← Windows 打包 + 图标（make_ico.py 出 .ico）
│   ├── version_info.txt       ← 打进 exe 的版本资源
│   └── ci/RELEASE_NOTES.md    ← Release 正文（发版前改这一份）
├── .github/workflows/         ← 打标签自动打出 exe 和 .app，一起挂到 Release
├── screenshots/               ← README 截图
└── rename-history/            ← 运行时生成：撤销记录（不要删）
```

## 开发与测试

```bash
python3 tests/selftest.py       # macOS / Linux
python tests\selftest.py        # Windows
```

也可以双击 `tests/run_tests.command`（macOS/Linux）或 `tests/run_tests.bat`（Windows）。

macOS 原生版另有自己的闸门 —— 它和 Python 版必须读出一模一样的结果：

```bash
python3 native/tests/run_parity.py          # 自动造样本，14 个场景逐字段比
python3 native/tests/run_parity.py --dir ~/Pictures/某相册   # 换成你自己的照片
```

一条命令会编出对照用的 CLI、造出覆盖 9 种格式的样本、把两版的
时间 / 亚秒 / 来源 / 新文件名 / 冲突标记全量比一遍，不一致就非零退出。

72 项自检覆盖：内置解析器（9 种格式 → 预期时间）、文件名规则、命名引擎、  
HTTP 全链路（扫描 → 预览 → 改名 → 幂等复扫 → 撤销）、勾选改名（只动选中的、
拒绝扫描结果之外的路径）、按文件列表扫描（路径去重、跨目录求公共父目录、
无效路径过滤）、接口安全（路径穿越防护）。  
全程在临时目录操作，跑完自动清理。

## 常见问题

**Q：为什么有些文件显示「无时间戳」？**  
这些文件的元数据被处理掉了（微信/QQ/WhatsApp 转发、截图工具二次编辑、在线编辑器保存）。  
可以在「时间戳来源」里开启文件时间兜底，或保持跳过。

**Q：时间差了几小时？**  
EXIF 时间本身不带时区，程序无法凭空推断。带时区的时间源（容器 `creationdate`、带 `OffsetTime` 的 EXIF）会自动换算，不会差。

**Q：视频时间比照片早了 / 晚了整整 8 小时？**  
先看「时间戳来源」那一列：

- `内嵌·mvhd 创建时间` —— 内置解析器直接读容器里的 UTC 秒数再换成本地时间，是对的
- `exiftool·QuickTime:CreateDate` —— 走的是 exiftool。**v1.3.1 之前**这里有个时区 bug：
  QuickTime 的时间是按 UTC 存的，而 exiftool 默认按本地时间解释，于是整整早了一个
  时区偏移（+08:00 就是早 8 小时）。v1.3.1 起已按 UTC 换算，与内置解析器结果一致

顺便说：同一个文件，装没装 exiftool 差 8 小时 —— 这正是它容易被忽略的原因。

**Q：改完名字会影响照片 / 视频本身吗？**  
不会。原地重命名只改文件名，文件内容一个字节都不动。

**Q：Windows 上双击 exe 没反应 / 被 SmartScreen 拦下？**  
被拦下是没买代码签名证书的正常现象：点「更多信息」→「仍要运行」。  
如果完全没反应，改用源码模式双击 `start.bat`，它会打印出具体报错。

**Q：Windows 上 HEIC 照片看不到缩略图？**  
HEIC 浏览器解不了，得借外部工具转图。macOS 有系统自带的 `sips`，Windows / Linux 需要另装  
ImageMagick（`winget install ImageMagick`）或 ffmpeg。没装也不影响改名，只是列表里显示占位图标。

**Q：支持 Windows / Linux 吗？**  
支持。三个平台同一份代码、同样的功能，自检在 Windows / macOS / Linux 上都会跑。  
Windows 上的「选择文件夹 / 选择文件」用 PowerShell 调系统原生对话框，中文路径不会乱码。

## 许可证

[MIT](LICENSE)
