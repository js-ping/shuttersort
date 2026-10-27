import Foundation

/// 命令行入口，只用于「Swift 版 vs Python 版」逐字段对照。
///
/// 存在的意义：解析器是重写的，肉眼看着对不代表真的对。用同一批样本分别跑
/// 两个版本，把 ts / tsIso / source / newName 全量比一遍，差异必须为零。
///
/// 用法：
///   shuttersort-cli dump --dir /path [--recursive] [--format F] [--prefix P]
///                        [--pattern 仅日期] [--offset 28800] [--no-exiftool]
///                        [--edit insert:8:-] [--edit replace:IMG_:]
///
///   --edit 的完整语法见 `CLIArgs.parseRule` 上面的注释。

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
    var rules: [NameRule] = []

    /// 规则语法（字段之间用冒号分隔，第三段吃掉剩下的全部）：
    ///
    ///     insert:<位置>:<文字>              在第 N 位后插入
    ///     insert@before:<锚点>:<文字>        在某段文字前插入
    ///     insert@after:<锚点>:<文字>         在某段文字后插入
    ///     delete:<位置>:<个数|end>           从第 N 位删若干个；end = 删到末尾
    ///     replace:<找>:<换成>                替换（「换成」留空 = 移除）
    ///     strip:<space|underscore|dash|brackets|symbols|digits>
    ///     case:<lower|upper|capitalize|sentence>
    static func parseRule(_ s: String) -> NameRule? {
        let parts = s.split(separator: ":", maxSplits: 2,
                            omittingEmptySubsequences: false).map(String.init)
        guard let head = parts.first else { return nil }
        let body = Array(parts.dropFirst())

        var r = NameRule()

        switch head {
        case "insert":
            guard body.count == 2, let pos = Int(body[0]) else { return nil }
            r.kind = .insert
            r.anchor = .position
            r.position = pos
            r.text = body[1]
            return r

        case "insert@before", "insert@after":
            guard body.count == 2, !body[0].isEmpty else { return nil }
            r.kind = .insert
            r.anchor = head == "insert@before" ? .beforeText : .afterText
            r.anchorText = body[0]
            r.text = body[1]
            return r

        case "delete":
            guard body.count == 2, let pos = Int(body[0]) else { return nil }
            r.kind = .delete
            r.position = pos
            if body[1] == "end" {
                r.toEnd = true
            } else if let n = Int(body[1]) {
                r.count = n
            } else {
                return nil
            }
            return r

        case "replace":
            guard body.count == 2 else { return nil }
            r.kind = .replace
            r.text = body[0]
            r.replacement = body[1]
            return r

        case "strip":
            guard let c = NameRule.Charset.fromKey(body.first ?? "") else { return nil }
            r.kind = .strip
            r.charset = c
            return r

        case "case":
            guard let s2 = NameRule.CaseStyle.fromKey(body.first ?? "") else { return nil }
            r.kind = .changeCase
            r.caseStyle = s2
            return r

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
                if let v = next(), let r = parseRule(v) { a.rules.append(r) }
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

// ---------------- 改名规则自检 ----------------

/// 五类规则的边界全钉在这里：0 / 负数 / 超长 / 锚点找不到 / 叠加 / 停用 /
/// 中文按字符计数 / 扩展名保护 / 删空回退。
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

    func ins(_ p: Int, _ t: String) -> NameRule {
        var r = NameRule(); r.kind = .insert; r.anchor = .position
        r.position = p; r.text = t; return r
    }
    func insBefore(_ anchor: String, _ t: String) -> NameRule {
        var r = NameRule(); r.kind = .insert; r.anchor = .beforeText
        r.anchorText = anchor; r.text = t; return r
    }
    func insAfter(_ anchor: String, _ t: String) -> NameRule {
        var r = NameRule(); r.kind = .insert; r.anchor = .afterText
        r.anchorText = anchor; r.text = t; return r
    }
    func del(_ p: Int, _ n: Int) -> NameRule {
        var r = NameRule(); r.kind = .delete; r.position = p; r.count = n; return r
    }
    func delToEnd(_ p: Int) -> NameRule {
        var r = NameRule(); r.kind = .delete; r.position = p; r.toEnd = true; return r
    }
    func rep(_ find: String, _ to: String, cs: Bool = true) -> NameRule {
        var r = NameRule(); r.kind = .replace
        r.text = find; r.replacement = to; r.caseSensitive = cs; return r
    }
    func strip(_ c: NameRule.Charset) -> NameRule {
        var r = NameRule(); r.kind = .strip; r.charset = c; return r
    }
    func changeCase(_ s: NameRule.CaseStyle) -> NameRule {
        var r = NameRule(); r.kind = .changeCase; r.caseStyle = s; return r
    }

    // ---- 插入：按位置
    check(Planner.applyRules(base, [ins(4, "-")]), "IMG_-20260101_120000", "插入：第 4 位后")
    check(Planner.applyRules(base, [ins(0, "X")]), "XIMG_20260101_120000", "插入：位置 0 = 最前面")
    check(Planner.applyRules(base, [ins(-1, "X")]), "IMG_20260101_120000X", "插入：位置 -1 = 末尾")
    check(Planner.applyRules(base, [ins(999, "X")]), "IMG_20260101_120000X", "插入：位置超长夹到末尾")

    // ---- 插入：按锚点（不用数位，日期格式变了也不会错）
    check(Planner.applyRules(base, [insAfter("IMG_", "旅行_")]),
          "IMG_旅行_20260101_120000", "插入：锚点「IMG_」后")
    check(Planner.applyRules(base, [insBefore("20260101", "拍于")]),
          "IMG_拍于20260101_120000", "插入：锚点「20260101」前")
    check(Planner.applyRules(base, [insBefore("找不到的", "X")]),
          base, "插入：锚点不存在 → 整条不生效")

    // ---- 删除
    check(Planner.applyRules(base, [del(1, 4)]), "20260101_120000", "删除：第 1 位删 4 个 = 去 IMG_")
    check(Planner.applyRules(base, [del(5, 9)]), "IMG_120000", "删除：第 5 位删 9 个 = 去日期段")
    check(Planner.applyRules(base, [del(-4, 4)]), "IMG_20260101_12", "删除：-4 位删 4 个 = 去秒")
    check(Planner.applyRules(base, [del(18, 99)]), "IMG_20260101_1200", "删除：数量超长只删到末尾")
    check(Planner.applyRules(base, [del(999, 3)]), base, "删除：位置超长 = 不删")
    check(Planner.applyRules(base, [delToEnd(13)]), "IMG_20260101", "删除：第 13 位删到末尾")
    check(Planner.applyRules(base, [delToEnd(1)]), "", "删除：第 1 位删到末尾 = 全空")

    // ---- 替换 / 移除
    check(Planner.applyRules(base, [rep("IMG_", "")]), "20260101_120000", "替换：换成留空 = 移除")
    check(Planner.applyRules(base, [rep("IMG_", "照片_")]), "照片_20260101_120000", "替换：换成照片_")
    check(Planner.applyRules(base, [rep("img_", "", cs: false)]),
          "20260101_120000", "替换：不区分大小写能命中")
    check(Planner.applyRules(base, [rep("img_", "", cs: true)]),
          base, "替换：区分大小写时找不到就不动")
    check(Planner.applyRules(base, [rep("不存在", "")]), base, "替换：找不到就不动")

    // ---- 剥离字符
    check(Planner.applyRules(base, [strip(.underscore)]),
          "IMG20260101120000", "剥离：下划线")
    check(Planner.applyRules("a-b—c", [strip(.dash)]), "abc", "剥离：连字符（含全角长破折号）")
    check(Planner.applyRules("a b\u{3000}c", [strip(.space)]),
          "abc", "剥离：空格（含全角）")
    check(Planner.applyRules("IMG_123", [strip(.digits)]), "IMG_", "剥离：数字")
    check(Planner.applyRules("题(注)【补】", [strip(.brackets)]), "题注补", "剥离：中英文括号")

    // ---- 大小写
    check(Planner.applyRules("IMG_ABC", [changeCase(.lower)]), "img_abc", "大小写：全小写")
    check(Planner.applyRules("img_abc", [changeCase(.upper)]), "IMG_ABC", "大小写：全大写")
    check(Planner.applyRules("img_abc", [changeCase(.capitalize)]),
          "Img_Abc", "大小写：每词首字母大写")
    check(Planner.applyRules("IMG_ABC", [changeCase(.sentence)]),
          "Img_abc", "大小写：首字母大写、其余小写")

    // ---- 多条叠加：前一条的结果是后一条的输入
    check(Planner.applyRules(base, [del(1, 4), ins(0, "P_")]),
          "P_20260101_120000", "叠加：先删 IMG_ 再插 P_")
    check(Planner.applyRules(base, [rep("IMG_", ""), strip(.underscore)]),
          "20260101120000", "叠加：先移除 IMG_ 再剥离下划线")
    check(Planner.applyRules(base, [ins(0, "P_"), del(1, 4)]),
          "G_20260101_120000", "叠加：顺序反过来，新插的 P_ 被后面的删除吃掉")

    // ---- 停用
    var off = ins(4, "-")
    off.enabled = false
    check(Planner.applyRules(base, [off]), base, "停用的规则被跳过")

    // ---- 空输入不该改动
    check(Planner.applyRules(base, [ins(4, "")]), base, "插入空文字 = 不动")
    check(Planner.applyRules(base, [rep("", "X")]), base, "查找空文字 = 不动")

    // ---- 中文按字符算，不是按字节
    check(Planner.applyRules("照片ABC", [ins(2, "—")]), "照片—ABC", "中文：按字符计数")
    check(Planner.applyRules("照片ABC", [del(1, 2)]), "ABC", "中文：删掉两个汉字")

    // ---- 走完整条命名链：扩展名必须留在最后
    var o = RenameOptions()
    o.format = "%Y%m%d_%H%M%S"
    o.prefix = "IMG_"
    o.rules = [del(1, 7)]   // 去掉 "IMG_202"
    let t = WallTime(year: 2026, month: 1, day: 1, hour: 12)
    check(Planner.formatName(t, "DSC0001.JPG", o) ?? "",
          "60101_120000.JPG", "扩展名不被规则链影响")

    // ---- 删到空时退回未编辑结果，不产出 ".jpg" 这种没名字的文件
    var o2 = RenameOptions()
    o2.format = "%Y"
    o2.prefix = ""
    o2.suffix = ""
    o2.rules = [delToEnd(1)]
    check(Planner.formatName(t, "a.JPG", o2) ?? "", "2026.JPG", "删空时退回原名主干")

    print(fails == 0 ? "  改名规则自检全部通过" : "  \(fails) 项失败")
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
    ro.rules = args.rules

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
    // 改名规则的边界：插入（位置/锚点）、删除（含到末尾）、替换、剥离、大小写，
    // 外加 0 / 负数 / 超长 / 叠加 / 停用 / 中文 / 扩展名保护 / 删空回退
    exit(editSelfTest())

default:
    FileHandle.standardError.write(Data("未知命令：\(args.command)\n".utf8))
    exit(2)
}
