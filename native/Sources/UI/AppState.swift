import AppKit
import Combine
import Foundation
import SwiftUI

/// 界面状态与全部业务动作。
///
/// 设计上刻意把「算」和「显示」分开：`plan` 是派生数据，选项一变就重算，
/// 但加 220ms 防抖 —— 拖数字框时不至于每敲一个字符就全表重排。
@MainActor
final class AppState: ObservableObject {

    // MARK: - 范围

    enum Scope: String {
        case folder, files
    }

    @Published var scope: Scope = .folder
    @Published var folder: URL?
    @Published var pickedFiles: [URL] = []
    @Published var recursive = true
    @Published var onlyMedia = true

    // MARK: - 命名

    @Published var format = "%Y%m%d_%H%M%S"
    @Published var customFormat = ""
    @Published var useCustomFormat = false
    @Published var prefix = "IMG_"
    @Published var suffix = ""
    @Published var pattern: NamePattern = .dateOnly
    @Published var archive = false
    @Published var archiveFormat = "%Y/%Y-%m"
    /// 按位置增删字符的规则列表，空 = 不启用
    @Published var edits: [NameEdit] = []

    // MARK: - 读取

    @Published var useExifTool = true
    @Published var parseFilename = true
    @Published var readXmpSidecar = true
    @Published var readTakeoutJSON = true
    @Published var fallback: FallbackMode = .skip

    // MARK: - 时间校正

    @Published var correctionOn = false
    @Published var corrDays = 0
    @Published var corrHours = 0
    @Published var corrMinutes = 0

    var offsetSeconds: Int {
        guard correctionOn else { return 0 }
        return corrDays * 86_400 + corrHours * 3600 + corrMinutes * 60
    }

    // MARK: - 数据

    @Published private(set) var rows: [MediaRow] = []
    @Published private(set) var plan: [PlanItem] = []
    @Published private(set) var scanning = false
    @Published var progress = 0.0
    @Published var stageText = ""

    @Published var selection = Set<String>()
    @Published var filter = ""
    @Published var statusFilter: StatusFilter = .all

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "全部状态"
        case rename = "待改名"
        case same = "无需改动"
        case skip = "无时间戳"
        var id: String { rawValue }
    }

    // MARK: - 弹窗

    @Published var showHelp = false
    @Published var showHistory = false
    @Published var showConfirm = false
    @Published var showCalibrate = false
    @Published var detailItem: PlanItem?
    @Published var alertText: String?
    @Published var toastText: String?

    @Published private(set) var history: [Renamer.HistoryEntry] = []
    @Published private(set) var exifToolInfo = ""

    var exifToolAvailable: Bool { exifTool.available }
    var exifToolVersion: String { exifTool.version.isEmpty ? "" : "v" + exifTool.version }

    private let exifTool = ExifToolBridge()
    private var debounceTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var scanToken = 0

    init() {
        exifToolInfo = exifTool.infoText
        if !exifTool.available { useExifTool = false }
        prepareFromLaunchArguments()
    }

    /// 支持 `--scan <路径>` 启动即扫（开发与自动化验证用，不影响正常使用）。
    ///
    /// 还支持几个辅助参数，同样只给自动化验证用：
    /// `--offset <分钟>` 预置时间校正、`--sheet <名字>` 扫完自动开某个弹窗、
    /// `--keep-selection` 保留扫描后的默认全选以外的情况（`--none` 清空选择）。
    private func prepareFromLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments

        if let i = args.firstIndex(of: "--offset"), i + 1 < args.count,
           let minutes = Int(args[i + 1]) {
            correctionOn = minutes != 0
            corrDays = minutes / 1_440
            corrHours = (minutes % 1_440) / 60
            corrMinutes = minutes % 60
        }
        if let i = args.firstIndex(of: "--sheet"), i + 1 < args.count {
            pendingSheet = args[i + 1]
        }
        if args.contains("--none") { pendingClearSelection = true }

        guard let i = args.firstIndex(of: "--scan"), i + 1 < args.count else { return }
        let path = args[i + 1]
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }
        let url = URL(fileURLWithPath: path)
        if isDir.boolValue {
            folder = url
            scope = .folder
        } else {
            pickedFiles = [url]
            scope = .files
        }
        autoScanOnLaunch = true
    }

    /// 启动参数里排队的弹窗，扫描完成后再开（那时才有 plan 数据）
    private var pendingSheet: String?
    private var pendingClearSelection = false

    /// 扫描完成、plan 已生成后调用
    private func runPendingSheet() {
        if pendingClearSelection { selection = [] }
        guard let name = pendingSheet else { return }
        pendingSheet = nil
        switch name {
        case "detail":
            if let first = visiblePlan.first ?? plan.first { detailItem = first }
        case "confirm":
            showConfirm = true
        case "history":
            loadHistory()
        case "calibrate":
            if let first = plan.first(where: { $0.status == .ok }) {
                selection = [first.path]
                showCalibrate = true
            }
        case "help":
            showHelp = true
        default:
            break
        }
    }

    /// 启动参数要求自动扫描时，由界面在第一帧之后触发
    var autoScanOnLaunch = false

    // MARK: - 派生

    /// 当前筛选后的行
    var visiblePlan: [PlanItem] {
        var list = plan
        if statusFilter != .all {
            let want: PlanStatus = switch statusFilter {
            case .rename: .ok
            case .same: .same
            case .skip: .skip
            case .all: .ok
            }
            list = list.filter { $0.status == want }
        }
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q)
                    || $0.newName.lowercased().contains(q)
                    || $0.source.lowercased().contains(q)
            }
        }
        return list
    }

    var stats: PlanStats { Planner.stats(plan) }

    var selectedRenamable: Int {
        plan.filter { $0.status == .ok && selection.contains($0.path) }.count
    }

    var hasResult: Bool { !plan.isEmpty }

    var scopeDescription: String {
        switch scope {
        case .folder:
            return folder?.path ?? "还没选文件夹"
        case .files:
            if pickedFiles.isEmpty { return "还没选文件" }
            let dirs = Set(pickedFiles.map { $0.deletingLastPathComponent().path })
            return "已选 \(pickedFiles.count) 个文件 · 分布在 \(dirs.count) 个文件夹"
        }
    }

    // MARK: - 选项快照

    private var readOptions: ReadOptions {
        var o = ReadOptions()
        o.useExifTool = useExifTool
        o.parseFilename = parseFilename
        o.readXmpSidecar = readXmpSidecar
        o.readTakeoutJSON = readTakeoutJSON
        o.fallback = fallback
        return o
    }

    private var renameOptions: RenameOptions {
        var o = RenameOptions()
        o.format = useCustomFormat && !customFormat.trimmingCharacters(in: .whitespaces).isEmpty
            ? customFormat : format
        o.prefix = prefix
        o.suffix = suffix
        o.pattern = pattern
        o.archive = archive
        o.archiveFormat = archiveFormat
        o.offsetSeconds = offsetSeconds
        o.edits = edits
        return o
    }

    // MARK: - 选路径

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择一个放照片 / 视频的文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        scope = .folder
        pickedFiles = []
        startScan()
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "选择"
        panel.message = "可以按住 ⌘ 一次选多个，也能跨文件夹混选"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        pickedFiles = panel.urls
        scope = .files
        folder = nil
        startScan()
    }

    func clearScope() {
        folder = nil
        pickedFiles = []
        rows = []
        plan = []
        selection = []
        stageText = ""
        progress = 0
    }

    /// 接收拖进来的文件
    func addDropped(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if scope == .folder, let folder,
           urls.allSatisfy({ $0.deletingLastPathComponent().path == folder.path }) {
            // 本来就在当前目录里：退化成「把这几行选中」
            let names = Set(urls.map { $0.lastPathComponent })
            selection = Set(plan.filter { names.contains($0.name) }.map { $0.path })
            showToast("已在列表里选中 \(selection.count) 个文件")
            return
        }
        scope = .files
        folder = nil
        // 追加，去重
        var seen = Set(pickedFiles.map { $0.path })
        var merged = pickedFiles
        for u in urls where !seen.contains(u.path) {
            merged.append(u)
            seen.insert(u.path)
        }
        pickedFiles = merged
        startScan()
    }

    // MARK: - 扫描

    func startScan() {
        let picked = scope == .files ? pickedFiles : []
        let dir = scope == .folder ? folder : nil
        guard dir != nil || !picked.isEmpty else { return }

        scanToken += 1
        let token = scanToken
        scanning = true
        progress = 0
        stageText = exifTool.available && useExifTool ? "正在用 exiftool 批量读取元数据…" : "正在解析每个文件…"

        let opts = readOptions
        let rec = recursive
        let media = onlyMedia
        let bridge = exifTool
        let useET = useExifTool && exifTool.available

        Task.detached(priority: .userInitiated) { [weak self] in
            let rows = AppState.scanSync(folder: dir, picked: picked, recursive: rec,
                                         onlyMedia: media, opts: opts,
                                         bridge: bridge, useET: useET) { done, total in
                Task { @MainActor [weak self] in
                    guard let self, self.scanToken == token else { return }
                    self.progress = total == 0 ? 1 : Double(done) / Double(total)
                }
            }

            await MainActor.run { [weak self] in
                guard let self, self.scanToken == token else { return }
                self.rows = rows
                self.scanning = false
                self.progress = 1
                self.stageText = rows.isEmpty ? "这个范围里没有可处理的文件" : "完成"
                self.rebuildPlan(immediate: true)
                self.selection = Set(self.plan.filter { $0.status == .ok }.map { $0.path })
                self.runPendingSheet()
            }
        }
    }

    /// 真正的扫描，同步执行。
    ///
    /// 单独抽出来是因为 `DispatchSemaphore.wait()` 在 async 上下文里是被禁的
    /// （Swift 6 直接报错）—— 把它放在普通函数里就没这个问题，也比 TaskGroup 更好
    /// 控制并发度：解析小文件时线程池开太满反而更慢。
    nonisolated static func scanSync(folder: URL?, picked: [URL], recursive: Bool,
                                     onlyMedia: Bool, opts: ReadOptions,
                                     bridge: ExifToolBridge, useET: Bool,
                                     onProgress: @escaping (Int, Int) -> Void) -> [MediaRow] {
        let urls = Scanner.collect(folder: folder, recursive: recursive,
                                   onlyMedia: onlyMedia, picked: picked)
        let sorted = urls.sorted { $0.path.lowercased() < $1.path.lowercased() }

        var exifMap: [String: [String: String]] = [:]
        if useET, !sorted.isEmpty {
            exifMap = bridge.batch(sorted.map { $0.path })
        }

        var collected: [MediaRow] = []
        collected.reserveCapacity(sorted.count)
        let lock = NSLock()
        let sem = DispatchSemaphore(value: 12)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "scan", attributes: .concurrent)

        for (i, url) in sorted.enumerated() {
            sem.wait()
            group.enter()
            queue.async {
                let key = URL(fileURLWithPath: url.path).standardizedFileURL.path
                let row = Scanner.makeRow(url, opts: opts, exifToolMD: exifMap[key])
                lock.lock()
                collected.append(row)
                let done = collected.count
                lock.unlock()
                sem.signal()
                group.leave()

                if i % 8 == 0 || done == sorted.count {
                    onProgress(done, sorted.count)
                }
            }
        }
        group.wait()

        collected.sort(by: { (a: MediaRow, b: MediaRow) -> Bool in
            let ka = a.sortKey, kb = b.sortKey
            if ka.0 != kb.0 { return ka.0 < kb.0 }
            if ka.1 != kb.1 { return ka.1 < kb.1 }
            if ka.2 != kb.2 { return ka.2 < kb.2 }
            return ka.3 < kb.3
        })
        return collected
    }

    // MARK: - 重算计划

    func rebuildPlan(immediate: Bool = false) {
        debounceTask?.cancel()
        let opts = renameOptions
        let rows = self.rows
        let apply: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            let next = Planner.build(rows: rows, options: opts)
            self.plan = next
            // 把已经不存在的路径从选择里剔掉
            let alive = Set(next.map { $0.path })
            self.selection = self.selection.intersection(alive)
        }
        if immediate {
            apply()
            return
        }
        debounceTask = Task { [apply] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { apply() }
        }
    }

    /// 选项改变时统一走这里（含防抖）
    func optionsChanged() { rebuildPlan() }

    // MARK: - 按位置增删

    func addEdit() {
        // 新规则默认插在中段，正好落在「前缀_日期」中间，一眼能看出效果
        var e = NameEdit()
        e.position = 4
        e.text = "-"
        edits.append(e)
        optionsChanged()
    }

    func removeEdit(_ id: UUID) {
        edits.removeAll { $0.id == id }
        optionsChanged()
    }

    /// 侧栏那行实时示例：拿当前规则打一遍样例名，让人不用真改名就能看出效果
    var editSample: String {
        guard !edits.isEmpty else { return "" }
        let stamp = PyFormat.strftime(renameOptions.format, PyFormat.now)
        let base = prefix + stamp + suffix
        let result = Planner.applyEdits(base, edits)
        return result.isEmpty ? base : result
    }

    // MARK: - 选择

    func selectAll() {
        selection = Set(visiblePlan.filter { $0.status == .ok }.map { $0.path })
    }

    func selectNone() { selection = [] }

    func invertSelection() {
        let visible = Set(visiblePlan.map { $0.path })
        let picked = selection.intersection(visible)
        selection = selection.subtracting(visible)
            .union(visible.subtracting(picked))
    }

    /// 表头三态
    var headerCheckState: CheckState {
        let renamable = Set(visiblePlan.filter { $0.status == .ok }.map { $0.path })
        guard !renamable.isEmpty else { return .off }
        let hit = renamable.filter { selection.contains($0) }.count
        if hit == 0 { return .off }
        return hit == renamable.count ? .on : .mixed
    }

    enum CheckState { case on, off, mixed }

    func toggleHeader() {
        headerCheckState == .on ? selectNone() : selectAll()
    }

    // MARK: - 改名

    func requestRename() {
        guard selectedRenamable > 0 else {
            alertText = "没有勾选任何待改名的文件。\n先在列表里选几行，或者点「全选」。"
            return
        }
        showConfirm = true
    }

    func performRename() {
        showConfirm = false
        let plan = self.plan
        let selected = selection
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = Renamer.perform(plan: plan, selected: selected)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if outcome.renamed == 0, outcome.errors == 0 {
                    self.alertText = outcome.messages.first ?? "没有需要改名的文件。"
                } else {
                    var msg = "改名完成：\(outcome.renamed) 个"
                    if outcome.skipped > 0 { msg += "，跳过 \(outcome.skipped) 个" }
                    if outcome.errors > 0 { msg += "，失败 \(outcome.errors) 个" }
                    self.showToast(msg)
                    self.startScan()
                }
            }
        }
    }

    // MARK: - 撤销 / 历史

    func loadHistory() {
        history = Renamer.history()
        showHistory = true
    }

    func undo(_ file: String?) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = Renamer.undo(file: file)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if outcome.undone == 0 {
                    self.alertText = outcome.messages.first ?? "没有可撤销的记录。"
                } else {
                    var msg = "已还原 \(outcome.undone) 个文件"
                    if outcome.failed > 0 { msg += "，\(outcome.failed) 个没还原" }
                    self.showToast(msg)
                    self.loadHistory()
                    if self.folder != nil || !self.pickedFiles.isEmpty { self.startScan() }
                }
            }
        }
    }

    // MARK: - 反推偏移

    func openCalibrate() {
        guard let path = selection.first,
              let item = plan.first(where: { $0.path == path }) else {
            alertText = "先在列表里选中一行，再来反推差多少。"
            return
        }
        _ = item
        showCalibrate = true
    }

    var calibrateItem: PlanItem? {
        for path in selection {
            if let hit = plan.first(where: { $0.path == path }) { return hit }
        }
        return nil
    }

    func applyCalibration(trueTime: WallTime) {
        guard let item = calibrateItem, let current = item.originalTime else { return }
        guard let a = current.date(in: TimeZone(secondsFromGMT: 0)!),
              let b = trueTime.date(in: TimeZone(secondsFromGMT: 0)!) else { return }
        let delta = Int(b.timeIntervalSince(a).rounded())
        let days = delta / 86_400
        let hours = (delta % 86_400) / 3600
        let minutes = (delta % 3600) / 60
        correctionOn = true
        corrDays = days
        corrHours = hours
        corrMinutes = minutes
        rebuildPlan(immediate: true)
        showCalibrate = false
        showToast("已算出偏移 \(offsetLabel)")
    }

    var offsetLabel: String {
        let total = offsetSeconds
        guard total != 0 else { return "不校正" }
        let sign = total > 0 ? "+" : "−"
        let v = abs(total)
        let d = v / 86_400, h = (v % 86_400) / 3600, m = (v % 3600) / 60
        var parts: [String] = []
        if d != 0 { parts.append("\(d) 天") }
        if h != 0 { parts.append("\(h) 小时") }
        if m != 0 { parts.append("\(m) 分钟") }
        if parts.isEmpty { parts.append("0") }
        return sign + parts.joined(separator: " ")
    }

    /// 表格里那个橙色小标签用的短形式：+8h / −30m / +1d
    var offsetShortLabel: String {
        let total = offsetSeconds
        guard total != 0 else { return "" }
        let sign = total > 0 ? "+" : "−"
        let v = abs(total)
        if v % 86_400 == 0 { return "\(sign)\(v / 86_400)d" }
        if v % 3600 == 0 { return "\(sign)\(v / 3600)h" }
        return "\(sign)\(v / 60)m"
    }

    // MARK: - 导出

    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue =
            "拍摄时间清单_\(PyFormat.strftime("%Y%m%d_%H%M%S", PyFormat.now)).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = Renamer.csv(for: plan)
        do {
            // 加 BOM，Excel 打开中文才不乱码
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(Data(text.utf8))
            try data.write(to: url)
            showToast("已导出 \((url as NSURL).lastPathComponent ?? "CSV")")
        } catch {
            alertText = "导出失败：\(error.localizedDescription)"
        }
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - 提示

    func showToast(_ text: String) {
        toastText = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.toastText = nil }
        }
    }
}
