import Foundation

/// JPEG / PNG / WebP 的容器遍历，以及格式识别、XMP 提取、旁车文件。
enum Formats {

    // MARK: - 格式识别

    /// 按魔数判断真实格式（比扩展名可靠）
    static func detectKind(_ r: ByteReader) -> String {
        let h = r.read(at: 0, count: min(32, r.size))
        guard h.count >= 4 else { return "unknown" }
        let b = { (i: Int) -> UInt8 in h[h.startIndex + i] }

        if h.count >= 2, b(0) == 0xFF, b(1) == 0xD8 { return "jpeg" }
        if h.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        if h.count >= 12, b(0) == 0x52, b(1) == 0x49, b(2) == 0x46, b(3) == 0x46,
           b(8) == 0x57, b(9) == 0x45, b(10) == 0x42, b(11) == 0x50 { return "webp" }
        if h.count >= 6, h.starts(with: Array("GIF87a".utf8)) || h.starts(with: Array("GIF89a".utf8)) {
            return "gif"
        }
        // TIFF：II*\0 或 MM\0*
        if h.count >= 4,
           ((b(0) == 0x49 && b(1) == 0x49 && b(2) == 0x2A && b(3) == 0x00)
            || (b(0) == 0x4D && b(1) == 0x4D && b(2) == 0x00 && b(3) == 0x2A)) {
            return "tiff"
        }
        // ISOBMFF：先看 size 是否常见，再看第 4 字节起的 box 类型
        let boxTypes: [String] = ["ftyp", "moov", "mdat", "free", "wide", "skip", "styp"]
        var isIso = false
        if h.count >= 4 {
            let size = h.be32(0)
            if size == 0x18 || size == 0x1C || size == 0x20 { isIso = true }
        }
        if !isIso, h.count >= 8 {
            let t = String(bytes: h.subdata(in: (h.startIndex + 4)..<(h.startIndex + 8)),
                           encoding: .isoLatin1) ?? ""
            if boxTypes.contains(t) { isIso = true }
        }
        if isIso {
            let brand = h.count >= 12
                ? (String(bytes: h.subdata(in: (h.startIndex + 8)..<(h.startIndex + 12)),
                          encoding: .isoLatin1) ?? "")
                : ""
            let heicBrands = ["heic", "heix", "hevc", "hevx", "mif1", "msf1", "heim", "heis"]
            if heicBrands.contains(brand) { return "heic" }
            if brand == "avif" || brand == "avis" { return "avif" }
            return "isobmff"
        }
        if h.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) { return "matroska" }
        if h.count >= 12, h.starts(with: Array("RIFF".utf8)),
           String(bytes: h.subdata(in: (h.startIndex + 8)..<(h.startIndex + 12)),
                  encoding: .isoLatin1) == "AVI " { return "avi" }
        return "unknown"
    }

    // MARK: - JPEG

    /// 返回 (EXIF 标签, XMP 文本)
    static func readJPEG(_ r: ByteReader) -> ([String: String], String) {
        var exif: [String: String] = [:]
        var xmp = ""
        var off = 2
        var guardCount = 0
        while off + 4 <= r.size && guardCount < 512 {
            guardCount += 1
            let b = r.read(at: off, count: 4)
            guard b.count >= 4 else { break }
            let marker = b[b.startIndex + 1]
            if b[b.startIndex] != 0xFF { off += 1; continue }
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) {
                off += 2; continue
            }
            if marker == 0xDA { break }                  // SOS 之后是压缩数据
            let segLen = b.be16(2)
            guard segLen >= 2 else { break }
            let bodyOff = off + 4
            let bodyLen = segLen - 2

            if marker == 0xE1 {
                let head = r.read(at: bodyOff, count: 32)
                if head.starts(with: Array("Exif".utf8) + [0, 0]) {
                    if let got = try? TIFF.parse(r, tiffOffset: bodyOff + 6) { exif = got }
                } else if head.count >= 28 {
                    let sig = String(bytes: head.subdata(in: (head.startIndex)..<(head.startIndex + 28)),
                                     encoding: .isoLatin1)?.lowercased() ?? ""
                    if sig.hasPrefix("http://ns.adobe.com/xap/1.0/") {
                        let n = min(bodyLen - 29, 1 << 20)
                        let raw = r.read(at: bodyOff + 29, count: n)
                        xmp = String(data: raw, encoding: .utf8) ?? ""
                    }
                }
            }
            off += 2 + segLen
        }
        return (exif, xmp)
    }

    // MARK: - PNG

    static func readPNG(_ r: ByteReader) -> ([String: String], String, WallTime?) {
        var exif: [String: String] = [:]
        var xmp = ""
        var ttime: WallTime?
        var off = 8
        var guardCount = 0
        while off + 8 <= r.size && guardCount < 2048 {
            guardCount += 1
            let hdr = r.read(at: off, count: 8)
            guard hdr.count >= 8 else { break }
            let length = hdr.be32(0)
            let ctype = String(bytes: hdr.subdata(in: (hdr.startIndex + 4)..<(hdr.startIndex + 8)),
                               encoding: .isoLatin1) ?? ""
            let dataOff = off + 8
            if length > r.size { break }

            if ctype == "tIME", length >= 7 {
                let d = r.read(at: dataOff, count: 7)
                if d.count >= 7 {
                    // 布局：年 2 字节、月、日、时、分、秒 —— 秒在偏移 6
                    let s = Int(d[d.startIndex + 6])
                    let t = WallTime(year: d.be16(0), month: Int(d[d.startIndex + 2]),
                                     day: Int(d[d.startIndex + 3]),
                                     hour: Int(d[d.startIndex + 4]),
                                     minute: Int(d[d.startIndex + 5]),
                                     second: min(s, 59))
                    ttime = t.isPlausible ? t : nil
                }
            } else if (ctype == "iTXt" || ctype == "tEXt") && xmp.isEmpty {
                let raw = r.read(at: dataOff, count: min(length, 1 << 20))
                if let range = raw.range(of: Data("<x:xmpmeta".utf8)) {
                    let sub = raw.subdata(in: range.lowerBound..<raw.endIndex)
                    xmp = String(data: sub, encoding: .utf8) ?? ""
                }
            } else if ctype == "eXIf" {
                if let got = try? TIFF.parse(r, tiffOffset: dataOff) { exif = got }
            }
            if ctype == "IEND" { break }
            off = dataOff + length + 4
        }
        return (exif, xmp, ttime)
    }

    // MARK: - WebP

    static func readWebP(_ r: ByteReader) -> ([String: String], String) {
        var exif: [String: String] = [:]
        var xmp = ""
        var off = 12
        var guardCount = 0
        while off + 8 <= r.size && guardCount < 256 {
            guardCount += 1
            let hdr = r.read(at: off, count: 8)
            guard hdr.count >= 8 else { break }
            let ctype = String(bytes: hdr.subdata(in: (hdr.startIndex)..<(hdr.startIndex + 4)),
                               encoding: .isoLatin1) ?? ""
            let length = hdr.le32(4)                     // RIFF 是小端
            let dataOff = off + 8
            if length > r.size { break }

            if ctype == "EXIF" {
                let head = r.read(at: dataOff, count: 8)
                let base = head.starts(with: Array("Exif".utf8) + [0, 0]) ? dataOff + 6 : dataOff
                if let got = try? TIFF.parse(r, tiffOffset: base) { exif = got }
            } else if ctype == "XMP " {
                let raw = r.read(at: dataOff, count: min(length, 1 << 20))
                xmp = String(data: raw, encoding: .utf8) ?? ""
            }
            off = dataOff + length + (length & 1)        // 奇数长度要补一个字节
        }
        return (exif, xmp)
    }

    // MARK: - XMP

    /// 按优先级在 XMP 文本里找拍摄时间
    private static let xmpPatterns: [String] = [
        #"xmp:CreateDate\s*=\s*"([^"]+)"#,
        #"<xmp:CreateDate>\s*([^<]+?)\s*</xmp:CreateDate>"#,
        #"photoshop:DateCreated\s*=\s*"([^"]+)"#,
        #"<photoshop:DateCreated>\s*([^<]+?)\s*</photoshop:DateCreated>"#,
        #"xmp:DateCreated\s*=\s*"([^"]+)"#,
        #"<exif:DateTimeOriginal>\s*([^<]+?)\s*</exif:DateTimeOriginal>"#,
    ]

    static func parseXMPForDate(_ text: String) -> WallTime? {
        guard !text.isEmpty else { return nil }
        for pattern in xmpPatterns {
            guard let rx = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = rx.firstMatch(in: text,
                                        range: NSRange(location: 0, length: (text as NSString).length)),
                  m.numberOfRanges > 1 else { continue }
            let v = (text as NSString).substring(with: m.range(at: 1))
            if let t = PyFormat.parseDatetimeAny(v) { return t }
        }
        return nil
    }

    // MARK: - 旁车

    /// 返回 (xmp 旁车, takeout json 旁车)
    static func sidecarPaths(_ p: URL) -> (URL?, URL?) {
        let fm = FileManager.default
        var xmp: URL?
        for name in [p.lastPathComponent + ".xmp", p.deletingPathExtension().lastPathComponent + ".xmp"] {
            let cand = p.deletingLastPathComponent().appendingPathComponent(name)
            if fm.fileExists(atPath: cand.path) { xmp = cand; break }
        }
        var js: URL?
        for name in [p.lastPathComponent + ".json", p.deletingPathExtension().lastPathComponent + ".json"] {
            let cand = p.deletingLastPathComponent().appendingPathComponent(name)
            if cand == p { continue }
            if fm.fileExists(atPath: cand.path) { js = cand; break }
        }
        return (xmp, js)
    }

    /// Google Takeout 的 .json 旁车
    static func parseTakeoutJSON(_ url: URL) -> WallTime? {
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        // 标准结构：photoTakenTime / creationTime 里的 timestamp（Unix 秒）
        for key in ["photoTakenTime", "creationTime", "modificationTime"] {
            if let node = obj[key] as? [String: Any],
               let ts = node["timestamp"] {
                if let n = (ts as? NSNumber)?.doubleValue ?? Double(String(describing: ts)) {
                    return WallTime(date: Date(timeIntervalSince1970: n), timeZone: .current)
                }
            }
        }
        // 变体：直接放 ISO 字符串或数字
        for key in ["dateTaken", "captureDate", "date", "timestamp"] {
            guard let v = obj[key] else { continue }
            if let s = v as? String, let t = PyFormat.parseDatetimeAny(s) { return t }
            if let n = v as? NSNumber {
                return WallTime(date: Date(timeIntervalSince1970: n.doubleValue),
                                timeZone: .current)
            }
        }
        return nil
    }
}
