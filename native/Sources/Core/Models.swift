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

enum NamePattern: String, CaseIterable, Identifiable, Codable {
    case dateOnly = "仅日期"
    case dateOriginal = "日期_原名"
    case originalDate = "原名_日期"
    case originalOnly = "仅原名"

    var id: String { rawValue }
}

/// 一条改名规则。按数组顺序作用在「拼好的名字主干」上，前一条的结果是后一条的输入。
///
/// 五种类型共用一个结构，字段按 `kind` 解释，没用到的不参与。
/// 为什么不用 enum + associated values：那样每个 case 都要单独一套 Binding 才能在
/// SwiftUI 里编辑，代码量翻倍还没换来任何好处。这里用「宽结构 + 按 kind 取字段」。
///
/// 刻意没做序号 / 正则 / 脚本那几样：
///  · 序号会破坏幂等 —— 只选部分文件时编号就漂了，而「重复扫描结果不变」是本工具的核心承诺
///  · 正则和脚本门槛太高，跟「傻瓜式」定位冲突
struct NameRule: Identifiable, Equatable, Codable {
    enum Kind: String, CaseIterable, Identifiable, Codable {
        case insert = "插入"
        case delete = "删除"
        case replace = "替换"
        case strip = "剥离字符"
        case cleanUp = "清理垃圾"
        case changeCase = "大小写"
        var id: String { rawValue }

        var hint: String {
            switch self {
            case .insert: return "在第 N 位或某段文字前后插一段"
            case .delete: return "从第 N 位删若干字符，或删到末尾"
            case .replace: return "查找替换；「换成」留空就是移除"
            case .strip: return "一次去掉所有某类字符"
            case .cleanUp: return "去掉 (1)、[副本]、多余空格这类垃圾"
            case .changeCase: return "统一大小写风格"
            }
        }
    }

    /// 插入位置怎么确定。按位置要数数，按文字不用数 —— 日期格式变了也不会错位
    enum Anchor: String, CaseIterable, Identifiable, Codable {
        case position = "按位置"
        case beforeText = "在某段文字前"
        case afterText = "在某段文字后"
        var id: String { rawValue }
    }

    enum Charset: String, CaseIterable, Identifiable, Codable {
        case space = "空格"
        case underscore = "下划线 _"
        case dash = "连字符 -"
        case brackets = "括号"
        case symbols = "所有符号"
        case digits = "数字"
        var id: String { rawValue }

        /// 命令行用的英文键 —— 终端里敲中文太费劲
        var key: String {
            switch self {
            case .space: return "space"
            case .underscore: return "underscore"
            case .dash: return "dash"
            case .brackets: return "brackets"
            case .symbols: return "symbols"
            case .digits: return "digits"
            }
        }

        static func fromKey(_ k: String) -> Charset? {
            allCases.first { $0.key == k }
        }

        var characters: Set<Character> {
            switch self {
            case .space:
                return [" ", "\t", "\u{3000}"]
            case .underscore:
                return ["_"]
            case .dash:
                return ["-", "－", "—", "–"]
            case .brackets:
                return ["(", ")", "（", "）", "[", "]", "【", "】", "{", "}", "「", "」"]
            case .symbols:
                return Set("~!@#$%^&*()_+-=[]{}|;:'\",.<>/?`\\".map { $0 })
            case .digits:
                return Set("0123456789".map { $0 })
            }
        }
    }

    enum CaseStyle: String, CaseIterable, Identifiable, Codable {
        case lower = "全小写"
        case upper = "全大写"
        case capitalize = "每词首字母大写"
        case sentence = "首字母大写"
        var id: String { rawValue }

        var key: String {
            switch self {
            case .lower: return "lower"
            case .upper: return "upper"
            case .capitalize: return "capitalize"
            case .sentence: return "sentence"
            }
        }

        static func fromKey(_ k: String) -> CaseStyle? {
            allCases.first { $0.key == k }
        }
    }

    var id = UUID()
    var enabled = true
    var kind: Kind = .insert

    // —— 位置类（insert 按位置时 / delete）
    /// 1 起算；负数从末尾数（-1 = 最后一个字符）
    var position = 1

    // —— 删除
    var count = 1
    /// 勾上就一路删到末尾，`count` 不参与
    var toEnd = false

    // —— 文字类（insert / replace）
    var text = ""
    var replacement = ""
    var caseSensitive = true

    // —— 插入的锚点
    var anchor: Anchor = .position
    var anchorText = ""

    // —— 剥离 / 大小写
    var charset: Charset = .space
    var caseStyle: CaseStyle = .lower

    // —— 清理垃圾
    /// 删掉括号连同里面的内容：`照片(1)` → `照片`
    var cleanBrackets = true
    /// 合并多余空格、去掉首尾空格（顺带把各种 Unicode 空白压成普通空格）
    var cleanSpaces = true
    /// 把 `_` `.` 换成空格：`20240506_153008` → `20240506 153008`
    var cleanSeparators = false
    /// 去掉 emoji
    var cleanEmoji = false

    /// 宽容解码：字段缺席就用默认值。
    ///
    /// 合成的 `init(from:)` 要求每个 key 都在，那样以后给规则加一个开关，
    /// 用户存在磁盘上的旧预设会**整份**解不出来、全部丢失。宁可少一个字段也不能这样。
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .insert
        position = (try? c.decode(Int.self, forKey: .position)) ?? 1
        count = (try? c.decode(Int.self, forKey: .count)) ?? 1
        toEnd = (try? c.decode(Bool.self, forKey: .toEnd)) ?? false
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        replacement = (try? c.decode(String.self, forKey: .replacement)) ?? ""
        caseSensitive = (try? c.decode(Bool.self, forKey: .caseSensitive)) ?? true
        anchor = (try? c.decode(Anchor.self, forKey: .anchor)) ?? .position
        anchorText = (try? c.decode(String.self, forKey: .anchorText)) ?? ""
        charset = (try? c.decode(Charset.self, forKey: .charset)) ?? .space
        caseStyle = (try? c.decode(CaseStyle.self, forKey: .caseStyle)) ?? .lower
        cleanBrackets = (try? c.decode(Bool.self, forKey: .cleanBrackets)) ?? true
        cleanSpaces = (try? c.decode(Bool.self, forKey: .cleanSpaces)) ?? true
        cleanSeparators = (try? c.decode(Bool.self, forKey: .cleanSeparators)) ?? false
        cleanEmoji = (try? c.decode(Bool.self, forKey: .cleanEmoji)) ?? false
    }

    /// 侧栏规则卡片标题用的一句话摘要
    var summary: String {        switch kind {
        case .insert:
            let where_ = anchor == .position ? "第 \(position) 位后" : "「\(anchorText)」\(anchor == .beforeText ? "前" : "后")"
            return "在\(where_)插入「\(text)」"
        case .delete:
            return toEnd ? "从第 \(position) 位删到末尾" : "从第 \(position) 位删 \(count) 个"
        case .replace:
            return replacement.isEmpty
                ? "移除「\(text)」"
                : "「\(text)」换成「\(replacement)」"
        case .strip:
            return "去掉所有\(charset.rawValue)"
        case .cleanUp:
            var parts: [String] = []
            if cleanBrackets { parts.append("括号内容") }
            if cleanSpaces { parts.append("多余空格") }
            if cleanSeparators { parts.append("下划线/点") }
            if cleanEmoji { parts.append("emoji") }
            return parts.isEmpty ? "没有勾选任何项" : "清掉" + parts.joined(separator: "、")
        case .changeCase:
            return caseStyle.rawValue
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
    /// 改名规则链，按顺序作用在拼好的主干上。空数组 = 不做任何编辑
    var rules: [NameRule] = []

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

// MARK: - 小工具

extension Character {
    /// 只认「默认就按 emoji 画出来」的字符（😀 ✅ 🎉 …）。
    ///
    /// 不用 `unicodeScalars.properties.isEmoji` —— 它对 `#`、`*`、`0`–`9` 也为真
    /// （keycap 表情的基础字符），会把文件名里的数字一起删掉。
    var isEmojiPresentation: Bool {
        unicodeScalars.contains { $0.properties.isEmojiPresentation }
    }
}
