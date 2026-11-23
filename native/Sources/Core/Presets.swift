import Foundation

/// 一套命名的全部设置，存下来随时切回。
///
/// 参照 ReNamer 的 Presets，但**只收跟命名有关的部分**：
/// 扫描哪个文件夹、时间校正多少、勾了哪些行 —— 这些每批都不一样，
/// 塞进预设反而碍事。预设要解决的是「同一套改法反复用」。
struct NamingPreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String

    // —— 名字怎么拼
    var format: String = "%Y%m%d_%H%M%S"
    var useCustomFormat: Bool = false
    var customFormat: String = ""
    var prefix: String = "IMG_"
    var suffix: String = ""
    var pattern: NamePattern = .dateOnly
    var archive: Bool = false
    var archiveFormat: String = "%Y/%Y-%m"

    /// 规则链，按顺序作用
    var rules: [NameRule] = []

    /// 侧栏上显示的一句摘要
    var summary: String {
        var parts: [String] = []
        let fmt = useCustomFormat && !customFormat.isEmpty ? customFormat : format
        parts.append(fmt)
        if !prefix.isEmpty { parts.append("前缀「\(prefix)」") }
        if !suffix.isEmpty { parts.append("后缀「\(suffix)」") }
        if archive { parts.append("归档") }
        if !rules.isEmpty { parts.append("\(rules.filter(\.enabled).count) 条规则") }
        return parts.joined(separator: " · ")
    }

    init(name: String) { self.name = name }

    /// 宽容解码 —— 和 `NameRule` 同一个理由：以后加字段不能让旧预设整份失效
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "未命名"
        format = (try? c.decode(String.self, forKey: .format)) ?? "%Y%m%d_%H%M%S"
        useCustomFormat = (try? c.decode(Bool.self, forKey: .useCustomFormat)) ?? false
        customFormat = (try? c.decode(String.self, forKey: .customFormat)) ?? ""
        prefix = (try? c.decode(String.self, forKey: .prefix)) ?? "IMG_"
        suffix = (try? c.decode(String.self, forKey: .suffix)) ?? ""
        pattern = (try? c.decode(NamePattern.self, forKey: .pattern)) ?? .dateOnly
        archive = (try? c.decode(Bool.self, forKey: .archive)) ?? false
        archiveFormat = (try? c.decode(String.self, forKey: .archiveFormat)) ?? "%Y/%Y-%m"
        rules = (try? c.decode([NameRule].self, forKey: .rules)) ?? []
    }
}

/// 预设的读写。
///
/// 存 `~/Library/Application Support/ShutterSort/presets.json`，
/// 跟撤销记录同一个目录（`Renamer.stateDir`），
/// 所以 `SHUTTERSORT_STATE_DIR` 也能把预设指到别处 —— 测试用得上。
enum PresetsStore {

    static var fileURL: URL {
        Renamer.stateDir.appendingPathComponent("presets.json")
    }

    static func load() -> [NamingPreset] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([NamingPreset].self, from: data)) ?? []
    }

    /// 先写临时文件再原子替换。
    /// 直接往目标文件里写，中途断电会留下一个半截 JSON，下次启动预设就全没了。
    static func save(_ list: [NamingPreset]) {
        Renamer.ensureDirs()
        guard let data = try? JSONEncoder().encode(list) else { return }
        let tmp = fileURL.deletingLastPathComponent()
            .appendingPathComponent("presets.json.tmp")
        do {
            try data.write(to: tmp)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
        } catch {
            try? data.write(to: fileURL)
        }
    }
}
