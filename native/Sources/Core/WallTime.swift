import Foundation

/// 本地墙钟时间（不含时区信息），带亚秒微秒。
///
/// 为什么不用 `Date`：`Date` 内部是从 2001 年起的 Double 秒数，2024 年这个量级上
/// 分辨率已经接近 100 纳秒，加减运算会丢微秒 —— 而连拍排序恰恰依赖微秒。
/// 所以这里直接用年月日时分秒 + 微秒七个整数，比较和排序都是精确的。
struct WallTime: Comparable, Hashable, Codable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var second: Int
    var micro: Int

    init(year: Int, month: Int, day: Int,
         hour: Int = 0, minute: Int = 0, second: Int = 0, micro: Int = 0) {
        self.year = year; self.month = month; self.day = day
        self.hour = hour; self.minute = minute; self.second = second
        self.micro = micro
    }

    /// 从一个绝对时间点，按指定时区取出墙钟表示。
    init?(date: Date, timeZone: TimeZone = .current) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond],
                                   from: date)
        guard let y = c.year, let mo = c.month, let d = c.day,
              let h = c.hour, let mi = c.minute, let s = c.second else { return nil }
        self.init(year: y, month: mo, day: d, hour: h, minute: mi, second: s,
                  micro: min(999_999, (c.nanosecond ?? 0) / 1000))
    }

    /// 在指定时区下转成绝对时间点。
    func date(in timeZone: TimeZone = .current) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        c.nanosecond = micro * 1000
        return cal.date(from: c)
    }

    /// 用户看的时间戳格式：`2026-05-06 15:30:08`
    var stamp: String {
        String(format: "%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
    }

    /// 带亚秒的时间戳，`2026-05-06 15:30:08.420000` —— 与 Python 版 `tsIso` 对齐
    var stampWithMicro: String {
        String(format: "%04d-%02d-%02d %02d:%02d:%02d.%06d",
               year, month, day, hour, minute, second, micro)
    }

    /// 只在这一秒内有亚秒时才带出来，否则退回 `stamp`（界面用）
    var stampWithMicroIfAny: String {
        micro == 0 ? stamp : stampWithMicro
    }

    /// 整体加减秒数。跨月、跨闰年交给 Calendar。
    ///
    /// 刻意不写成 `date.addingTimeInterval(...)` 再取回：`Date` 是 Double 秒，
    /// 2023 年这个量级的浮点分辨率约 0.4 微秒，来回一趟微秒就会被磨掉 1μs ——
    /// 连拍排序靠的正是微秒。这里秒和微秒分开走，全程整数。
    func adding(seconds: Int) -> WallTime {
        guard seconds != 0 else { return self }
        let utc = TimeZone(secondsFromGMT: 0)!
        guard let base = date(in: utc) else { return self }
        let whole = Int(base.timeIntervalSince1970.rounded())
        guard let moved = WallTime(unix: whole + seconds, micro: micro, timeZone: utc) else {
            return self
        }
        return moved
    }

    /// 从整数 Unix 秒 + 独立微秒构造，秒和小数分开，避免浮点误差
    init?(unix: Int, micro: Int = 0, timeZone: TimeZone = .current) {
        let d = Date(timeIntervalSince1970: TimeInterval(unix))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        guard let y = c.year, let mo = c.month, let dd = c.day,
              let h = c.hour, let mi = c.minute, let sec = c.second else { return nil }
        let probe = WallTime(year: y, month: mo, day: dd, hour: h, minute: mi,
                             second: sec, micro: micro)
        guard probe.isPlausible else { return nil }
        self = probe
    }

    static func < (a: WallTime, b: WallTime) -> Bool {
        if a.year != b.year { return a.year < b.year }
        if a.month != b.month { return a.month < b.month }
        if a.day != b.day { return a.day < b.day }
        if a.hour != b.hour { return a.hour < b.hour }
        if a.minute != b.minute { return a.minute < b.minute }
        if a.second != b.second { return a.second < b.second }
        return a.micro < b.micro
    }

    static func == (a: WallTime, b: WallTime) -> Bool {
        a.year == b.year && a.month == b.month && a.day == b.day
            && a.hour == b.hour && a.minute == b.minute
            && a.second == b.second && a.micro == b.micro
    }

    /// 各字段是否落在合法范围内。Python 的 strptime 会拒绝 2024-02-30，
    /// 这里同样要拒绝 —— 靠 Calendar 自动滚动会把 2 月 30 日变成 3 月 1 日，那就错了。
    var isPlausible: Bool {
        guard (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute),
              (0...60).contains(second), (0...999_999).contains(micro) else { return false }
        return day <= WallTime.daysInMonth(year: year, month: month)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        default: return 0
        }
    }

    /// 从 `DateComponents` 组装，顺手做合法性校验
    init?(components c: DateComponents) {
        guard let y = c.year, let mo = c.month, let d = c.day else { return nil }
        let probe = WallTime(year: y, month: mo, day: d,
                             hour: c.hour ?? 0, minute: c.minute ?? 0,
                             second: c.second ?? 0,
                             micro: c.nanosecond.map { min(999_999, $0 / 1000) } ?? 0)
        guard probe.isPlausible else { return nil }
        self = probe
    }
}
