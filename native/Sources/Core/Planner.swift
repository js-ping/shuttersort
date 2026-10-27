import Foundation

/// 命名计划：算出每个文件的目标名，消解冲突，判定状态。
///
/// 两轮设计不是多余的：
///  · 第一轮先算出所有目标名和「哪些旧名字会被腾出来」
///  · 第二轮消解冲突时排除「文件自身」和「本轮即将腾出的旧名」
/// 这样重复执行结果稳定 —— 已经改好的文件再扫一次显示「无需改动」，不会被再改一次。
enum Planner {

    static func build(rows: [MediaRow], options o: RenameOptions) -> [PlanItem] {
        // ±10 年以外的偏移当作误输入，直接忽略
        var shift = o.offsetSeconds
        if abs(shift) > 86_400 * 3660 { shift = 0 }
        let archiveFmt = o.archiveFormat.trimmingCharacters(in: .whitespaces).isEmpty
            ? "%Y/%Y-%m" : o.archiveFormat
        let fmt = o.format.trimmingCharacters(in: .whitespaces).isEmpty ? "%Y%m%d_%H%M%S" : o.format

        var opts = o
        opts.format = fmt
        opts.archiveFormat = archiveFmt

        var used: [String: Set<String>] = [:]
        var staged: [(row: MediaRow, newName: String?, targetDir: String, time: WallTime?)] = []
        var vacating = Set<String>()

        // ---- 第一轮 ----
        for row in rows {
            let shifted = row.time.map { shift == 0 ? $0 : $0.adding(seconds: shift) }
            let newName = formatName(shifted, row.name, opts)
            var targetDir = row.dir
            if newName != nil, opts.archive, let t = shifted {
                let sub = PyFormat.strftime(archiveFmt, t)
                if !sub.isEmpty { targetDir = row.dir + "/" + sub }
            }
            staged.append((row, newName, targetDir, shifted))
            if let n = newName, !(n == row.name && targetDir == row.dir) {
                vacating.insert(row.path)
            }
        }

        // ---- 第二轮 ----
        var plan: [PlanItem] = []
        for (index, tuple) in staged.enumerated() {
            let (row, newName, targetDir, shifted) = tuple
            var item = PlanItem(
                path: row.path, name: row.name, dir: row.dir,
                size: row.size, sizeText: row.sizeText, ext: row.ext,
                source: row.source, kind: row.kind, note: row.note,
                duration: row.duration, exif: row.exif,
                originalTime: row.time, shiftedTime: shifted,
                newName: "", targetDir: targetDir,
                status: .skip, conflict: "", order: index
            )

            guard let newName else {
                if !opts.onlyRenamable { plan.append(item) }
                continue
            }

            var ignore = vacating
            ignore.insert(row.path)
            var bucket = used[targetDir] ?? []
            let unique = uniqueTarget(dir: targetDir, name: newName, used: &bucket, ignore: ignore)
            used[targetDir] = bucket

            let conflict = unique == newName ? "" : "重名加后缀"
            let unchanged = (unique == row.name && targetDir == row.dir)

            item.newName = unique
            item.status = unchanged ? .same : .ok
            item.conflict = conflict
            plan.append(item)
        }

        // 待改名的排前面；同组内按（校正后的）时间字符串比较 ——
        // 定宽 ISO 的字典序就是时间序，没有时间的空串自然排最前。
        // 键完全相同时用原始序号兜底，保证结果稳定（Python 的 Timsort 本来就稳定）。
        plan.sort { a, b in
            let aOK = a.status == .ok, bOK = b.status == .ok
            if aOK != bOK { return aOK }
            if a.sortStamp != b.sortStamp { return a.sortStamp < b.sortStamp }
            return a.order < b.order
        }
        return plan
    }

    static func stats(_ plan: [PlanItem]) -> PlanStats {
        var s = PlanStats()
        s.total = plan.count
        for item in plan {
            switch item.status {
            case .ok: s.rename += 1
            case .same: s.same += 1
            case .skip: s.skip += 1
            }
        }
        return s
    }

    /// 对应 `format_new_name`
    static func formatName(_ t: WallTime?, _ original: String, _ o: RenameOptions) -> String? {
        let ns = original as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        let extPart = ext.isEmpty ? "" : "." + ext

        // 先把主干拼出来，扩展名单独留着 —— 后面的位置编辑只动主干
        var stem: String
        if o.pattern == .originalOnly {
            stem = o.prefix + base + o.suffix
        } else {
            guard let t else { return nil }
            let stamp = PyFormat.strftime(o.format, t)
            guard !stamp.isEmpty else { return nil }

            switch o.pattern {
            case .dateOriginal:
                stem = o.prefix + stamp + "_" + base + o.suffix
            case .originalDate:
                stem = o.prefix + base + "_" + stamp + o.suffix
            default:
                stem = o.prefix + stamp + o.suffix
            }
        }

        // 规则链：在「前缀 + 日期 + 后缀」全部拼完之后再动，
        // 这样连前缀也能被删掉（例如去掉 `IMG_`）
        if !o.rules.isEmpty {
            let edited = applyRules(stem, o.rules)
            // 删到空会产出 `.jpg` 这种没名字的文件，退回未编辑的结果更安全
            if !edited.isEmpty { stem = edited }
        }
        return stem + extPart
    }

    // MARK: - 规则链

    /// 把一串规则依次作用到文件名主干上。
    ///
    /// 前一条的结果是后一条的输入，所以顺序是有意义的 ——
    /// 「先删 IMG_ 再插日期」和「先插日期再删前 4 位」结果完全不同。
    static func applyRules(_ stem: String, _ rules: [NameRule]) -> String {
        var s = stem
        for r in rules where r.enabled {
            s = applyRule(s, r)
        }
        return s
    }

    static func applyRule(_ stem: String, _ r: NameRule) -> String {
        switch r.kind {
        case .insert:
            return insertRule(stem, r)
        case .delete:
            return deleteRule(stem, r)
        case .replace:
            return replaceRule(stem, r)
        case .strip:
            let drop = r.charset.characters
            return String(stem.filter { !drop.contains($0) })
        case .changeCase:
            return changeCase(stem, r.caseStyle)
        }
    }

    // MARK: 插入

    private static func insertRule(_ stem: String, _ r: NameRule) -> String {
        guard !r.text.isEmpty else { return stem }

        let at: Int
        switch r.anchor {
        case .position:
            at = insertionPoint(r.position, count: stem.count)

        case .beforeText, .afterText:
            guard !r.anchorText.isEmpty,
                  let rng = stem.range(of: r.anchorText,
                                       options: r.caseSensitive ? [] : .caseInsensitive)
            else { return stem }   // 锚点文字不存在 → 这条规则不生效，不瞎插
            let edge = r.anchor == .beforeText ? rng.lowerBound : rng.upperBound
            at = stem.distance(from: stem.startIndex, to: edge)
        }

        let idx = stem.index(stem.startIndex, offsetBy: at)
        return String(stem[..<idx]) + r.text + String(stem[idx...])
    }

    /// 插入点（字符数，0 = 最前）：正数 = 第 N 个字符之后；负数从末尾往前数（-1 = 末尾）
    private static func insertionPoint(_ p: Int, count n: Int) -> Int {
        if p > 0 { return min(p, n) }
        if p < 0 { return max(0, n + p + 1) }
        return 0
    }

    // MARK: 删除

    private static func deleteRule(_ stem: String, _ r: NameRule) -> String {
        let chars = Array(stem)
        guard !chars.isEmpty else { return stem }

        let start = deletionStart(r.position, count: chars.count)
        let end = r.toEnd ? chars.count : min(chars.count, start + max(0, r.count))
        guard start < end else { return stem }

        return String(chars[0..<start] + chars[end...])
    }

    /// 删除起点（0-based）：正数 = 第 N 个字符；负数从末尾数（-1 = 最后一个）
    private static func deletionStart(_ p: Int, count n: Int) -> Int {
        if p > 0 { return min(p - 1, n) }
        if p < 0 { return max(0, n + p) }
        return 0
    }

    // MARK: 替换

    private static func replaceRule(_ stem: String, _ r: NameRule) -> String {
        guard !r.text.isEmpty else { return stem }
        return stem.replacingOccurrences(
            of: r.text,
            with: r.replacement,
            options: r.caseSensitive ? [] : .caseInsensitive
        )
    }

    // MARK: 大小写

    private static func changeCase(_ stem: String, _ style: NameRule.CaseStyle) -> String {
        switch style {
        case .lower:
            return stem.lowercased()
        case .upper:
            return stem.uppercased()
        case .capitalize:
            return stem.capitalized
        case .sentence:
            guard let first = stem.first else { return stem }
            return String(first).uppercased() + stem.dropFirst().lowercased()
        }
    }

    /// 冲突时自动加 `_1` `_2` …，保证目标名唯一。
    /// `ignore` 里的完整路径表示「不算占用」。
    static func uniqueTarget(dir: String, name: String,
                             used: inout Set<String>, ignore: Set<String>) -> String {
        func taken(_ n: String) -> Bool {
            if used.contains(n) { return true }
            let full = dir + "/" + n
            guard FileManager.default.fileExists(atPath: full) else { return false }
            return !ignore.contains(full)
        }

        if !taken(name) {
            used.insert(name)
            return name
        }

        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        let extPart = ext.isEmpty ? "" : "." + ext
        var i = 1
        while true {
            let cand = "\(base)_\(i)\(extPart)"
            if !taken(cand) {
                used.insert(cand)
                return cand
            }
            i += 1
        }
    }
}
