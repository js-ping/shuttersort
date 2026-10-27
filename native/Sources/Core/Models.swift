import Foundation

// MARK: - 读取选项

enum FallbackMode: String, CaseIterable {
    case skip, created, modified

    var label: String {
        switch self {
        case .skip: return "跳过该文件（推荐，最安全）"
        case .created: return "用文件创建时间"
        case .modified: return "用文件修改时间"
        }
    }
}

struct ReadOptions {
    var useExifTool = true
    var parseFilename = true
    var readXMPGlobal = true
    var readXmpSidecar = true
    var readTakeoutJSON = true
    var fallback: FallbackMode = .skip
    var deepExif = true
}

// MARK: - 探测结果

struct ProbeResult {
    var time: WallTime?
    var source: String = "缺失"
    var exif: [String: String] = [:]
    var kind: String = ""
    var note: String = ""
    var durationSec: Double?
}

// MARK: - 扫描出来的一行

struct MediaRow: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var dir: String
    var name: String
    var ext: String
    var size: Int64
    var sizeText: String
    var mtime: Date
    /// `stat(2)` 的原始秒 + 微秒。`Date` 是 Double，取微秒会有浮点误差，
    /// 排序只认这一对整数。
    var mtimeSec: Int = 0
    var mtimeMicro: Int = 0
    var time: WallTime?
    var source: String
    var kind: String
    var note: String
    var duration: Double?
    var exif: [String: String]

    /// 排序键：时间在前，没有时间的沉底；同秒再靠 mtime 和文件名兜底。
    /// 连拍的先后顺序就靠这个稳住，换机器重扫也不会漂移。
    /// 时间用 `stampWithMicroIfAny`（无亚秒时不带小数），与 Python 的 `isoformat` 一致。
    var sortKey: (String, Int, Int, String) {
        (time?.stampWithMicroIfAny ?? "9999", mtimeSec, mtimeMicro, name.lowercased())
    }

    static func == (a: MediaRow, b: MediaRow) -> Bool { a.path == b.path && a.time == b.time }
    func hash(into h: inout Hasher) { h.combine(path) }
}

// MARK: - 命名选项

enum NamePattern: String, CaseIterable, Identifiable {
    case dateOnly = "仅日期"
    case dateOriginal = "日期_原名"
    case originalDate = "原名_日期"
    case originalOnly = "仅原名"

    var id: String { rawValue }
}

/// 对新文件名按「字符序号」做插入 / 删除。
///
/// 位置 1 起算，负数从末尾数：
///  · 插入：在第 N 个字符**之后**；`0` = 最前面；`-1` = 末尾
///  · 删除：从第 N 个字符**开始**删 N 个；`-1` = 最后一个字符
///
/// 只作用于扩展名之前的主干 —— 位置算错了也不会把 `.jpg` 撕掉。
struct NameEdit: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case insert = "插入"
        case delete = "删除"
        var id: String { rawValue }
    }

    var id = UUID()
    var enabled = true
    var kind: Kind = .insert
    var position: Int = 1
    /// 插入的内容（`kind == .delete` 时忽略）
    var text = ""
    /// 删除几个字符（`kind == .insert` 时忽略）
    var count: Int = 1

    /// 给 tooltip / 摘要用的一句话
    var summary: String {
        switch kind {
        case .insert:
            return "第 \(position) 位后插入「\(text)」"
        case .delete:
            return "从第 \(position) 位删 \(count) 个字符"
        }
    }
}

struct RenameOptions {
    var format = "%Y%m%d_%H%M%S"
    var prefix = "IMG_"
    var suffix = ""
    var pattern: NamePattern = .dateOnly
    var archive = false
    var archiveFormat = "%Y/%Y-%m"
    var onlyRenamable = false
    /// 时间校正：只作用于生成文件名，绝不回写元数据
    var offsetSeconds = 0
    /// 按位置增删字符，按顺序作用在拼好的主干上。空数组 = 不做任何编辑
    var edits: [NameEdit] = []

    static let formatPresets: [String] = [
        "%Y%m%d_%H%M%S", "%Y-%m-%d_%H-%M-%S", "%Y%m%d", "%Y年%m月%d日", "%Y%m%d_%H%M%S_%j",
    ]

    /// 「缺省」= 恢复默认
    static let `default` = RenameOptions()
}

// MARK: - 计划条目

enum PlanStatus: String {
    case ok, same, skip

    var text: String {
        switch self {
        case .ok: return "待改名"
        case .same: return "无需改动"
        case .skip: return "跳过（无时间戳）"
        }
    }
}

struct PlanItem: Identifiable {
    var id: String { path }
    var path: String
    var name: String
    var dir: String
    var size: Int64
    var sizeText: String
    var ext: String
    var source: String
    var kind: String
    var note: String
    var duration: Double?
    var exif: [String: String]
    var originalTime: WallTime?
    var shiftedTime: WallTime?
    var newName: String
    var targetDir: String
    var status: PlanStatus
    var conflict: String
    /// 原始顺序。Swift 的 sort 不保证稳定，靠它兜住「键完全相同时的相对次序」，
    /// 才能和 Python 那边 Timsort 的结果一致。
    var order: Int = 0

    /// 界面显示 / 排序都用校正后的时间
    var displayTime: WallTime? { shiftedTime ?? originalTime }

    /// 排序用的时间字符串：没有时间的用空串，和 Python 的 `tsShifted or ""` 对齐
    var sortStamp: String { displayTime?.stampWithMicroIfAny ?? "" }

    var archiveSubdir: String? {
        guard targetDir != dir else { return nil }
        return (targetDir as NSString).lastPathComponent
    }
}

struct PlanStats {
    var total = 0
    var rename = 0
    var same = 0
    var skip = 0
}
