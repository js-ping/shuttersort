import Foundation

/// 命令行入口，只用于「Swift 版 vs Python 版」逐字段对照。
///
/// 存在的意义：解析器是重写的，肉眼看着对不代表真的对。用同一批样本分别跑
/// 两个版本，把 ts / tsIso / source / newName 全量比一遍，差异必须为零。
///
/// 用法：
///   shuttersort-cli dump --dir /path [--recursive] [--format F] [--prefix P]
///                        [--pattern 仅日期] [--offset 28800] [--no-exiftool]

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

// ---------------- 主流程 ----------------

let args = CLIArgs.parse(Array(CommandLine.arguments.dropFirst()))

switch args.command {
case "version":
    print("ShutterSort CLI（原生版对照用）")

case "dump":
    let urls: [URL]
    if !args.files.isEmpty {
        urls = args.files.map { URL(fileURLWithPath: $0) }
    } else if let dir = args.dir {
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
    let sem = DispatchSemaphore(value: min(16, max(4, ProcessInfo.processInfo.activeProcessorCount * 2)))

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

    let plan = Planner.build(rows: rows, options: ro)
    print(dumpJSON(rows: rows, plan: plan))

default:
    FileHandle.standardError.write(Data("未知命令：\(args.command)\n".utf8))
    exit(2)
}
