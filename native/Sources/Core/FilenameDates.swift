import Foundation

/// 从文件名里还原拍摄时间。
///
/// 聊天软件、无人机、截图工具导出的文件，名字里常常带着完整时间，
/// 而元数据反倒被剥掉了 —— 这时名字就是最可靠的来源。
enum FilenameDates {

    /// 时间戳后面必须是分隔符或结尾，避免把 `IMG_202405061` 这种截断数字认成日期
    private static let tsEnd = #"(?=$|[_\-. \)\[（(])"#

    struct Rule {
        let label: String
        let pattern: String
        let ignoreCase: Bool
    }

    /// 顺序即优先级，与 `media_time.FILENAME_PATTERNS` 一致
    static let rules: [Rule] = [
        Rule(label: "DJI Fly", pattern: #"DJI[_-]?FLY[_-]((?:19|20)\d{6})[_-](\d{6})"# + tsEnd, ignoreCase: true),
        Rule(label: "DJI", pattern: #"DJI[_-]((?:19|20)\d{6})[_-](\d{6})"# + tsEnd, ignoreCase: true),
        Rule(label: "IMG_/VID_", pattern: #"(?:IMG|VID)[-_]?((?:19|20)\d{6})[_-](\d{6})"# + tsEnd, ignoreCase: true),
        Rule(label: "PXL/微信/相机", pattern: #"(?:PXL|MVIMG|mmexport|wx_camera)[_-]?((?:19|20)\d{6})[_-]?(\d{6})?"# + tsEnd, ignoreCase: true),
        Rule(label: "通用 YYYYMMDD_HHMMSS", pattern: #"((?:19|20)\d{6})[_-](\d{6})"# + tsEnd, ignoreCase: false),
        // 连续 14 位：IMG_20200101000000 / 微信、QQ 导出常见
        Rule(label: "连续 YYYYMMDDHHMMSS", pattern: #"((?:19|20)\d{12})"# + tsEnd, ignoreCase: false),
        Rule(label: "通用 YYYY-MM-DD_HH-MM-SS",
             pattern: #"((?:19|20)\d{2})[-_.](\d{2})[-_.](\d{2})[ _T-](\d{2})[-_.:](\d{2})[-_.:](\d{2})"# + tsEnd,
             ignoreCase: false),
        Rule(label: "WhatsApp IMG", pattern: #"IMG-((?:19|20)\d{6})-WA\d+"# + tsEnd, ignoreCase: true),
        Rule(label: "WhatsApp VID", pattern: #"VID-((?:19|20)\d{6})-WA\d+"# + tsEnd, ignoreCase: true),
        Rule(label: "中文日期", pattern: #"((?:19|20)\d{2})年(\d{1,2})月(\d{1,2})日"#, ignoreCase: false),
        Rule(label: "截图",
             pattern: #"(?:Screenshot|屏幕快照|截屏)[ _-]*((?:19|20)\d{2})[-_.]?(\d{2})[-_.]?(\d{2})[ _-]*(\d{2})?[-_.:]?(\d{2})?[-_.:]?(\d{2})?"#,
             ignoreCase: true),
    ]

    private static let uuidRx = try! NSRegularExpression(
        pattern: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
        options: .caseInsensitive)
    private static let hashRx = try! NSRegularExpression(
        pattern: #"^[0-9a-f]{16,}$"#, options: .caseInsensitive)

    /// UUID / 长哈希文件名通常意味着元数据已被剥离，不做任何猜测
    static func looksOpaque(stem: String) -> Bool {
        let ns = stem as NSString
        let range = NSRange(location: 0, length: ns.length)
        return uuidRx.firstMatch(in: stem, range: range) != nil
            || hashRx.firstMatch(in: stem, range: range) != nil
    }

    /// 返回 (时间, 来源标签)
    static func parse(_ filename: String) -> (WallTime?, String) {
        let stem = (filename as NSString).deletingPathExtension
        if looksOpaque(stem: stem) { return (nil, "missing") }

        for rule in rules {
            let opts: NSRegularExpression.Options = rule.ignoreCase ? .caseInsensitive : []
            guard let rx = try? NSRegularExpression(pattern: rule.pattern, options: opts) else { continue }
            let ns = stem as NSString
            guard let m = rx.firstMatch(in: stem, range: NSRange(location: 0, length: ns.length)) else {
                continue
            }
            // 未参与匹配的组是 NSNotFound
            var g: [String?] = []
            for i in 1..<m.numberOfRanges {
                let r = m.range(at: i)
                g.append(r.location == NSNotFound ? nil : ns.substring(with: r))
            }
            if let t = build(rule: rule.label, groups: g) { return (t, "文件名·\(rule.label)") }
        }
        return (nil, "missing")
    }

    private static func build(rule: String, groups g: [String?]) -> WallTime? {
        func at(_ i: Int) -> String? { i < g.count ? g[i] : nil }
        func num(_ i: Int) -> Int? { at(i).flatMap { Int($0) } }

        switch rule {
        case "DJI Fly", "DJI", "IMG_/VID_", "通用 YYYYMMDD_HHMMSS":
            guard let ymd = at(0) else { return nil }
            let hms = at(1) ?? "000000"
            return PyFormat.strptime(ymd + hms, "%Y%m%d%H%M%S")

        case "连续 YYYYMMDDHHMMSS":
            guard let all = at(0), let t = PyFormat.strptime(all, "%Y%m%d%H%M%S") else { return nil }
            // 14 位连续数字太容易误判，加一道年份合理性校验
            return (1990...2100).contains(t.year) ? t : nil

        case "PXL/微信/相机":
            guard let ymd = at(0) else { return nil }
            let hms = at(1) ?? "000000"
            return PyFormat.strptime(ymd + hms, "%Y%m%d%H%M%S")

        case "通用 YYYY-MM-DD_HH-MM-SS":
            guard let y = num(0), let mo = num(1), let d = num(2),
                  let h = num(3), let mi = num(4), let s = num(5) else { return nil }
            let t = WallTime(year: y, month: mo, day: d, hour: h, minute: mi, second: s)
            return t.isPlausible ? t : nil

        case "WhatsApp IMG", "WhatsApp VID":
            guard let ymd = at(0) else { return nil }
            return PyFormat.strptime(ymd, "%Y%m%d")

        case "中文日期":
            guard let y = num(0), let mo = num(1), let d = num(2) else { return nil }
            let t = WallTime(year: y, month: mo, day: d)
            return t.isPlausible ? t : nil

        case "截图":
            guard let y = num(0), let mo = num(1), let d = num(2) else { return nil }
            let t = WallTime(year: y, month: mo, day: d,
                             hour: num(3) ?? 0, minute: num(4) ?? 0, second: num(5) ?? 0)
            return t.isPlausible ? t : nil

        default:
            return nil
        }
    }

    /// 缺失时间戳时给用户的解释（对应 `_missing_hint`）
    static func missingHint(_ filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        let ns = stem as NSString
        let range = NSRange(location: 0, length: ns.length)
        if uuidRx.firstMatch(in: stem, range: range) != nil {
            return "文件名是 UUID 格式，通常表示已被导出/处理过，元数据可能被剥离；可开启「文件时间兜底」"
        }
        if hashRx.firstMatch(in: stem, range: range) != nil {
            return "文件名是哈希串，常见于聊天软件导出，元数据多已剥离"
        }
        if stem.allSatisfy(\.isNumber), stem.count >= 8 {
            return "文件名是纯数字编号，不含日期信息，且文件内没有可用元数据；可开启「文件时间兜底」或跳过"
        }
        return ""
    }
}
