import Foundation

/// 改名执行、撤销记录、历史查询。
enum Renamer {

    /// `~/Library/Application Support/ShutterSort/rename-history`
    /// —— 与 Python 版用同一个目录，撤销记录可以互通。
    static var stateDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ShutterSort")
    }

    static var historyDir: URL { stateDir.appendingPathComponent("rename-history") }

    static func ensureDirs() {
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
    }

    // MARK: - 日志结构

    struct UndoPair: Codable {
        let from: String
        let to: String
        let name: String
    }

    struct UndoLog: Codable {
        let time: String
        let count: Int
        let pairs: [UndoPair]
        let meta: [String: String]
    }

    struct HistoryEntry: Identifiable {
        var id: String { file }
        let file: String
        let time: String
        let count: Int
        let folder: String
        let renamed: Int
    }

    struct RenameOutcome {
        var renamed = 0
        var skipped = 0
        var errors = 0
        var messages: [String] = []
        var logName: String?
    }

    // MARK: - 执行

    /// 只处理 `selected` 里点名的文件；`selected` 为 nil 表示全部。
    /// 关键：拿界面传来的路径去跟扫描结果求交集，不直接信任 —— 否则等于给了
    /// 一个「重命名本机任意文件」的能力。
    static func perform(plan: [PlanItem], selected: Set<String>?) -> RenameOutcome {
        var out = RenameOutcome()
        var todo = plan
        if let selected {
            todo = plan.filter { selected.contains($0.path) }
            if todo.isEmpty {
                out.messages = ["没有选中任何文件"]
                return out
            }
        }

        var pairs: [UndoPair] = []
        let fm = FileManager.default

        for item in todo {
            guard item.status == .ok else {
                out.skipped += 1
                continue
            }
            let src = item.path
            let dst = item.targetDir + "/" + item.newName

            guard fm.fileExists(atPath: src) else {
                out.skipped += 1
                continue
            }
            // 目标已存在且不是同一个文件 → 拒绝，绝不覆盖
            if fm.fileExists(atPath: dst),
               URL(fileURLWithPath: src).resolvingSymlinksInPath().path
                != URL(fileURLWithPath: dst).resolvingSymlinksInPath().path {
                out.errors += 1
                if out.messages.count < 20 {
                    out.messages.append("目标已存在：\((dst as NSString).lastPathComponent)")
                }
                continue
            }

            do {
                if item.targetDir != item.dir {
                    try fm.createDirectory(atPath: item.targetDir,
                                           withIntermediateDirectories: true)
                }
                try fm.moveItem(atPath: src, toPath: dst)
                pairs.append(UndoPair(from: src, to: dst,
                                      name: (src as NSString).lastPathComponent))
                out.renamed += 1
            } catch {
                out.errors += 1
                if out.messages.count < 20 {
                    out.messages.append("\((src as NSString).lastPathComponent)："
                                        + error.localizedDescription)
                }
            }
        }

        out.logName = writeLog(pairs: pairs, renamed: out.renamed)
        return out
    }

    private static func writeLog(pairs: [UndoPair], renamed: Int) -> String? {
        guard !pairs.isEmpty else { return nil }
        ensureDirs()

        let stamp = PyFormat.strftime("%Y%m%d_%H%M%S", PyFormat.now)
        let name = "改名记录_\(stamp).json"
        let log = UndoLog(
            time: PyFormat.strftime("%Y-%m-%d %H:%M:%S", PyFormat.now),
            count: pairs.count,
            pairs: pairs,
            meta: ["renamed": String(renamed)]
        )

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? enc.encode(log) else { return nil }
        do {
            try data.write(to: historyDir.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    // MARK: - 历史与撤销

    static func history(limit: Int = 60) -> [HistoryEntry] {
        let fm = FileManager.default
        guard let list = try? fm.contentsOfDirectory(atPath: historyDir.path) else { return [] }
        let files = list.filter { $0.hasPrefix("改名记录_") && $0.hasSuffix(".json") }.sorted(by: >)

        var out: [HistoryEntry] = []
        for f in files.prefix(limit) {
            let url = historyDir.appendingPathComponent(f)
            guard let data = try? Data(contentsOf: url),
                  let log = try? JSONDecoder().decode(UndoLog.self, from: data) else { continue }
            out.append(HistoryEntry(file: f, time: log.time, count: log.count,
                                    folder: log.meta["folder"] ?? "",
                                    renamed: Int(log.meta["renamed"] ?? "") ?? log.count))
        }
        return out
    }

    struct UndoOutcome {
        var undone = 0
        var failed = 0
        var messages: [String] = []
    }

    /// 撤销。传具体的记录文件名，或留空撤销最近一次。
    static func undo(file: String?) -> UndoOutcome {
        var out = UndoOutcome()
        let fm = FileManager.default

        var target: URL?
        if let file, !file.isEmpty, !file.contains("/") {
            let url = historyDir.appendingPathComponent(file)
            if fm.fileExists(atPath: url.path) { target = url }
        }
        if target == nil {
            let list = (try? fm.contentsOfDirectory(atPath: historyDir.path))?
                .filter { $0.hasPrefix("改名记录_") && $0.hasSuffix(".json") }
                .sorted(by: >) ?? []
            if let first = list.first {
                target = historyDir.appendingPathComponent(first)
            }
        }
        guard let target, let data = try? Data(contentsOf: target),
              let log = try? JSONDecoder().decode(UndoLog.self, from: data) else {
            out.messages = ["没有可撤销的记录"]
            return out
        }

        // 倒序还原：把一个文件改回原名之后，才轮到下一个
        for pair in log.pairs.reversed() {
            guard fm.fileExists(atPath: pair.to) else {
                out.failed += 1
                continue
            }
            if fm.fileExists(atPath: pair.from) {
                out.failed += 1
                if out.messages.count < 20 {
                    out.messages.append("原位置已被占用：\((pair.from as NSString).lastPathComponent)")
                }
                continue
            }
            do {
                let parent = (pair.from as NSString).deletingLastPathComponent
                if !fm.fileExists(atPath: parent) {
                    try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
                }
                try fm.moveItem(atPath: pair.to, toPath: pair.from)
                out.undone += 1
            } catch {
                out.failed += 1
                if out.messages.count < 20 {
                    out.messages.append(error.localizedDescription)
                }
            }
        }
        return out
    }

    // MARK: - 导出 CSV

    static func csv(for plan: [PlanItem]) -> String {
        var lines = ["原文件名,新文件名,拍摄时间,时间戳来源,大小,状态"]
        for item in plan {
            let cols = [
                item.name,
                item.newName.isEmpty ? "" : item.newName,
                item.displayTime?.stampWithMicroIfAny ?? "",
                item.source,
                item.sizeText,
                item.status.text,
            ]
            lines.append(cols.map(escapeCSV).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escapeCSV(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
