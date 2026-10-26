import Foundation

/// TIFF / EXIF 解析器。
///
/// 照 `media_time.parse_tiff` 逐行移植，几个容易踩的点都在注释里标出来了：
///  · 子 IFD（ExifIFD / GPSIFD）要跟进队列，深度有上限防死循环
///  · value 字段 ≤4 字节时数据**内联**在偏移位置，不能当偏移去解 —— 真实相机
///    写 SubSecTime 就是这么写的，把 "42" 当偏移读出来会变成垃圾
///  · ASCII / UNDEFINED 要截到第一个 \0
enum TIFF {

    static let typeSize: [Int: Int] = [
        1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8,
    ]

    static let tagNames: [Int: String] = [
        0x010F: "Make", 0x0110: "Model", 0x0112: "Orientation",
        0x0132: "DateTime", 0x8769: "ExifIFD", 0x8825: "GPSIFD",
        0x9003: "DateTimeOriginal", 0x9004: "DateTimeDigitized",
        0x9000: "ExifVersion", 0x9010: "OffsetTime",
        0x9011: "OffsetTimeOriginal", 0x9012: "OffsetTimeDigitized",
        0x9290: "SubSecTime", 0x9291: "SubSecTimeOriginal", 0x9292: "SubSecTimeDigitized",
        0xA002: "PixelXDimension", 0xA003: "PixelYDimension",
        0x013B: "Artist", 0x8298: "Copyright",
    ]

    /// 解析信息栏里要展示的字段（顺序即展示顺序）
    static let textTags: [String] = [
        "DateTimeOriginal", "DateTimeDigitized", "DateTime",
        "OffsetTimeOriginal", "OffsetTimeDigitized", "OffsetTime",
        "SubSecTimeOriginal", "SubSecTimeDigitized", "SubSecTime",
        "Make", "Model", "Orientation", "PixelXDimension", "PixelYDimension",
    ]

    enum TiffError: Error {
        case truncated, badByteOrder, badMagic
    }

    /// 解析 TIFF 头（EXIF 也走这里），返回 [标签名: 字符串值]
    static func parse(_ reader: ByteReader, tiffOffset: Int, maxIFD: Int = 6) throws -> [String: String] {
        let head = reader.read(at: tiffOffset, count: 8)
        guard head.count >= 8 else { throw TiffError.truncated }

        let big: Bool
        if head.starts(with: [0x49, 0x49]) {          // "II"
            big = false
        } else if head.starts(with: [0x4D, 0x4D]) {   // "MM"
            big = true
        } else {
            throw TiffError.badByteOrder
        }
        guard reader.u16(tiffOffset + 2, big: big) == 42 else { throw TiffError.badMagic }

        var out: [String: String] = [:]
        var visited = Set<Int>()
        var queue: [(Int, Int)] = [(reader.u32(tiffOffset + 4, big: big).map { $0 } ?? 0, 0)]

        while !queue.isEmpty {
            let (off, depth) = queue.removeFirst()
            guard off > 0, !visited.contains(off), depth <= maxIFD else { continue }
            visited.insert(off)

            let cntBytes = reader.read(at: tiffOffset + off, count: 2)
            guard cntBytes.count >= 2 else { continue }
            let count = big ? cntBytes.be16(0) : cntBytes.le16(0)
            guard count > 0, count <= 4096 else { continue }

            let entries = reader.read(at: tiffOffset + off + 2, count: count * 12)
            for i in 0..<count {
                let e = i * 12
                guard e + 12 <= entries.count else { break }
                let tag = big ? entries.be16(e) : entries.le16(e)
                let typ = big ? entries.be16(e + 2) : entries.le16(e + 2)
                let num = big ? entries.be32(e + 4) : entries.le32(e + 4)
                let size = (typeSize[typ] ?? 1) * num

                // ≤4 字节内联在 e+8，否则 e+8 是偏移
                let payload: Data
                if size <= 4 {
                    payload = entries.subdata(in: (entries.startIndex + e + 8)
                                              ..< min(entries.endIndex, entries.startIndex + e + 12))
                } else {
                    let at = big ? entries.be32(e + 8) : entries.le32(e + 8)
                    payload = reader.read(at: tiffOffset + at, count: min(size, 65535))
                }

                if tag == 0x8769 || tag == 0x8825 {          // Exif / GPS 子 IFD
                    if size >= 4 && payload.count >= 4 {
                        let sub = big ? payload.be32(0) : payload.le32(0)
                        queue.append((sub, depth + 1))
                    }
                    continue
                }

                guard let name = tagNames[tag], out[name] == nil else { continue }

                if typ == 2 || typ == 7 {                     // ASCII / UNDEFINED
                    out[name] = payload.cString(at: 0, maxLen: payload.count)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else if typ == 1 || typ == 3 || typ == 4 {
                    let w = typeSize[typ] ?? 1
                    if size >= w, !payload.isEmpty {
                        var v = 0
                        for k in 0..<min(w, payload.count) {
                            v = big ? (v << 8) | Int(payload[payload.startIndex + k])
                                    : v | (Int(payload[payload.startIndex + k]) << (8 * k))
                        }
                        out[name] = String(v)
                    }
                } else if typ == 5 || typ == 9 || typ == 10 {
                    if payload.count >= 8 {
                        let n = big ? payload.be32(0) : payload.le32(0)
                        var d = big ? payload.be32(4) : payload.le32(4)
                        if d == 0 { d = 1 }
                        out[name] = String(Double(n) / Double(d))
                    }
                }
            }
        }
        return out
    }

    /// 暴力扫描 TIFF 头（HEIC 这类容器里 EXIF 偏移不好定位时用）。
    /// 从文件里找 `Exif\0\0` / `II*\0` / `MM\0*` 三种魔数，返回其后紧跟 TIFF 头的位置。
    static func scanMagic(_ reader: ByteReader, limit: Int = 4 << 20) -> [Int] {
        let data = reader.read(at: 0, count: min(limit, reader.size))
        let exifMagic: [UInt8] = Array("Exif".utf8) + [0, 0]
        let iiMagic: [UInt8] = [0x49, 0x49, 0x2A, 0x00]
        let mmMagic: [UInt8] = [0x4D, 0x4D, 0x00, 0x2A]
        var hits: [Int] = []
        var i = 0
        while i + 4 <= data.count {
            let base = data.startIndex + i
            if data[base] == 0x45 || data[base] == 0x49 || data[base] == 0x4D {
                if data.starts(with: exifMagic, at: i) {
                    hits.append(i + 6)          // 跳过 "Exif\0\0"，指向 TIFF 头
                } else if data.starts(with: iiMagic, at: i) || data.starts(with: mmMagic, at: i) {
                    hits.append(i)
                }
            }
            i += 1
        }
        return hits
    }
}
