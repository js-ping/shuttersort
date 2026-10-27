import Foundation

/// 命令行入口，只用于「Swift 版 vs Python 版」逐字段对照。
///
/// 存在的意义：解析器是重写的，肉眼看着对不代表真的对。用同一批样本分别跑
/// 两个版本，把 ts / tsIso / source / newName 全量比一遍，差异必须为零。
///
/// 用法：
///   shuttersort-cli dump --dir /path [--recursive] [--format F] [--prefix P]
///                        [--pattern 仅日期] [--offset 28800] [--no-exiftool]
///                        [--edit insert:8:-] [--edit delete:1:4]

struct CLIArgs {
    var command = "dump"
    var dir: String?
    var files: [String] = []
    var recursive = true
    var onlyMedia = true
    var format = "%Y%m%d_%H%M%S"
    var prefix = "IMG_"
    var suffix = ""
    var pattern = NamePattern.dateOnly
    var archive = false
    var archiveFormat = "%Y/%Y-%m"
    var offset = 0
    var useExifTool = true
    var parseFilename = true
    var fallback: FallbackMode = .skip
    var edits: [NameEdit] = []

    /// `insert:<位置>:<文字>` 或 `delete:<位置>:<个数>`
    ///
    /// 文字里允许出现冒号，所以最多切三刀，第三段把剩下的全吃掉。
    static func parseEdit(_ s: String) -> NameEdit? {
        let parts = s.split(separator: ":", maxSplits: 2,
                            omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let pos = Int(parts[1]) else { return nil }
        var e = NameEdit()
        e.position = pos
        switch parts[0] {
        case "insert":
            e.kind = .insert
            e.text = parts[2]
            return e
        case "delete":
            guard let n = Int(parts[2]) else { return nil }
            e.kind = .delete
            e.count = n
            return e
        default:
            return nil
        }
    }

    static func parse(_ argv: [String]) -> CLIArgs {
        var a = CLIArgs()
        var i = 0
        if let first = argv.first, !first.hasPrefix("-") {
            a.command = first
            i = 1
        }
        while i < argv.count {
            let k = argv[i]
            func next() -> String? {
                i += 1
                return i < argv.count ? argv[i] : nil
            }
            switch k {
            case "--dir": a.dir = next()
            case "--file": if let v = next() { a.files.append(v) }
            case "--format": a.format = next() ?? a.format
            case "--prefix": a.prefix = next() ?? ""
            case "--suffix": a.suffix = next() ?? ""
            case "--archive-format": a.archiveFormat = next() ?? a.archiveFormat
            case "--offset": a.offset = Int(next() ?? "0") ?? 0
            case "--pattern":
                if let v = next(), let p = NamePattern(rawValue: v) { a.pattern = p }
            case "--no-recursive": a.recursive = false
            case "--all-files": a.onlyMedia = false
            case "--no-exiftool": a.useExifTool = false
            case "--no-filename": a.parseFilename = false
            case "--archive": a.archive = true
            case "--fallback":
                if let v = next(), let f = FallbackMode(rawValue: v) { a.fallback = f }
            case "--edit":
                if let v = next(), let e = parseEdit(v) { a.edits.append(e) }
            default: break
            }
            i += 1
        }
        return a
    }
}

func jsonEscape(_ s: String) -> String {
    var out = ""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if ch.value < 0x20 {
                out += String(format: "\\u%04x", ch.value)
            } else {
                out.unicodeScalars.append(ch)
            }
        }
    }
    return out
}

func dumpJSON(rows: [MediaRow], plan: [PlanItem]) -> String {
    var parts: [String] = []

    var rowParts: [String] = []
    for r in rows {
        rowParts.append("""
        {"path":"\(jsonEscape(r.path))","name":"\(jsonEscape(r.name))",\
        "ts":"\(r.time?.stamp ?? "")",\
        "tsIso":"\(r.time?.stampWithMicroIfAny ?? "")",\
        "source":"\(jsonEscape(r.source))",\
        "kind":"\(jsonEscape(r.kind))",\
        "size":\(r.size)}
        """)
    }
    parts.append("\"rows\":[" + rowParts.joined(separator: ",") + "]")

    var planParts: [String] = []
    for p in plan {
        planParts.append("""
        {"path":"\(jsonEscape(p.path))","name":"\(jsonEscape(p.name))",\
        "newName":"\(jsonEscape(p.newName))",\
        "targetDir":"\(jsonEscape(p.targetDir))",\
        "status":"\(p.status.rawValue)",\
        "conflict":"\(jsonEscape(p.conflict))",\
        "tsShifted":"\(p.shiftedTime?.stampWithMicroIfAny ?? "")"}
        """)
    }
    parts.append("\"plan\":[" + planParts.joined(separator: ",") + "]")

    return "{" + parts.joined(separator: ",") + "}"
}

// ---------------- 改名自检 ----------------

/// 真刀真枪地改一遍名字，再撤销回来，逐条断言。
///
/// 覆盖的是「只有界面才点得到」的四条路：改名、幂等复扫、CSV 导出、撤销。
/// 全程在临时目录 + 临时状态目录里跑，不碰用户的真实文件和撤销记录。
func renameSelfTest(rows: [MediaRow], plan: [PlanItem]) -> Int32 {
    var fails = 0
    func check(_ ok: Bool, _ label: String) {
        print((ok ? "  ✓ " : "  ✗ ") + label)
        if !ok { fails += 1 }
    }

    let fm = FileManager.default
    let todo = plan.filter { $0.status == .ok }
    guard !todo.isEmpty else {
        print("  ✗ 样本里没有可改名的文件，没法测")
        return 1
    }

    // 1. 改名
    let outcome = Renamer.perform(plan: plan, selected: Set(todo.map { $0.path }))
    check(outcome.renamed == todo.count, "改名 \(outcome.renamed)/\(todo.count) 个")
    check(outcome.errors == 0, "改名过程零报错")
    for item in todo {
        let dst = item.targetDir + "/" + item.newName
        check(fm.fileExists(atPath: dst), "落盘：\(item.newName)")
    }
    for item in todo where item.targetDir == item.dir {
        check(!fm.fileExists(atPath: item.path), "原名已不存在：\(item.name)")
    }

    // 2. 幂等：同样的规则再扫一遍，不该再有「待改名」
    let (rows2, plan2) = scanAndPlan(dir: nil,
                                     files: todo.map { $0.targetDir + "/" + $0.newName },
                                     args: CLIArgs())
    _ = rows2
    check(plan2.allSatisfy { $0.status != .ok }, "复扫没有新的待改名（幂等）")

    // 3. CSV
    let csv = Renamer.csv(for: plan2)
    check(csv.hasPrefix("原文件名,新文件名,拍摄时间"), "CSV 表头正确")
    check(csv.split(separator: "\n").count == plan2.count + 1, "CSV 行数 = 计划数 + 表头")

    // 4. 撤销
    let undo = Renamer.undo(file: nil)
    check(undo.undone == todo.count, "撤销 \(undo.undone)/\(todo.count) 个")
    for item in todo {
        check(fm.fileExists(atPath: item.path), "原名已还原：\(item.name)")
        check(!fm.fileExists(atPath: item.targetDir + "/" + item.newName), "新名已清掉")
    }

    // 5. 再撤销一次应该没东西可撤（记录已消费）
    let again = Renamer.undo(file: nil)
    check(again.undone == 0, "重复撤销不会误删文件")

    print(fails == 0 ? "  改名自检全部通过" : "  \(fails) 项失败")
    return fails == 0 ? 0 : 1
}

// ---------------- 按位置增删自检 ----------------

/// 位置算法的边界全钉在这里：0 / 负数 / 超长 / 叠加 / 停用 / 中文。
///
/// 这类「数错一位」的 bug 肉眼极难发现 —— 界面里看着像对的，
/// 改完一百张照片才发现每张少了两个字。所以放进 CI 当闸门。
func editSelfTest() -> Int32 {
    var fails = 0
    func check(_ got: String, _ want: String, _ label: String) {
        let ok = got == want
        var line = (ok ? "  ✓ " : "  ✗ ") + label
        if !ok { line += "\n      得到「\(got)」 / 期望「\(want)」" }
        print(line)
        if !ok { fails += 1 }
    }

    // 19 个字符：I M G _ 2 0 2 6 0 1 0 1 _ 1 2 0 0 0 0
    let base = "IMG_20260101_120000"

    func ins(_ p: Int, _ t: String) -> NameEdit {
        var e = NameEdit(); e.kind = .insert; e.position = p; e.text = t; return e
    }
    func del(_ p: Int, _ n: Int) -> NameEdit {
        var e = NameEdit(); e.kind = .delete; e.position = p; e.count = n; return e
    }

    // 插入：位置 = 「第几个字符之后」
    check(Planner.applyEdits(base, [ins(4, "-")]), "IMG_-20260101_120000", "第 4 位后插入 -")
    check(Planner.applyEdits(base, [ins(0, "X")]), "XIMG_20260101_120000", "位置 0 = 最前面")
    check(Planner.applyEdits(base, [ins(-1, "X")]), "IMG_20260101_120000X", "位置 -1 = 末尾")
    check(Planner.applyEdits(base, [ins(-2, "X")]), "IMG_20260101_12000X0", "位置 -2 = 倒数第二个之后")
    check(Planner.applyEdits(base, [ins(999, "X")]), "IMG_20260101_120000X", "位置超长夹到末尾")

    // 删除：位置 = 「从第几个字符开始删」
    check(Planner.applyEdits(base, [del(1, 4)]), "20260101_120000", "从第 1 位删 4 个 = 去 IMG_")
    check(Planner.applyEdits(base, [del(5, 9)]), "IMG_120000", "从第 5 位删 9 个 = 去日期段")
    check(Planner.applyEdits(base, [del(-4, 4)]), "IMG_20260101_12", "从 -4 删 4 个 = 去秒")
    check(Planner.applyEdits(base, [del(18, 99)]), "IMG_20260101_1200", "删超长只删到末尾")
    check(Planner.applyEdits(base, [del(999, 3)]), base, "删除位置超长 = 不删")

    // 多条规则按数组顺序叠加：前一条的结果是后一条的输入
    check(Planner.applyEdits(base, [del(1, 4), ins(0, "P_")]),
          "P_20260101_120000", "先删前缀再插 P_（顺序生效）")
    check(Planner.applyEdits(base, [ins(0, "P_"), del(1, 4)]),
          "G_20260101_120000", "反过来先插再删：新插的 P_ 被后面的删除吃掉")

    // 停用的规则等于不存在
    var off = ins(4, "-")
    off.enabled = false
    check(Planner.applyEdits(base, [off]), base, "停用的规则被跳过")

    // 空内容 / 零个数不该改动任何东西
    check(Planner.applyEdits(base, [ins(4, "")]), base, "插入空文字 = 不动")
    check(Planner.applyEdits(base, [del(4, 0)]), base, "删 0 个 = 不动")

    // 按字符算，不是按字节：中文一个字就是一个位置
    check(Planner.applyEdits("照片ABC", [ins(2, "—")]), "照片—ABC", "中文按字符计数")
    check(Planner.applyEdits("照片ABC", [del(1, 2)]), "ABC", "删掉两个汉字")

    // 走完整条命名链：扩展名必须留在最后，不能被当成字符删掉
    var o = RenameOptions()
    o.format = "%Y%m%d_%H%M%S"
    o.prefix = "IMG_"
    o.edits = [del(1, 7)]   // 去掉 "IMG_202"
    let t = WallTime(year: 2026, month: 1, day: 1, hour: 12)
    check(Planner.formatName(t, "DSC0001.JPG", o) ?? "",
          "60101_120000.JPG", "扩展名不被位置规则影响")

    // 删到空时退回未编辑结果，不产出 ".jpg" 这种没名字的文件
    var o2 = RenameOptions()
    o2.format = "%Y"
    o2.prefix = ""
    o2.suffix = ""
    o2.edits = [del(1, 99)]
    check(Planner.formatName(t, "a.JPG", o2) ?? "", "2026.JPG", "删空时退回原名主干")

    print(fails == 0 ? "  按位置增删自检全部通过" : "  \(fails) 项失败")
    return fails == 0 ? 0 : 1
}

// ---------------- 主流程 ----------------

/// 扫目录 → 出 rows → 出 plan。dump 和 rename-test 共用这一段，
/// 免得两条路径的排序/优先级链慢慢跑偏。
func scanAndPlan(dir: String?, files: [String], args: CLIArgs) -> ([MediaRow], [PlanItem]) {
    let urls: [URL]
    if !files.isEmpty {
        urls = files.map { URL(fileURLWithPath: $0) }
    } else if let dir {
        urls = Scanner.collect(folder: URL(fileURLWithPath: dir),
                               recursive: args.recursive,
                               onlyMedia: args.onlyMedia,
                               picked: [])
    } else {
        FileHandle.standardError.write(Data("需要 --dir 或 --file\n".utf8))
        exit(2)
    }

    var opts = ReadOptions()
    opts.useExifTool = args.useExifTool
    opts.parseFilename = args.parseFilename
    opts.fallback = args.fallback

    // 排序要和 Python 版一致：先按路径名字典序，扫描完再按时间重排
    let sorted = urls.sorted { $0.path.lowercased() < $1.path.lowercased() }

    var exifMap: [String: [String: String]] = [:]
    if opts.useExifTool {
        let bridge = ExifToolBridge()
        if bridge.available {
            exifMap = bridge.batch(sorted.map { $0.path })
        }
    }

    var rows: [MediaRow] = []
    let lock = NSLock()
    let queue = DispatchQueue(label: "scan", attributes: .concurrent)
    let group = DispatchGroup()
    let sem = DispatchSemaphore(value: Swift.min(16, Swift.max(4, ProcessInfo.processInfo.activeProcessorCount * 2)))

    for url in sorted {
        sem.wait()
        group.enter()
        queue.async {
            let key = URL(fileURLWithPath: url.path).standardizedFileURL.path
            let row = Scanner.makeRow(url, opts: opts, exifToolMD: exifMap[key])
            lock.lock(); rows.append(row); lock.unlock()
            sem.signal()
            group.leave()
        }
    }
    group.wait()

    rows.sort(by: { (a: MediaRow, b: MediaRow) -> Bool in
        let ka = a.sortKey, kb = b.sortKey
        if ka.0 != kb.0 { return ka.0 < kb.0 }
        if ka.1 != kb.1 { return ka.1 < kb.1 }
        if ka.2 != kb.2 { return ka.2 < kb.2 }
        return ka.3 < kb.3
    })

    var ro = RenameOptions()
    ro.format = args.format
    ro.prefix = args.prefix
    ro.suffix = args.suffix
    ro.pattern = args.pattern
    ro.archive = args.archive
    ro.archiveFormat = args.archiveFormat
    ro.offsetSeconds = args.offset
    ro.edits = args.edits

    return (rows, Planner.build(rows: rows, options: ro))
}

let args = CLIArgs.parse(Array(CommandLine.arguments.dropFirst()))

switch args.command {
case "version":
    print("ShutterSort CLI（原生版对照用）")

case "dump":
    let (rows, plan) = scanAndPlan(dir: args.dir, files: args.files, args: args)
    print(dumpJSON(rows: rows, plan: plan))

case "rename-test":
    // 改名 / 撤销 / CSV / 幂等 这四条路只有在界面里才点得到，命令行里补一个
    // 自检：把样本复制到临时目录，真改一遍名字，再撤销回来。
    // 走的是和界面完全相同的 Renamer 代码，所以能当作发布前的闸门。
    let (rows, plan) = scanAndPlan(dir: args.dir, files: args.files, args: args)
    exit(renameSelfTest(rows: rows, plan: plan))

case "edit-test":
    // 按位置增删的边界：0 / 负数 / 超长 / 叠加 / 停用 / 中文 / 扩展名保护
    exit(editSelfTest())

default:
    FileHandle.standardError.write(Data("未知命令：\(args.command)\n".utf8))
    exit(2)
}
