import Foundation

/// Python `strptime` / `strftime` 的最小兼容实现。
///
/// 为什么要自己写：`DateFormatter` 依赖 locale 和日历设置，同一串在不同系统语言下
/// 结果可能不同；而本项目要跟 Python 版逐字节对齐。这里把 Python 格式串编成正则，
/// 匹配语义（几位数字、哪些非法值要拒）全部显式写死。
enum PyFormat {

    /// 与 `media_time.DATE_FORMATS` 完全一致，顺序也保持一致
    static let dateFormats: [String] = [
        "%Y:%m:%d %H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
        "%Y/%m/%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y:%m:%d %H:%M:%S.%f",
        "%Y-%m-%d %H:%M:%S.%f",
        "%Y-%m-%dT%H:%M:%S.%f",
        "%Y:%m:%d %H:%M",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d",
        "%Y:%m:%d",
    ]

    /// `([+-])(\d{2}):?(\d{2})$` —— 结尾的时区偏移
    private static let tzRx = try! NSRegularExpression(pattern: "([+-])([0-9]{2}):?([0-9]{2})$")

    // MARK: - strptime

    /// 把 Python 格式串编译成正则 + 指令顺序。不支持的指令返回 nil（整条格式放弃）。
    private static func compile(_ fmt: String) -> (NSRegularExpression, [Character])? {
        var pattern = "^"
        var order: [Character] = []
        var it = fmt.makeIterator()
        while let ch = it.next() {
            if ch == "%" {
                guard let spec = it.next() else { return nil }
                switch spec {
                case "Y": pattern += "([0-9]{4})"; order.append("Y")
                case "y": pattern += "([0-9]{2})"; order.append("y")
                case "m": pattern += "([0-9]{1,2})"; order.append("m")
                case "d": pattern += "([0-9]{1,2})"; order.append("d")
                case "e": pattern += "([0-9 ]{1,2})"; order.append("e")
                case "H": pattern += "([0-9]{1,2})"; order.append("H")
                case "M": pattern += "([0-9]{1,2})"; order.append("M")
                case "S": pattern += "([0-9]{1,2})"; order.append("S")
                case "f": pattern += "([0-9]{1,6})"; order.append("f")
                case "%": pattern += "%"
                default: return nil
                }
            } else {
                pattern += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        pattern += "$"
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return nil }
        return (rx, order)
    }

    /// 按给定 Python 格式解析。日期非法（2 月 30 日、13 月）一律拒绝 ——
    /// 与 CPython `strptime` 抛 ValueError 的行为一致。
    static func strptime(_ s: String, _ fmt: String) -> WallTime? {
        guard let (rx, order) = compile(fmt) else { return nil }
        let ns = s as NSString
        guard let m = rx.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.range.location != NSNotFound else { return nil }

        var parts: [Character: Int] = [:]
        for (i, spec) in order.enumerated() {
            let r = m.range(at: i + 1)
            guard r.location != NSNotFound else { return nil }
            var text = ns.substring(with: r)
            if spec == "e" { text = text.replacingOccurrences(of: " ", with: "0") }
            guard let v = Int(text) else { return nil }
            parts[spec] = v
        }

        guard var year = parts["Y"] else { return nil }
        if let yy = parts["y"] {
            // Python 的 %y：69-99 → 1900+, 00-68 → 2000+
            year = yy >= 69 ? 1900 + yy : 2000 + yy
        }
        guard let month = parts["m"], let day = parts["d"] else { return nil }
        let hour = parts["H"] ?? 0, minute = parts["M"] ?? 0, second = parts["S"] ?? 0
        var micro = 0
        if let f = parts["f"] {
            // %f 右补零到 6 位：「42」是 0.42 秒 = 420000 微秒
            let text = String(format: "%06d", f)
            micro = Int(text.prefix(6)) ?? 0
        }
        let t = WallTime(year: year, month: month, day: day,
                         hour: hour, minute: minute, second: second, micro: micro)
        return t.isPlausible ? t : nil
    }

    /// 尝试所有内置格式
    static func strptimeAny(_ s: String) -> WallTime? {
        for fmt in dateFormats {
            if let t = strptime(s, fmt) { return t }
        }
        return nil
    }

    // MARK: - parse_datetime_any

    /// 对应 `media_time.parse_datetime_any`：
    /// 处理 `Z` 结尾（UTC）、结尾时区偏移、以及各种朴素格式，最终统一成**本地墙钟时间**。
    static func parseDatetimeAny(_ raw: String?) -> WallTime? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        // 连续空白压成一个空格，和 Python 的 re.sub(r"\s+", " ", s) 对齐
        s = s.replacingOccurrences(of: "[ \\t\\n\\r]+", with: " ", options: .regularExpression)

        // 结尾的 Z 表示 UTC。不能简单去掉当本地时间用，那样会整整早一个时区偏移。
        if s.hasSuffix("Z") {
            let base = String(s.dropLast()).trimmingCharacters(in: .whitespaces)
            if let wall = strptimeAny(base),
               let abs = wall.date(in: TimeZone(secondsFromGMT: 0)!),
               let local = WallTime(date: abs, timeZone: .current) {
                return local
            }
            s = base
        }

        // 朴素时间：本来就是本地时间，原样返回
        if let t = strptimeAny(s) { return t }

        // 结尾带时区偏移 +08:00 / +0800
        let ns = s as NSString
        if let m = tzRx.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            let base = ns.substring(to: m.range.location)
                .trimmingCharacters(in: .whitespaces)
            let sign = ns.substring(with: m.range(at: 1)) == "+" ? 1 : -1
            let hh = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let mm = Int(ns.substring(with: m.range(at: 3))) ?? 0
            let offset = sign * (hh * 3600 + mm * 60)
            if let wall = strptimeAny(base),
               let tz = TimeZone(secondsFromGMT: offset),
               let abs = wall.date(in: tz),
               let local = WallTime(date: abs, timeZone: .current) {
                return local
            }
        }
        return nil
    }

    // MARK: - strftime

    /// Python 风格格式化。只实现本项目可能用到的指令，缺的直接原样输出。
    static func strftime(_ fmt: String, _ t: WallTime) -> String {
        var out = ""
        var it = fmt.makeIterator()
        while let ch = it.next() {
            guard ch == "%" else { out.append(ch); continue }
            guard let spec = it.next() else { out.append("%"); break }
            switch spec {
            case "Y": out += String(format: "%04d", t.year)
            case "y": out += String(format: "%02d", t.year % 100)
            case "m": out += String(format: "%02d", t.month)
            case "d": out += String(format: "%02d", t.day)
            case "e": out += String(format: "%2d", t.day)
            case "H": out += String(format: "%02d", t.hour)
            case "M": out += String(format: "%02d", t.minute)
            case "S": out += String(format: "%02d", t.second)
            case "f": out += String(format: "%06d", t.micro)
            case "j": out += String(format: "%03d", dayOfYear(t))
            case "I":
                let h12 = t.hour % 12 == 0 ? 12 : t.hour % 12
                out += String(format: "%02d", h12)
            case "p": out += t.hour < 12 ? "AM" : "PM"
            case "%": out += "%"
            default: out += "%\(spec)"
            }
        }
        return out
    }

    /// 年内第几天（001–366）
    static func dayOfYear(_ t: WallTime) -> Int {
        var n = t.day
        for m in 1..<t.month { n += WallTime.daysInMonth(year: t.year, month: m) }
        return n
    }

    /// 现在，本地墙钟
    static var now: WallTime {
        WallTime(date: Date(), timeZone: .current)
            ?? WallTime(year: 1970, month: 1, day: 1)
    }
}
