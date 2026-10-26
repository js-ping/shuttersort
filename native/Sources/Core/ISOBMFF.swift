import Foundation

/// ISOBMFF 容器解析（MP4 / MOV / M4V / HEIC / HEIF / AVIF）。
///
/// 核心是两条路径：
///  · 视频：`moov/mvhd` 的创建时间 + `moov/udta/meta/ilst` 里的元数据字符串
///  · HEIC：没有 moov，时间藏在 `meta/iloc` 指向的 Exif item 里
///
/// 1904 纪元那个坑记一下：`mvhd` / `mdhd` 的 creation_time 是
/// **1904-01-01 00:00:00 UTC 起的秒数**，必须按 UTC 解释再转本地，
/// 直接当本地时间用会整整早一个时区偏移。
enum ISOBMFF {

    /// full box：内容前 4 字节是 version + flags，子 box 从 +4 开始
    static let fullBoxes: Set<String> = [
        "meta", "iinf", "iloc", "pitm", "keys", "hdlr", "dref", "stsd",
    ]

    /// 1904-01-01T00:00:00Z 相对 1970-01-01 的秒数（负值）
    static let epoch1904From1970: Double = -2_082_844_800

    struct Box {
        let type: String
        let contentStart: Int
        let contentEnd: Int
    }

    struct IsoResult {
        var mvhd: WallTime?
        var mdhd: WallTime?
        var ilst: [String: String] = [:]
        var durationSec: Double?
        var handler: String = ""
        var exif: [String: String] = [:]
        var createdStr: String = ""
    }

    // MARK: - Box 遍历

    static func iterBoxes(_ r: ByteReader, from start: Int, to end: Int) -> [Box] {
        var out: [Box] = []
        var off = start
        var guardCount = 0
        while off + 8 <= end && guardCount < 4096 {
            guardCount += 1
            let hdr = r.read(at: off, count: 8)
            guard hdr.count >= 8 else { break }
            var size = hdr.be32(0)
            let type = String(bytes: hdr.subdata(in: (hdr.startIndex + 4)..<(hdr.startIndex + 8)),
                              encoding: .isoLatin1) ?? ""
            var header = 8
            if size == 1 {                        // 64 位 length
                let big = r.read(at: off + 8, count: 8)
                guard big.count >= 8 else { break }
                size = big.int(0, count: 8, big: true)
                header = 16
            } else if size == 0 {                 // 延伸到文件尾
                size = end - off
            }
            guard size >= header, off + size <= end else { break }
            out.append(Box(type: type, contentStart: off + header, contentEnd: off + size))
            off += size
        }
        return out
    }

    /// 深度优先查找指定路径的 box
    static func findBoxes(_ r: ByteReader, from start: Int, to end: Int,
                          path: [String], depth: Int = 0) -> [Box] {
        guard depth <= 8 else { return [] }
        var out: [Box] = []
        for box in iterBoxes(r, from: start, to: end) {
            if let head = path.first, box.type != head { continue }
            let rest = path.isEmpty ? [] : Array(path.dropFirst())
            if rest.isEmpty {
                out.append(box)
            } else {
                let inner = fullBoxes.contains(box.type)
                    ? box.contentStart + 4 : box.contentStart
                out += findBoxes(r, from: inner, to: box.contentEnd, path: rest, depth: depth + 1)
            }
        }
        return out
    }

    // MARK: - 时间

    /// 解析 mvhd / mdhd 的创建时间
    static func parseTimeBox(_ r: ByteReader, contentStart cs: Int) -> WallTime? {
        let vf = r.read(at: cs, count: 4)
        guard vf.count >= 4 else { return nil }
        let version = vf[vf.startIndex]
        let secs: Int
        if version == 1 {
            let raw = r.read(at: cs + 4, count: 8)
            guard raw.count >= 8 else { return nil }
            secs = raw.int(0, count: 8, big: true)
        } else {
            let raw = r.read(at: cs + 4, count: 4)
            guard raw.count >= 4 else { return nil }
            secs = raw.be32(0)
        }
        guard secs > 0, secs <= 0xFFFF_FFFF else { return nil }
        let abs = Date(timeIntervalSince1970: epoch1904From1970 + Double(secs))
        guard let t = WallTime(date: abs, timeZone: .current) else { return nil }
        // 明显早于 1970 的当作无效值
        guard t.year >= 1970, t.year <= 2200 else { return nil }
        return t
    }

    // MARK: - keys / ilst

    static func parseKeys(_ r: ByteReader, contentStart cs: Int, contentEnd ce: Int) -> [String] {
        var names: [String] = []
        let vf = r.read(at: cs, count: 4)
        guard vf.count >= 4 else { return names }
        let version = vf[vf.startIndex]
        var off = cs + 4
        var count: Int
        if version >= 1 {
            count = r.u32(off) ?? 0
            off += 4
        } else {
            let b = r.read(at: off, count: 2)
            count = b.count == 2 ? b.be16(0) : 0
            off += 2
        }
        guard count > 0, count <= 1024 else { return names }
        for _ in 0..<count {
            guard off + 8 <= ce else { break }
            let size = r.u32(off) ?? 0
            guard size >= 8 else { break }
            let raw = r.read(at: off + 8, count: size - 8)
            names.append(String(data: raw, encoding: .utf8) ?? "")
            off += size
        }
        return names
    }

    static func parseIlst(_ r: ByteReader, contentStart cs: Int, contentEnd ce: Int,
                          keys: [String]?) -> [String: String] {
        var out: [String: String] = [:]
        for item in iterBoxes(r, from: cs, to: ce) {
            // 带 keys 时，item 的类型其实是 1 起的索引
            var label = item.type
            let idx = item.type.utf8.reduce(0) { $0 << 8 | Int($1) }
            if let keys, idx >= 1, idx <= keys.count {
                label = keys[idx - 1]
            }
            for data in iterBoxes(r, from: item.contentStart, to: item.contentEnd) {
                guard data.type == "data" else { continue }
                let head = r.read(at: data.contentStart, count: 8)
                guard head.count >= 8 else { continue }
                let len = min(data.contentEnd - data.contentStart - 8, 512)
                let payload = r.read(at: data.contentStart + 8, count: len)
                guard !payload.isEmpty else { continue }
                let txt = (String(data: payload, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !txt.isEmpty && out[label] == nil { out[label] = txt }
            }
        }
        return out
    }

    // MARK: - 主流程

    static func parse(_ r: ByteReader, deepExif: Bool = true) -> IsoResult {
        var res = IsoResult()
        let top = iterBoxes(r, from: 0, to: r.size)

        var moov: Box?
        var metaTop: Box?
        for box in top {
            if box.type == "moov", moov == nil { moov = box }
            else if box.type == "meta", metaTop == nil { metaTop = box }
        }

        if let moov {
            for box in iterBoxes(r, from: moov.contentStart, to: moov.contentEnd) {
                if box.type == "mvhd", res.mvhd == nil {
                    res.mvhd = parseTimeBox(r, contentStart: box.contentStart)
                } else if box.type == "trak" {
                    for t2 in iterBoxes(r, from: box.contentStart, to: box.contentEnd) {
                        guard t2.type == "mdia" else { continue }
                        for t3 in iterBoxes(r, from: t2.contentStart, to: t2.contentEnd) {
                            if t3.type == "mdhd", res.mdhd == nil {
                                res.mdhd = parseTimeBox(r, contentStart: t3.contentStart)
                            } else if t3.type == "hdlr", res.handler.isEmpty {
                                let raw = r.read(at: t3.contentStart + 8, count: 4)
                                res.handler = String(data: raw, encoding: .isoLatin1)?
                                    .trimmingCharacters(in: .whitespaces) ?? ""
                            }
                        }
                    }
                }
            }

            // ilst 可能出现在 moov/meta 或 moov/udta/meta
            var keys: [String] = []
            for meta in findBoxes(r, from: moov.contentStart, to: moov.contentEnd, path: ["meta"]) {
                let inner = meta.contentStart + 4
                for b in iterBoxes(r, from: inner, to: meta.contentEnd) where b.type == "keys" {
                    keys = parseKeys(r, contentStart: b.contentStart, contentEnd: b.contentEnd)
                }
                for b in iterBoxes(r, from: inner, to: meta.contentEnd) where b.type == "ilst" {
                    res.ilst.merge(parseIlst(r, contentStart: b.contentStart,
                                             contentEnd: b.contentEnd, keys: keys)) { _, new in new }
                }
            }
            for meta in findBoxes(r, from: moov.contentStart, to: moov.contentEnd,
                                  path: ["udta", "meta"]) {
                let inner = meta.contentStart + 4
                for b in iterBoxes(r, from: inner, to: meta.contentEnd) where b.type == "ilst" {
                    res.ilst.merge(parseIlst(r, contentStart: b.contentStart,
                                             contentEnd: b.contentEnd, keys: keys)) { _, new in new }
                }
            }

            // 时长
            for box in iterBoxes(r, from: moov.contentStart, to: moov.contentEnd)
            where box.type == "mvhd" {
                let vf = r.read(at: box.contentStart, count: 4)
                var timescale = 0
                var duration = 0
                if !vf.isEmpty && vf[vf.startIndex] == 1 {
                    timescale = r.u32(box.contentStart + 20) ?? 0
                    duration = r.read(at: box.contentStart + 24, count: 8).int(0, count: 8, big: true)
                } else {
                    timescale = r.u32(box.contentStart + 12) ?? 0
                    duration = r.u32(box.contentStart + 16) ?? 0
                }
                if timescale != 0 { res.durationSec = Double(duration) / Double(timescale) }
                break
            }
        }

        // Keys:CreationDate / ©day 这类字符串时间（自由文本，不含时区语义）
        for key in res.ilst.keys.sorted() {
            if key.lowercased().contains("creationdate") || key == "\u{00A9}day"
                || key == "\u{00A9}DAY" {
                res.createdStr = res.ilst[key] ?? ""
                break
            }
        }

        // HEIC / AVIF：没有 moov，从 meta 里找 Exif item
        if deepExif, let metaTop, res.createdStr.isEmpty, res.mvhd == nil {
            res.exif = heicExif(r, metaStart: metaTop.contentStart, metaEnd: metaTop.contentEnd)
        }
        return res
    }

    // MARK: - HEIC Exif

    static func heicExif(_ r: ByteReader, metaStart: Int, metaEnd: Int) -> [String: String] {
        let inner = metaStart + 4
        var itemIDs: [Int: String] = [:]
        var iloc: [Int: (Int, Int)] = [:]

        for box in iterBoxes(r, from: inner, to: metaEnd) {
            if box.type == "iinf" {
                let vf = r.read(at: box.contentStart, count: 4)
                guard vf.count >= 4 else { continue }
                var off = box.contentStart + 4
                var count: Int
                if vf[vf.startIndex] >= 1 {
                    count = r.u32(off) ?? 0
                    off += 4
                } else {
                    let b = r.read(at: off, count: 2)
                    count = b.count == 2 ? b.be16(0) : 0
                    off += 2
                }
                for _ in 0..<min(count, 512) {
                    let infes = iterBoxes(r, from: off, to: box.contentEnd)
                    guard let infe = infes.first(where: { $0.type == "infe" }) else { break }
                    let hd = r.read(at: infe.contentStart, count: 12)
                    guard hd.count >= 12 else { break }
                    let ver = hd[hd.startIndex]
                    let iid = hd.be16(4)
                    let itypeRaw = String(bytes: hd.subdata(in: (hd.startIndex + 8)..<(hd.startIndex + 12)),
                                          encoding: .isoLatin1) ?? ""
                    let itype = ver >= 2 ? itypeRaw : "?" + itypeRaw
                    itemIDs[iid] = itype.trimmingCharacters(in: .whitespaces)
                    off = infe.contentEnd
                }
            } else if box.type == "iloc" {
                iloc = parseIloc(r, contentStart: box.contentStart, contentEnd: box.contentEnd)
            }
        }

        for (iid, itype) in itemIDs {
            guard itype.lowercased() == "exif", let (off, length) = iloc[iid] else { continue }
            guard off > 0, length > 8, off + length <= r.size else { continue }
            let hdr = r.read(at: off, count: 4)
            guard hdr.count >= 4 else { continue }
            let delta = hdr.be32(0)
            var tiffOff = off + 4 + delta
            if !(delta > 0 && delta < 4096) { tiffOff = off + 4 }
            for cand in [tiffOff, off + 4, off + 6, off] {
                if let got = try? TIFF.parse(r, tiffOffset: cand), !got.isEmpty { return got }
            }
        }

        // 兜底：暴力扫 TIFF 魔数
        for cand in TIFF.scanMagic(r) {
            if let got = try? TIFF.parse(r, tiffOffset: cand),
               got["DateTimeOriginal"] != nil || got["DateTime"] != nil {
                return got
            }
        }
        return [:]
    }

    /// 解析 iloc（只支持 construction_method = 0）
    static func parseIloc(_ r: ByteReader, contentStart cs: Int, contentEnd ce: Int) -> [Int: (Int, Int)] {
        var out: [Int: (Int, Int)] = [:]
        let vf = r.read(at: cs, count: 4)
        guard vf.count >= 4 else { return out }
        let version = vf[vf.startIndex]
        var off = cs + 4
        let b = r.read(at: off, count: 2)
        guard b.count >= 2 else { return out }
        let sizes = Int(b[b.startIndex])
        var count: Int
        if version < 2 {
            let b2 = r.read(at: off + 2, count: 2)
            guard b2.count >= 2 else { return out }
            count = b2.be16(0)
            off += 4
        } else {
            count = r.u32(off + 2) ?? 0
            off += 6
        }

        let offsetSize = sizes >> 4
        let lengthSize = sizes & 0x0F
        let b3 = r.read(at: off, count: 2)
        guard b3.count >= 2 else { return out }
        let baseOffsetSize = Int(b3[b.startIndex]) >> 4
        let indexSize = (version == 1 || version == 2) ? Int(b3[b.startIndex + 1]) : 0
        off += 2

        func take(_ n: Int) -> Int {
            guard n > 0 else { return 0 }
            let raw = r.read(at: off, count: n)
            off += n
            return raw.int(0, count: raw.count, big: true)
        }

        for _ in 0..<min(count, 1024) {
            guard off < ce else { break }
            let iid = version < 2 ? take(2) : take(4)
            if version == 1 || version == 2 { _ = take(2) }   // construction_method
            _ = take(2)                                        // data_reference_index
            let baseOffset = take(baseOffsetSize)
            let extCount = take(2)
            for _ in 0..<min(extCount, 8) {
                if indexSize != 0 { _ = take(indexSize) }
                let eoff = take(offsetSize)
                let elen = take(lengthSize)
                if eoff != 0 && elen != 0 && out[iid] == nil {
                    out[iid] = (baseOffset + eoff, elen)
                }
            }
        }
        return out
    }
}
