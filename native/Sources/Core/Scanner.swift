import Foundation

/// 目录扫描。
enum Scanner {

    static let imageExts: Set<String> = [
        ".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff", ".gif",
        ".heic", ".heif", ".avif",
        ".arw", ".nef", ".cr2", ".cr3", ".dng", ".rw2", ".orf", ".srw", ".raf", ".pef",
        ".jfif", ".jpe",
    ]

    static let videoExts: Set<String> = [
        ".mp4", ".mov", ".m4v", ".mkv", ".avi", ".wmv", ".webm",
        ".3gp", ".3g2", ".mts", ".m2ts", ".mpg", ".mpeg", ".m2v", ".flv", ".ts",
    ]

    static var mediaExts: Set<String> { imageExts.union(videoExts) }

    /// 这些扩展名是「附属文件」，永远不当媒体扫进来
    static let sidecarExts: Set<String> = [".xmp", ".json", ".aae", ".txt"]

    /// `URL.pathExtension` 不带点（"jpg"），而我们的集合都带点（".jpg"）
    static func dotExt(_ url: URL) -> String {
        "." + url.pathExtension.lowercased()
    }

    static func isMedia(_ url: URL) -> Bool {
        mediaExts.contains(dotExt(url))
    }

    /// 列出待处理文件。`picked` 非空时走「点名模式」：只处理这几个，
    /// 且不按扩展名过滤 —— 用户亲手挑的就该出现在列表里。
    static func collect(folder: URL?, recursive: Bool, onlyMedia: Bool,
                        picked: [URL]) -> [URL] {
        if !picked.isEmpty {
            return picked.filter {
                isRegularFile($0) && !$0.lastPathComponent.hasPrefix(".")
            }
        }
        guard let folder else { return [] }
        return walk(folder, recursive: recursive, onlyMedia: onlyMedia)
    }

    /// 自己递归而不用 `enumerator`：后者会把 `/tmp` 解析成 `/private/tmp`，
    /// 用户看到的路径就和选的不一样了。这里用字符串拼，保持用户输入的路径前缀。
    private static func walk(_ folder: URL, recursive: Bool, onlyMedia: Bool) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        var stack: [String] = [folder.path]

        while let dir = stack.popLast() {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names {
                if name.hasPrefix(".") { continue }
                let full = dir.hasSuffix("/") ? dir + name : dir + "/" + name
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    if recursive { stack.append(full) }
                    continue
                }
                let url = URL(fileURLWithPath: full)
                if accept(url, onlyMedia: onlyMedia) { out.append(url) }
            }
        }
        return out
    }

    private static func accept(_ url: URL, onlyMedia: Bool) -> Bool {
        guard isRegularFile(url) else { return false }
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return false }
        if sidecarExts.contains(dotExt(url)) { return false }
        if onlyMedia && !isMedia(url) { return false }
        return true
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return !isDir.boolValue
    }

    /// 统一的大小文案
    static func humanSize(_ n: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(n)
        for (i, unit) in units.enumerated() {
            if v < 1024 || i == units.count - 1 {
                return unit == "B" ? String(format: "%.0f %@", v, unit)
                                   : String(format: "%.1f %@", v, unit)
            }
            v /= 1024
        }
        return String(format: "%.1f TB", v)
    }

    /// 用 `stat(2)` 拿 size 和 mtime —— 精确到纳秒再换算成微秒，
    /// 比 `attributesOfItem` 的 `Date` 少一层浮点误差。
    static func statInfo(_ url: URL) -> (size: Int64, sec: Int, micro: Int) {
        var st = stat()
        guard url.path.withCString({ stat($0, &st) }) == 0 else { return (0, 0, 0) }
        var micro = (Int(st.st_mtimespec.tv_nsec) + 500) / 1000
        var sec = Int(st.st_mtimespec.tv_sec)
        if micro >= 1_000_000 { micro -= 1_000_000; sec += 1 }
        return (Int64(st.st_size), sec, micro)
    }

    /// 扫描一个文件，产出表格里的一行
    static func makeRow(_ url: URL, opts: ReadOptions,
                        exifToolMD: [String: String]?) -> MediaRow {
        let info = statInfo(url)
        let mtime = Date(timeIntervalSince1970: Double(info.sec) + Double(info.micro) / 1e6)

        let probe = Prober.probe(url: url, opts: opts, exifToolMD: exifToolMD)

        return MediaRow(
            path: url.path,
            dir: url.deletingLastPathComponent().path,
            name: url.lastPathComponent,
            ext: "." + url.pathExtension.lowercased(),
            size: info.size,
            sizeText: humanSize(info.size),
            mtime: mtime,
            mtimeSec: info.sec,
            mtimeMicro: info.micro,
            time: probe.time,
            source: probe.source,
            kind: probe.kind,
            note: probe.note,
            duration: probe.durationSec,
            exif: probe.exif
        )
    }
}
