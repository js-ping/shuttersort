import Foundation

/// 对单个文件求最佳拍摄时间 —— 八级优先级链。
///
/// 顺序是有讲究的，别随便调：exiftool 覆盖面最广放最前，然后是容器内嵌、
/// 旁车、文件名，最后才是文件系统时间（那已经不算"拍摄时间"了，只在用户
/// 主动开启兜底时才用）。
enum Prober {

    static func probe(url: URL, opts: ReadOptions,
                      exifToolMD: [String: String]? = nil) -> ProbeResult {
        var res = ProbeResult()
        let name = url.lastPathComponent

        do {
            let reader = try ByteReader(url: url)
            let kind = Formats.detectKind(reader)
            res.kind = kind

            // ---- 0) exiftool 优先 ----
            if opts.useExifTool, let md = exifToolMD {
                let (t, src, _) = ExifToolBridge.pickTime(md)
                if let t {
                    res.time = t
                    res.source = src
                    // 详情面板里去掉命名空间前缀，只留标签名
                    var exif: [String: String] = [:]
                    for (k, v) in md {
                        let short = k.split(separator: ":").last.map(String.init) ?? k
                        exif[short] = v
                    }
                    res.exif = exif
                    return res
                }
            }

            switch kind {
            case "isobmff", "heic", "avif":
                let iso = ISOBMFF.parse(reader, deepExif: opts.deepExif)
                res.durationSec = iso.durationSec

                // ilst 里的 creationdate / ©day 是自由文本本地时间，直接用
                for key in iso.ilst.keys.sorted() {
                    if key.lowercased().contains("creationdate")
                        || key == "\u{00A9}day" || key == "\u{00A9}DAY" {
                        if let t = PyFormat.parseDatetimeAny(iso.ilst[key]) {
                            res.time = t
                            res.source = "内嵌·\(key.trimmingCharacters(in: .whitespaces))"
                            res.exif.merge(iso.exif) { a, _ in a }
                            return res
                        }
                    }
                }
                if let t = iso.mvhd {
                    res.time = t
                    res.source = "内嵌·mvhd 创建时间"
                    res.exif.merge(iso.exif) { a, _ in a }
                    return res
                }
                if let t = iso.mdhd {
                    res.time = t
                    res.source = "内嵌·mdhd 媒体创建时间"
                    return res
                }
                if !iso.exif.isEmpty, let (t, note) = exifDictTime(iso.exif) {
                    res.time = t
                    res.source = "内嵌·HEIF Exif"
                    res.exif = iso.exif
                    res.note = note
                    return res
                }

            case "jpeg":
                let (exif, xmp) = Formats.readJPEG(reader)
                res.exif = exif
                if !xmp.isEmpty, let t = Formats.parseXMPForDate(xmp) {
                    res.time = t
                    res.source = "内嵌·XMP"
                    return res
                }
                if let (t, note) = exifDictTime(exif) {
                    res.time = t
                    res.source = "内嵌·EXIF"
                    res.note = note
                    return res
                }

            case "png":
                let (exif, xmp, ttime) = Formats.readPNG(reader)
                res.exif = exif
                if !xmp.isEmpty, let t = Formats.parseXMPForDate(xmp) {
                    res.time = t
                    res.source = "内嵌·XMP"
                    return res
                }
                if let (t, note) = exifDictTime(exif) {
                    res.time = t
                    res.source = "内嵌·eXIf"
                    res.note = note
                    return res
                }
                if let t = ttime {
                    res.time = t
                    res.source = "内嵌·PNG tIME"
                    return res
                }

            case "webp":
                let (exif, xmp) = Formats.readWebP(reader)
                res.exif = exif
                if !xmp.isEmpty, let t = Formats.parseXMPForDate(xmp) {
                    res.time = t
                    res.source = "内嵌·XMP"
                    return res
                }
                if let (t, note) = exifDictTime(exif) {
                    res.time = t
                    res.source = "内嵌·EXIF"
                    res.note = note
                    return res
                }

            case "tiff":
                let exif = (try? TIFF.parse(reader, tiffOffset: 0)) ?? [:]
                res.exif = exif
                if let (t, note) = exifDictTime(exif) {
                    res.time = t
                    res.source = "内嵌·EXIF"
                    res.note = note
                    return res
                }

            default:
                break
            }
        } catch {
            res.source = "缺失"
            res.note = "读取失败：\(type(of: error))"
            return res
        }

        // ---- 6) 旁车文件 ----
        let (xmpSide, jsonSide) = Formats.sidecarPaths(url)
        if opts.readTakeoutJSON, let jsonSide, let t = Formats.parseTakeoutJSON(jsonSide) {
            res.time = t
            res.source = "旁车·Google Takeout JSON"
            return res
        }
        if opts.readXmpSidecar, let xmpSide,
           let text = try? String(contentsOf: xmpSide, encoding: .utf8),
           let t = Formats.parseXMPForDate(text) {
            res.time = t
            res.source = "旁车·XMP"
            return res
        }

        // ---- 7) 文件名 ----
        if opts.parseFilename {
            let (t, src) = FilenameDates.parse(name)
            if let t {
                res.time = t
                res.source = src
                return res
            }
        }

        // ---- 8) 文件系统兜底 ----
        switch opts.fallback {
        case .created:
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let d = attrs[.creationDate] as? Date {
                res.time = WallTime(date: d, timeZone: .current)
                res.source = "文件系统·创建时间"
                return res
            }
        case .modified:
            let info = Scanner.statInfo(url)
            res.time = WallTime(unix: info.sec, micro: info.micro, timeZone: .current)
            res.source = "文件系统·修改时间"
            return res
        case .skip:
            break
        }

        res.source = "缺失"
        res.note = FilenameDates.missingHint(name)
        return res
    }

    /// 按 DateTimeOriginal → DateTimeDigitized → DateTime 的优先级从 EXIF 字典取时间，
    /// 顺带处理 OffsetTime 偏移与 SubSecTime 亚秒。
    static func exifDictTime(_ exif: [String: String]) -> (WallTime, String)? {
        guard !exif.isEmpty else { return nil }
        let order = ["DateTimeOriginal", "DateTimeDigitized", "DateTime"]
        let offKeys = ["DateTimeOriginal": "OffsetTimeOriginal",
                       "DateTimeDigitized": "OffsetTimeDigitized",
                       "DateTime": "OffsetTime"]
        let subKeys = ["DateTimeOriginal": "SubSecTimeOriginal",
                       "DateTimeDigitized": "SubSecTimeDigitized",
                       "DateTime": "SubSecTime"]

        for key in order {
            guard let raw = exif[key], !raw.isEmpty,
                  var t = PyFormat.parseDatetimeAny(raw) else { continue }

            let off = exif[offKeys[key] ?? ""]
            if let off, !off.isEmpty,
               let rx = try? NSRegularExpression(pattern: #"([+-])(\d{2}):?(\d{2})$"#),
               let m = rx.firstMatch(in: off.trimmingCharacters(in: .whitespaces),
                                     range: NSRange(location: 0,
                                                    length: (off as NSString).length)) {
                let ns = off.trimmingCharacters(in: .whitespaces) as NSString
                let sign = ns.substring(with: m.range(at: 1)) == "+" ? 1 : -1
                let hh = Int(ns.substring(with: m.range(at: 2))) ?? 0
                let mm = Int(ns.substring(with: m.range(at: 3))) ?? 0
                let seconds = sign * (hh * 3600 + mm * 60)
                if let tz = TimeZone(secondsFromGMT: seconds),
                   let abs = t.date(in: tz),
                   let local = WallTime(date: abs, timeZone: .current) {
                    t = local
                }
            }

            t = Subsecond.apply(t, exif[subKeys[key] ?? ""])

            var note = "\(key)=\(raw)"
            if let off, !off.isEmpty { note += " 时区=\(off)" }
            return (t, note)
        }
        return nil
    }
}
