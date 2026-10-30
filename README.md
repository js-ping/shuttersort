<div align="center">

# 拍摄时间改名器

**把手机照片的名字，换成真实的拍摄时间。**

改完之后，整个文件夹自动按拍摄时间排好，跟手机相册里的顺序一模一样。

![License: MIT](https://img.shields.io/badge/License-MIT-8a63d2.svg)

![macOS](https://img.shields.io/badge/macOS-14%2B%20%E5%8E%9F%E7%94%9F%20SwiftUI-000000.svg)

![Python](https://img.shields.io/badge/Python-3.8%2B-3776ab.svg)

![Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen.svg)

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg)

![Tests](https://img.shields.io/badge/self--test-72%20pass-brightgreen.svg)

简体中文 · [English](README.en.md)

</div>

---

## 先看一眼效果

手机拍完导到电脑上，名字是这样的 —— 三个文件，看不出哪天拍的：

```
IMG_8734.HEIC
IMG_8734.MOV
IMG_8741.HEIC
```

改完之后：

```
IMG_20240506_153008.HEIC
IMG_20240506_153012.MOV
IMG_20240506_154421.HEIC
```

一眼就是 2024 年 5 月 6 日下午三点。按名字排序就是按时间排，搜索、备份、传到别的设备都顺畅了。

**它不会动你的照片。** 只改名字，文件内容一个字节都不碰。改错了可以一键还原。

> **适合**：手机照片越攒越多、按文件名找不着的；从微信或 Google 相册成批导出过的；
> 相机时钟设错过一整批的。
>
> **不适合**：想按人脸、地点、事件自动分类的；想改照片本身元数据的；想要云同步的。
> 它只做「改名字」这一件事，并且只把这件做好。

## 三步搞定

**一、下载**

| 你的电脑 | 下什么 | 怎么装 |
| --- | --- | --- |
| Windows 10 / 11 | `ShutterSort.exe` | 双击就能用，不用装任何东西 |
| macOS 14 或更新 | `ShutterSort-x.x.x-macOS-universal.dmg` | 双击挂载，把图标拖进「应用程序」 |

到 [Releases](https://github.com/js-ping/shuttersort/releases) 页面下载。

**二、把装了照片的文件夹拖进窗口**

也可以点「选择文件夹」慢慢挑，或者只点名几个文件。

**三、看一眼右边的预览，点「开始改名」**

预览里会列出每个文件改完之后叫什么。看着不对就别点，这时候什么都还没改。

> 第一次用，建议先把要整理的文件夹复制一份副本出来试手。
> 改错了虽然能撤销，但拿副本练最省心。

> ⚠️ **第一次打开会被系统拦一下**，因为没买代码签名证书（苹果一年 688 元，微软更贵）。
> Windows：点「更多信息」→「仍要运行」。
> macOS：在访达里**右键点 App → 选「打开」→ 再点「打开」**。
> 只需要放行一次，之后双击就正常了。

## 它帮你解决什么

手机拍的、微信转发的、从 Google 相册导出的、相机和无人机拍的 —— 名字里没有时间的，它都能把真实时间找出来。

| 你可能遇到的情况 | 它怎么处理 |
| --- | --- |
| iPhone 导出的 `IMG_8734.HEIC` | 读照片里存着的拍摄时间 |
| 手机录的 `IMG_8734.MOV` | 读视频文件里记录的创建时间 |
| 微信、QQ 转发过、信息被清掉的 | 从文件名里把时间抠出来 |
| Google 相册导出的一大堆 | 读导出时附带的 `.json` |
| 连拍好几张，全落在同一秒 | 读到百分之一秒，先后顺序跟快门一致 |
| 相机时钟设错了，全都差 8 小时 | 整体平移，只改文件名、不动原文件 |
| 名字里带一堆垃圾（`_edited`、多余编号） | 用改名规则一次清干净 |

**它会告诉你每个时间是打哪儿来的。** 列表里每个文件带一个彩色小标签，写着「内嵌·EXIF」「文件名」「Takeout JSON」这类来源。觉得不对可以逐个核对 —— 而不是改完你也不知道它凭什么这么改。

**它只动你勾上的那些。** 扫描完默认全选，取消勾选的原封不动。

**重复扫不会乱改。** 已经改好的文件再扫一遍显示「无需改动」，不会又给你加一遍后缀。

**找不到时间的就跳过。** 标成「无时间戳」，绝不瞎猜一个时间糊弄你。

## 界面

**改名前先看清楚，这时候文件还没被动过：**

![拍摄时间改名器主界面](screenshots/01-main.png)

**点任意一行，能看到这个时间的出处和原始信息：**

![文件详情](screenshots/02-detail.png)

**动手前再确认一次，列清楚要改多少个、命名参数是什么、有没有重名：**

![改名确认](screenshots/03-confirm.png)

**每次改名都记档，重启电脑之后依然能一键还原：**

![改名记录可撤销](screenshots/04-history.png)

**相机时钟错了也不怕 —— 整体平移时间，只改文件名、不改照片里的数据：**

![时间校正](screenshots/05-correction.png)

## 名字怎么起

默认出来是 `IMG_20240506_153008.jpg` —— 前缀 `IMG_` 加上日期时间。这两样都能在左边改，前缀留空就变成 `20240506_153008.jpg`。

日期和原来的名字怎么拼，有四种选法：

| 选这个 | 结果长这样 |
| --- | --- |
| 仅日期（默认） | `20240506_153008.jpg` |
| 日期_原名 | `20240506_153008_IMG_8734.jpg` |
| 原名_日期 | `IMG_8734_20240506_153008.jpg` |
| 仅原名 | `IMG_8734.jpg`（只加前缀后缀，不写时间） |

日期格式可以自己改，比如写成 `2024年05月06日`。还能让它**按日期归档到子文件夹**，自动分到 `2024/2024-05/` 这种目录里。

**如果两个文件算出来的名字撞了**，程序自动在后面加 `_1`、`_2`，绝不覆盖已有文件。

### 名字里有不想要的部分？用「改名规则」

前缀和后缀只能加在名字两头，可真正碍事的那段常常在中间：相机自动加的 `IMG_`、修图软件追的 `_edited`、多余的秒数、导入工具塞的一大串编号。

这条功能（**仅 macOS 版**）在名字拼好之后依次动刀，五种规则：

| 规则 | 做什么 | 例子 |
| --- | --- | --- |
| 插入 | 在第几位后面插一段，或在某段文字前 / 后插 | `20240506_153008` → `20240506-_153008` |
| 删除 | 从第几位删几个字，或者一路删到末尾 | `IMG_20240506_153008` → `20240506_153008` |
| 替换 | 找一段换成另一段，「换成」留空就是删掉 | `IMG_` → `照片_` |
| 剥离字符 | 一次去掉所有空格 / 下划线 / 括号 / 数字 | 清掉名字里的所有下划线 |
| 大小写 | 全小写 / 全大写 / 每词首字母大写 / 首字母大写 | `DSC` → `dsc` |

- 从上往下依次执行，前一条的结果接着给后一条处理。每条能单独关掉，也能上下挪
- **位置不用自己数**：那条规则下面有一排小字符，点哪个就把位置设成几。
  这排字符显示的是「这条规则动手那一刻的名字」，所以前一条把 `IMG_` 换成了 `照片_`（长度变了）也不会点错位
- 空格会画成 `·`，制表符画成 `→`，看不见的字符不会被数错

**两条保护**：扩展名不会被误伤（规则只管 `.jpg` 前面那段）；万一删到一个字都不剩，会退回没编辑过的名字，不会产出 `.jpg` 这种没名字的文件。

<details>
<summary>为什么没有「自动编号」和「正则」这两样</summary>

参照 [ReNamer](https://www.den4b.com/products/renamer) 的规则体系挑了对口的部分，有意砍掉三样：

- **自动编号**：会破坏「重复扫一遍结果不变」。只勾选部分文件时编号就漂了，等于把最核心的承诺废掉。同秒连拍已经按亚秒排好，重名已经有 `_1` `_2`，不需要再编一套号
- **正则 / 脚本**：门槛太高、容易误操作，跟「傻瓜式」的定位冲突
- **改扩展名 / 随机化 / 音译**：跟拍摄时间没关系；改扩展名对照片有风险

Windows / Linux 版暂时没有这个功能，代码与 v1.5.0 相同。

</details>

### 连拍好几张落在同一秒怎么办

一秒能拍好几张，时间戳看起来一样。程序会读照片里存的更精确的那部分（毫秒、微秒），按它排先后 —— 所以谁叫 `_1` 谁叫 `_2` 跟快门顺序一致，换台电脑重扫也不会对调。表格里的时间会带 3 位小字显示这个精度。

### 相机时钟错了怎么办

时区设错、出国忘了调时钟、拷来一批时间全错的老照片 —— 勾上左边的「时间校正」，填天 / 时 / 分三个格子（负数就是往前拨），文件名就按校正后的时间生成。

不确定差多少？选中一行可疑的，点「不知道差多少？用选中行反推…」，直接填这张照片**真实拍摄时间**，偏移量自动算好填回去。

> 校正只影响生成的文件名，**绝不改写照片里的 EXIF 数据**。原值一直在，随时把偏移改回 0 重来。
> 表格里校正过的行会带一个橙色小标签（如 `+8h`），鼠标悬停能看原始时间。

## 时间是从哪找出来的

程序按固定顺序一层层往下翻，**找到第一个能用的就停**，然后告诉你是从哪一层找到的：

1. **照片自己记着的** —— 照片文件里内嵌的拍摄时间。最准，优先用
2. **视频文件里记着的** —— MP4 / MOV / HEIC 这类文件里记录的创建时间，带时区的会自动换算成你本地时间
3. **旁边文件里记着的** —— Google 相册导出时附带的 `.json`，修图软件写在与照片同名的 `.xmp` 里
4. **文件名里写着的** —— DJI、微信、截图工具、中文日期等 10 种常见格式
5. **文件本身的时间** —— 注意这个不是拍摄时间，是「文件存到电脑上的那一刻」。默认不用，要你手动开才会启用

五层都没有，就跳过并标成「无时间戳」，**不会瞎猜一个时间给你**。

<details>
<summary>想看每一层的具体优先级、以及「不装 exiftool 行不行」</summary>

| 顺序 | 来源 | 说明 |
| :-: | --- | --- |
| 1 | exiftool（若已安装） | 覆盖度最高的标准元数据提取 |
| 2 | 容器内嵌时间（MP4/MOV/HEIC） | `com.apple.quicktime.creationdate` → `mvhd` → `mdhd`，UTC 自动换算本机时区 |
| 3 | XMP（JPEG/PNG/WebP 内嵌） | `xmp:CreateDate`、`photoshop:DateCreated` |
| 4 | EXIF（JPEG/TIFF/RAW/WebP） | `DateTimeOriginal` → `DateTimeDigitized` → `DateTime`，支持 `OffsetTime*` 时区与 `SubSecTime*` 毫秒 |
| 5 | PNG `tIME` 块 | 手机截图的救命稻草 |
| 6 | Google Takeout `.json` 旁车 | Google 相册导出附带的准确拍摄时间 |
| 7 | `.xmp` 旁车 | 修图软件写在与图片同名的 `.xmp` 里 |
| 8 | 文件名解析 | 10 种常见命名模式，见下表 |
| 9 | 文件系统时间（需手动开启兜底） | 明确提示：这是文件落盘时间，不是拍摄时间 |
| 10 | 都没有 | 跳过并标记「无时间戳」 |

**不装 exiftool 完全能跑。** 核心格式全是自研解析，纯标准库实现：

- **JPEG / TIFF / RAW 的 EXIF**：自己遍历 TIFF 的 IFD 结构，支持 ARW / NEF / CR2 / DNG / RW2 / ORF / SRW 等 TIFF 系 RAW
- **MP4 / MOV / HEIC / AVIF**：自己解析 ISOBMFF 的 box 结构，从 `keys` + `ilst` 取 QuickTime 创建时间，回退 `mvhd` / `mdhd`
- **HEIC / HEIF**：自己走 `meta` → `iinf` / `iloc` 定位 Exif item，另有 TIFF 魔数扫描兜底
- **PNG / WebP**：自己解析 chunk（`tIME` / `eXIf` / EXIF / XMP）

</details>

<details>
<summary>文件名能认出来的 10 种格式</summary>

| 格式 | 例子 |
| --- | --- |
| DJI Fly | `dji_fly_20251108_164116_0042_D.MP4` |
| DJI | `DJI_20251108_164116_0042_D.MP4` |
| IMG_ / VID_ | `IMG_20250418_193012.jpg` |
| 连续 14 位 | `IMG_20200101000000_0001.jpg` |
| 通用 | `20251111_184839.png` / `2025-11-08_16-41-16.mp4` |
| WhatsApp | `IMG-20240125-WA0001.jpg` |
| 截图 | `Screenshot 2024-09-15 at 10.20.30.jpg` |
| 中文日期 | `2024年5月6日 活动.jpg` |
| 微信 / 相机 | `PXL_20240506_153008123.jpg` |

**纯数字编号不会被误认成日期。** `1000000034.jpg` 这种凑不成合法日期的名字会被识别出来跳过；UUID、长哈希文件名同理，另外还有年份合法性校验兜底。

</details>

## 常见问题

**Q：会不会把我的照片弄坏？**

不会。只改文件名，文件内容一个字节都不动，照片里的拍摄信息也一个字不改。万一改错，改名记录里点一下就能全部还原。

**Q：改名之后，手机相册还认得出来吗？**

这个工具是给「已经导到电脑上」的文件用的。手机里的照片改名不在它的范围内 —— 改的是电脑 / 移动硬盘上的文件，不会影响手机相册。

**Q：为什么有些文件显示「无时间戳」？**

这些文件的信息被处理掉了：微信 / QQ / WhatsApp 转发过的、截图工具二次编辑过的、在线编辑器保存过的。可以在「时间戳来源」里开启文件时间兜底（但那是文件存到电脑的时间，不一定等于拍摄时间），或者就保持跳过。

**Q：时间是差了几个小时？**

照片里的 EXIF 时间本身不带时区，程序没法凭空推断你在哪个时区。带时区的时间来源（视频容器里的创建时间、带 `OffsetTime` 的 EXIF）会自动换算，不会差。

**Q：视频时间比照片早了整整 8 小时？**

先看「时间戳来源」那一列写的是什么：

- `内嵌·mvhd 创建时间` —— 内置解析器直接读容器里的 UTC 秒数再换成本地时间，是对的
- `exiftool·QuickTime:CreateDate` —— 走 exiftool。**v1.3.1 之前**这里有时区 bug：QuickTime 的时间按 UTC 存，而 exiftool 默认按本地时间解释，于是整整早一个时区（+08:00 就是早 8 小时）。v1.3.1 起已修正，与内置解析器结果一致

顺便说：同一个文件，装没装 exiftool 差 8 小时 —— 这正是它容易被忽略的原因。

**Q：Windows 上双击没反应 / 被 SmartScreen 拦下？**

被拦下是没买代码签名证书的正常现象：点「更多信息」→「仍要运行」。如果完全没反应，改用源码模式双击 `start.bat`，它会打印出具体报错。

**Q：Windows 上 HEIC 照片看不到缩略图？**

HEIC 得借外部工具转图。macOS 有系统自带的，Windows / Linux 需要另装 ImageMagick（`winget install ImageMagick`）或 ffmpeg。不装也不影响改名，只是列表里显示一个占位图标。

**Q：支持 Windows / Linux 吗？**

支持。三个平台同一份代码、同样的功能，自检在三个系统上都会跑。Windows 上的「选择文件夹」用系统原生对话框，中文路径不会乱码。

## 关于隐私

- ❌ **不联网**。macOS 原生版连本地端口都不开；Python 版的服务只监听 `127.0.0.1`，外面连不进来
- ❌ **不上传**任何文件、文件名或拍摄信息
- ❌ **不改文件内容**。只做重命名（勾了归档才会多一步移动）
- ✅ 重名有保护，绝不覆盖已有文件
- ✅ 全部自检都在系统临时目录里跑，不碰你的真实文件
- ✅ Windows 的 exe 由公开的 GitHub Actions 构建，构建过程可查

## 给想改代码的人

<details>
<summary>从源码运行</summary>

**Windows**（要求 Python 3.8+，安装时第一屏要勾选 `Add python.exe to PATH`）：

```bat
git clone https://github.com/js-ping/shuttersort.git
cd shuttersort
start.bat
```

**macOS / Linux**（Python 3.8+，macOS 自带）：

```bash
git clone https://github.com/js-ping/shuttersort.git
cd shuttersort
./start.command
```

没有 `pip install`，没有虚拟环境，没有配置文件 —— 纯标准库。

</details>

<details>
<summary>自己打包</summary>

**Windows**：双击 `build_exe.bat`，自动装 PyInstaller、生成图标，打出 `dist\ShutterSort.exe`。

**macOS 原生版**（只要 `swiftc`，`xcode-select --install` 装命令行工具即可，不需要 Xcode）：

```bash
cd native
./build.sh --universal --zip --dmg
```

跑完在 `native/dist/` 里得到三样：能直接双击的 `ShutterSort.app`、
发给别人的 `ShutterSort-<版本>-macOS-universal.dmg` 和同名 `.zip`。

**自动打包**：推一个 `v*` 标签，GitHub Actions 会开真实 Windows 和 macOS 机器各打一份，
自动挂到对应的 Release。也可以到 Actions 页面手动点「Run workflow」只打包不发布。

</details>

<details>
<summary>跑测试</summary>

```bash
python3 tests/selftest.py           # 72 项自检
python3 native/tests/run_parity.py  # 原生版 vs Python 版，14 个场景逐字段对照
```

原生版是 Swift 重写的，最怕「界面好看但时间读错了」。所以 `run_parity.py` 会造一批覆盖各种格式的样本
（HEIC、WebP、大端 TIFF、带时区偏移的 EXIF、子目录同秒冲突），把两版的时间、亚秒、来源、
新文件名、冲突标记全量比一遍，任何一个字段不一致就非零退出。最后还会把 6 个样本真改一遍名字、
复扫验「重复扫描不会乱改」、导 CSV、再撤销回来。

改名规则的边界单独一套闸门 —— 这类「数错一位」的 bug 肉眼极难发现：

```bash
swiftc -O native/Sources/Core/*.swift native/Sources/CLI/main.swift -o /tmp/ss-cli
/tmp/ss-cli edit-test        # 38 项：五类规则 + 0/负数/超长/锚点/叠加/停用/中文/扩展名
```

界面也能离线验收，不用盯着屏幕点：

```bash
native/tests/snapshots.sh            # 浅色
native/tests/snapshots.sh --dark     # 深色
```

会把侧栏、表格单元格、右半栏、五个弹窗离屏渲染成 PNG（`$TMPDIR/shuttersort-snapshots/out`），
用来核对列宽够不够、字有没有被裁、深浅色下看不看得清。

72 项自检覆盖：内置解析器（9 种格式 → 预期时间）、文件名规则、命名引擎、HTTP 全链路
（扫描 → 预览 → 改名 → 幂等复扫 → 撤销）、勾选改名（只动选中的、拒绝扫描结果之外的路径）、
按文件列表扫描（路径去重、跨目录求公共父目录、无效路径过滤）、接口安全（路径穿越防护）。
全程在临时目录操作，跑完自动清理。

</details>

<details>
<summary>可选增强工具（全都可以不装）</summary>

| 工具 | 作用 | 没装会怎样 |
| --- | --- | --- |
| `exiftool` | 第一优先级的元数据提取，覆盖度最高 | 自动改用内置解析器，功能完整 |
| `ffmpeg` | 视频缩略图预览；HEIC 缩略图（备用） | 显示 🎬 图标，不影响改名 |
| `magick`（ImageMagick） | HEIC 缩略图（Windows / Linux 上不装只能看占位图标） | 显示占位图标，不影响改名 |

```bash
brew install exiftool ffmpeg                                    # macOS
winget install exiftool ffmpeg                                  # Windows
sudo apt install libimage-exiftool-perl ffmpeg imagemagick      # Debian / Ubuntu
```

**macOS 原生版这三个全都不用装**：缩略图走系统 ImageIO（HEIC / HEIF / RAW / TIFF 全认）
和 AVFoundation（视频抽第 0.5 秒的帧），exiftool 装了会更准、不装也完整。

</details>

<details>
<summary>和市面上的批量改名工具比，差别在哪</summary>

| 能力 | 普通批量改名工具 | 这个 |
| --- | :---: | :---: |
| 读取照片拍摄时间（EXIF / XMP / PNG / HEIC / RAW） | 部分 | ✅ |
| 读取视频拍摄时间（MP4 / MOV 容器内嵌时间） | 多数不支持 | ✅ |
| 读取聊天软件导出的文件（从文件名解析） | 基本不支持 | ✅ |
| 读取 Google Takeout 导出（`.json` 旁车） | 不支持 | ✅ |
| **告诉你时间是哪儿来的** | 不告诉 | ✅ 每个文件都标注来源，可核对 |
| **只改挑中的那几个文件** | 少有支持 | ✅ 勾了谁才动谁 |
| 撤销 | 多数只支持当次 | ✅ 记录落盘，重启后仍可撤销 |
| 重复执行结果稳定 | 常出问题 | ✅ |
| **同秒连拍按亚秒排先后** | 按读取顺序 | ✅ 编号跟快门一致 |
| **时间校正**（相机钟错 / 忘了调时区） | 少有支持 | ✅ ±天时分，还能按参考文件反推 |
| 安装依赖 | 要装一堆包 | ✅ 零第三方依赖 |
| 平台 | 多半只支持一个 | ✅ Windows / macOS / Linux，macOS 为原生应用 |

</details>

## 项目结构

```
ShutterSort/
├── native/                    ← macOS 原生版（SwiftUI，v1.5.0 起）
│   ├── build.sh               ← 一条命令编出 .app + zip + dmg
│   ├── Sources/Core/          ← 时间戳解析引擎（Swift 重写，含 TIFF/EXIF/ISOBMFF 解析）
│   ├── Sources/UI/            ← SwiftUI 界面（三栏、表格、五个弹窗、说明书）
│   ├── Sources/CLI/           ← 对照测试用的命令行入口
│   └── tests/                 ← run_parity.py 逐字段对照、snapshots.sh 离屏快照
├── start.command / start.bat  ← 双击启动（macOS·Linux / Windows，Python 版）
├── build_exe.bat              ← 双击打包出 Windows 免安装 exe
├── src/
│   ├── media_time.py          ← 时间戳解析引擎（Python 版，Windows / Linux 在用）
│   ├── server.py              ← 本地服务 + 全部接口
│   ├── app_main.py            ← 窗口入口（Windows .exe 用）
│   └── static/index.html      ← 界面（单文件，无构建步骤）
├── tests/selftest.py          ← 72 项回归自检
├── packaging/                 ← Windows 打包 + 图标
│   ├── version_info.txt       ← 打进 exe 的版本资源
│   └── ci/RELEASE_NOTES.md    ← Release 正文（发版前改这一份）
├── .github/workflows/         ← 打标签自动打出 exe 和 .app，一起挂到 Release
├── screenshots/               ← README 截图
└── rename-history/            ← 运行时生成：撤销记录（不要删）
```

## 性能

| 规模 | 表现 |
| --- | --- |
| 100 张照片 | 1 秒以内 |
| 10 000 个文件 | 20–60 秒（取决于硬盘速度） |
| 单个 4 GB 4K 视频 | 只读文件头的 box 结构（几百字节），毫秒级 |

并行扫描默认按 CPU 核心数自动决定并发数；视频只读文件头，不整读进内存。
界面表格最多渲染 1500 行保证流畅，改名仍然作用于全部文件。

## 许可证

[MIT](LICENSE)
