# 拍摄时间改名器 · ShutterSort

把手机照片的文件名换成真实拍摄时间。**只改名，不动照片。**

macOS 14+ · 通用二进制（Apple 芯片 / Intel）· MIT

**下载**：[Releases](../../releases) 里最新那版 `.dmg`

---

## 做什么

```
IMG_8734.HEIC   →   IMG_20240506_153008.HEIC
IMG_8741.HEIC   →   IMG_20240506_154421.HEIC
```

改完之后，按文件名排序就是按拍摄时间排序，跟手机相册里的顺序一模一样。

- 只改名字，**文件内容一个字节都不碰**；改错了可一键撤销（记录落盘，重启后仍可撤）
- 批量扫文件夹，也可以只挑几个文件（勾选 / 拖入）
- 时间校正：相机时钟设错了，整批 ±天/时/分 平移，还能按一个已知时间的文件反推偏移
- 同秒连拍按亚秒排序，顺序稳定
- **六种改名规则链**：插入 / 删除 / 替换 / 剥离字符 / 清理垃圾 / 大小写
  - 位置不用数 —— 规则下面有一排可点的字符，点哪个就把位置设成几，空格画成 `·`、制表符画成 `→`
  - 「清理垃圾」专门对付导出工具塞的东西：`照片(1)` → `照片`，顺带能收掉多余空格、下划线、emoji
- **预设**：日期格式 + 前后缀 + 归档开关 + 整条规则链存成一套，换场景一键切回
- 不联网、不上传，全部在本机

## 安装

1. 下载 dmg，双击挂载，把 App 拖进「应用程序」。
2. 第一次打开会被系统拦（没有 Apple 开发者签名）：**右键点 App → 打开 → 再点「打开」**。
3. 首次启动会弹三步引导；把装了照片的文件夹拖进窗口 → 看预览 → 点「开始改名」。

## 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| 时间是「接收时间」 | 文件里没有拍摄时间元数据（微信、QQ 转发过的图常见），会退回文件系统时间并标注来源 |
| 想用文件时间兜底 | 「时间戳来源」切到「用文件修改时间 / 创建时间」，右侧列表会**立刻**重算，不用重新扫 |
| 视频时间差 8 小时 | 1.3.1 已修（QuickTime 时间按 UTC 存，旧版按本地时间用） |
| MKV / AVI 读不到时间 | 这两种容器没有统一的创建时间字段，只能靠文件名或文件系统时间 |
| 同一批跑两次结果会不会变 | 不会。冲突检测排除了文件自身与本轮腾出的旧名，重复执行结果稳定 |
| 名字里的 (1)、[副本] 怎么去 | 加一条「清理垃圾」规则，勾「括号内容」即可，中英文括号、嵌套都认 |

## 从源码构建

只需要 Command Line Tools（不用 Xcode）：

```bash
cd native
./build.sh --universal --zip --dmg
```

产物在 `native/dist/`。版本号读仓库根的 `VERSION` 文件，一处改完全局生效。

## 测试

```bash
cd native
python3 tests/run_parity.py                 # 与旧 Python 版逐字段对照，3878 项

swiftc -O Sources/Core/*.swift Sources/CLI/main.swift -o /tmp/ss-cli
/tmp/ss-cli edit-test                       # 改名规则 53 项

swiftc -O Sources/Core/*.swift tests/preset-test.swift -o /tmp/ss-preset
/tmp/ss-preset /tmp/ss-preset-dir           # 预设读写 14 项
```

界面行为另有两道闸（需要先造样本：`python3 tests/mkcorpus.py --out /tmp/corpus`）：

```bash
# 切换时间戳来源：9 项，验「跳过 → 修改 → 创建 → 跳过」一圈的行为
swiftc -O Sources/Core/*.swift Sources/UI/AppState.swift tests/fallback-test.swift \
    -o /tmp/ss-fb -framework SwiftUI -framework AppKit
/tmp/ss-fb /tmp/corpus

# 界面离屏渲染成 PNG，核对列宽、裁字、深浅色
tests/snapshots.sh          # 浅色
tests/snapshots.sh --dark   # 深色
```

## 说明

- 界面中文，只做 macOS。1.8.0 起不再提供 Windows / Linux 版，旧 exe 留在 Release 历史里。
- 预设存在 `~/Library/Application Support/ShutterSort/presets.json`，重装应用之前都在。
- 历史版本见 [CHANGELOG.md](CHANGELOG.md)。

## 许可

MIT
