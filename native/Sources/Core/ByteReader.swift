import Foundation

/// 统一的内存 / 文件随机读取接口，offset 一律是**文件绝对偏移**。
///
/// 照片动辄几十 MB，不能整个读进内存；但 EXIF 解析又要随机跳着读，
/// 所以这里包一层 seek + read，接口保持和 Python 版的 `_Reader` 一致。
final class ByteReader {
    private let fh: FileHandle?
    private let mem: Data?
    let size: Int
    let url: URL?

    init(url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        self.size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        self.fh = try FileHandle(forReadingFrom: url)
        self.mem = nil
        self.url = url
    }

    init(data: Data) {
        self.size = data.count
        self.mem = data
        self.fh = nil
        self.url = nil
    }

    deinit { try? fh?.close() }

    /// 越界或长度非法一律返回空 Data，调用方按「读不到」处理，不抛异常
    func read(at off: Int, count n: Int) -> Data {
        guard off >= 0, off < size, n > 0 else { return Data() }
        let take = min(n, size - off)
        if let mem {
            return mem.subdata(in: off..<(off + take))
        }
        guard let fh else { return Data() }
        do {
            try fh.seek(toOffset: UInt64(off))
            return try fh.read(upToCount: take) ?? Data()
        } catch {
            return Data()
        }
    }

    func readAll(limit: Int = Int.max) -> Data {
        read(at: 0, count: min(limit, size))
    }

    func u16(_ off: Int, big: Bool = true) -> Int? {
        let b = read(at: off, count: 2)
        guard b.count == 2 else { return nil }
        return big ? Int(b[b.startIndex]) << 8 | Int(b[b.startIndex + 1])
                   : Int(b[b.startIndex + 1]) << 8 | Int(b[b.startIndex])
    }

    func u32(_ off: Int, big: Bool = true) -> Int? {
        let b = read(at: off, count: 4)
        guard b.count == 4 else { return nil }
        return b.int(0, count: 4, big: big)
    }

    func u64(_ off: Int, big: Bool = true) -> Int? {
        let b = read(at: off, count: 8)
        guard b.count == 8 else { return nil }
        return b.int(0, count: 8, big: big)
    }

    /// 4 字节 Box 类型（ISOBMFF 用），返回 ASCII 串
    func fourCC(_ off: Int) -> String? {
        let b = read(at: off, count: 4)
        guard b.count == 4 else { return nil }
        return String(bytes: b, encoding: .isoLatin1)
    }
}

extension Data {
    /// 从 `offset` 起读 `count` 字节的大端 / 小端无符号整数
    func int(_ offset: Int, count: Int, big: Bool = true) -> Int {
        guard offset >= 0, count > 0, offset + count <= self.count else { return 0 }
        var v = 0
        let base = startIndex + offset
        if big {
            for i in 0..<count { v = (v << 8) | Int(self[base + i]) }
        } else {
            for i in stride(from: count - 1, through: 0, by: -1) {
                v = (v << 8) | Int(self[base + i])
            }
        }
        return v
    }

    func be16(_ o: Int) -> Int { int(o, count: 2, big: true) }
    func be32(_ o: Int) -> Int { int(o, count: 4, big: true) }
    func le16(_ o: Int) -> Int { int(o, count: 2, big: false) }
    func le32(_ o: Int) -> Int { int(o, count: 4, big: false) }

    /// C 风格字符串：截到第一个 \0，UTF-8 解码失败就当 Latin-1
    func cString(at o: Int, maxLen: Int) -> String {
        guard o >= 0, o < count else { return "" }
        let end = Swift.min(count, o + maxLen)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(end - o)
        for i in o..<end {
            let b = self[startIndex + i]
            if b == 0 { break }
            bytes.append(b)
        }
        if let s = String(bytes: bytes, encoding: .utf8) { return s }
        return String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }

    func starts(with magic: [UInt8], at o: Int = 0) -> Bool {
        guard o >= 0, o + magic.count <= count else { return false }
        let base = startIndex + o
        for (i, m) in magic.enumerated() where self[base + i] != m { return false }
        return true
    }
}
