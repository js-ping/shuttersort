import Foundation

/// 可选增强层：系统装了 exiftool 就用它批量提取，覆盖度比内置解析器高。
///
/// 两个必须记住的点：
///  1. `-api QuickTimeUTC=1` 不能省。QuickTime 的创建时间按 UTC 存，exiftool 默认
///     按本地时间解释，少了这个开关所有视频会整整早一个时区。
///  2. 但 `©day` / `Keys:CreationDate` 是**自由文本本地时间**，不能按 UTC 再平移一次，
///     所以只有 `quickTimeUTCTags` 里那几个标签才做 UTC 补算。
final class ExifToolBridge {

    let cmd: String?
    let version: String

    static let tags: [String] = [
        "EXIF:DateTimeOriginal", "EXIF:CreateDate", "EXIF:ModifyDate",
        "XMP:CreateDate", "XMP:DateCreated", "XMP:MetadataDate",
        "QuickTime:CreateDate", "QuickTime:MediaCreateDate",
        "QuickTime:TrackCreateDate", "QuickTime:ContentCreateDate",
        "QuickTime:CreationDate", "Keys:CreationDate",
        "Composite:SubSecDateTimeOriginal", "Composite:DateTimeCreated",
        "PNG:CreationTime", "RIFF:DateTimeOriginal",
        "DateTimeOriginal", "CreateDate", "MediaCreateDate", "CreationDate",
        // 亚秒：连拍（同一秒好几张）要按它排先后。本身不是日期，放在最后只做补充。
        "EXIF:SubSecTimeOriginal", "EXIF:SubSecTimeDigitized", "EXIF:SubSecTime",
    ]

    /// 这些标签在文件里是 1904 纪元的 UTC 秒数
    static let quickTimeUTCTags: Set<String> = [
        "QuickTime:CreateDate", "QuickTime:MediaCreateDate",
        "QuickTime:TrackCreateDate", "QuickTime:ContentCreateDate",
        "CreateDate", "MediaCreateDate",
    ]

    private static let subSecKeys = [
        "EXIF:SubSecTimeOriginal", "SubSecTimeOriginal", "EXIF:SubSecTimeDigitized",
    ]

    init() {
        var found: String?
        var ver = ""
        // .app 里的 PATH 很干净，Homebrew 目录要显式找
        for cand in ["exiftool", "/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"] {
            let path = cand.hasPrefix("/") ? cand
                : (ProcessInfo.processInfo.environment["PATH"] ?? "")
                    .split(separator: ":").map { "\($0)/exiftool" }
                    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? cand
            guard FileManager.default.isExecutableFile(atPath: path)
                    || cand == "exiftool" else { continue }
            if let out = Self.run([path, "-ver"], timeout: 10) {
                found = path
                ver = out.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        self.cmd = found
        self.version = ver
    }

    var available: Bool { cmd != nil }

    var infoText: String {
        available ? "exiftool v\(version)" : "未检测到（使用内置解析器）"
    }

    /// 批量取元数据。返回 [规范化路径: {标签: 值}]
    func batch(_ paths: [String]) -> [String: [String: String]] {
        guard let cmd, !paths.isEmpty else { return [:] }
        var out: [String: [String: String]] = [:]
        let chunkSize = 120
        var i = 0
        while i < paths.count {
            let part = Array(paths[i..<min(i + chunkSize, paths.count)])
            i += chunkSize

            var args = [cmd, "-j", "-G", "-s", "-charset", "utf8"]
            args += ["-api", "QuickTimeUTC=1"]
            args += Self.tags.map { "-" + $0 }
            args += part

            guard let raw = Self.runData(args, timeout: 180),
                  let arr = (try? JSONSerialization.jsonObject(with: raw)) as? [[String: Any]]
            else { continue }

            for dict in arr {
                guard let sf = dict["SourceFile"] as? String, !sf.isEmpty else { continue }
                var md: [String: String] = [:]
                for (k, v) in dict {
                    if k == "SourceFile" { continue }
                    md[k] = "\(v)"
                }
                out[URL(fileURLWithPath: sf).standardizedFileURL.path] = md
            }
        }
        return out
    }

    /// 从一批标签里挑出最早可用的时间，返回 (时间, 来源, 原始字符串)
    static func pickTime(_ md: [String: String]) -> (WallTime?, String, String) {
        for tag in tags {
            guard let raw = md[tag], !raw.isEmpty else { continue }
            guard var t = PyFormat.parseDatetimeAny(raw) else { continue }

            // QuickTime 的 CreateDate 系列是 UTC 存的。正常情况下字符串会带 +08:00
            // 偏移，上面已经转好了；万一只拿到裸时间，这里按 UTC 补一次换算。
            if quickTimeUTCTags.contains(tag), !hasTZMarker(raw),
               let abs = t.date(in: TimeZone(secondsFromGMT: 0)!),
               let local = WallTime(date: abs, timeZone: .current) {
                t = local
            }
            for sk in subSecKeys {
                if let v = md[sk], !v.isEmpty {
                    t = Subsecond.apply(t, v)
                    break
                }
            }
            return (t, "exiftool·\(tag)", raw)
        }
        return (nil, "", "")
    }

    /// 字符串里有没有显式时区（结尾的 Z，或 +08:00 / +0800）
    static func hasTZMarker(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("Z") { return true }
        return t.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
    }

    // MARK: - 进程调用

    private static func runData(_ args: [String], timeout: TimeInterval) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice

        do { try p.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        while p.isRunning, Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate() }
        return data.isEmpty ? nil : data
    }

    private static func run(_ args: [String], timeout: TimeInterval) -> String? {
        runData(args, timeout: timeout).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// 亚秒（SubSecTime*）的解析与应用
enum Subsecond {
    /// `"42"` 表示 0.42 秒 —— 右补零到 6 位再截取，与 Python 的
    /// `int((txt + "000000")[:6])` 完全一致
    static func apply(_ t: WallTime, _ raw: String?) -> WallTime {
        guard let raw else { return t }
        let txt = raw.trimmingCharacters(in: .whitespaces)
        guard !txt.isEmpty, txt.allSatisfy(\.isNumber) else { return t }
        let padded = String((txt + "000000").prefix(6))
        guard let micro = Int(padded) else { return t }
        var out = t
        out.micro = micro
        return out
    }
}
