import Foundation

// MARK: - 预设读写的自检
//
// 预设是唯一「用户自己攒出来、丢了没法重建」的数据 —— 文件改名记录还能靠撤销恢复，
// 预设丢了就得一条条重填。所以这里守两件事：
//
//   1. 存进去再读出来，必须一模一样（含整条规则链、含 UUID）
//   2. 旧版本存的 JSON 缺字段时，不能整份解不出来 —— 少一个字段可以退回默认值，
//      但「六套预设全没了」是不可接受的
//
// 用法：preset-test <临时目录>

@main
struct PresetTest {

    static func main() {
        let argv = CommandLine.arguments
        let dir = argv.count > 1 ? argv[1] : NSTemporaryDirectory() + "ss-preset-test"
        setenv("SHUTTERSORT_STATE_DIR", dir, 1)

        var fails = 0
        func check(_ cond: Bool, _ label: String, _ extra: String = "") {
            print((cond ? "  ✓ " : "  ✗ ") + label + (cond ? "" : "　\(extra)"))
            if !cond { fails += 1 }
        }

        // ---- 1. 完整往返：六种规则全带上
        var insert = NameRule()
        insert.kind = .insert
        insert.anchor = .beforeText
        insert.anchorText = "2026"
        insert.text = "拍于"

        var clean = NameRule()
        clean.kind = .cleanUp
        clean.cleanBrackets = true
        clean.cleanSpaces = false
        clean.cleanSeparators = true
        clean.cleanEmoji = true

        var caser = NameRule()
        caser.kind = .changeCase
        caser.caseStyle = .sentence

        var p = NamingPreset(name: "相机原片")
        p.prefix = "DSC_"
        p.suffix = "_已整理"
        p.pattern = .originalDate
        p.archive = true
        p.archiveFormat = "%Y/%Y-%m"
        p.rules = [insert, clean, caser]

        PresetsStore.save([p])
        let loaded = PresetsStore.load()

        check(loaded.count == 1, "存一套读回一套", "读到 \(loaded.count) 套")
        if let q = loaded.first {
            check(q == p, "完整往返后每个字段都一致")
            check(q.rules.count == 3, "规则链三条都在", "实际 \(q.rules.count)")
            check(q.rules[1].cleanEmoji && q.rules[1].cleanSeparators
                  && !q.rules[1].cleanSpaces, "清理垃圾的四个开关没串位")
            check(q.rules[0].anchor == .beforeText && q.rules[0].anchorText == "2026",
                  "插入的锚点文字保住了")
            check(q.id == p.id, "UUID 没变（列表不会整块重建）")
        }

        // ---- 2. 同名覆盖
        var p2 = p
        p2.prefix = "MOV_"
        PresetsStore.save([p2])
        let afterOverwrite = PresetsStore.load()
        check(afterOverwrite.count == 1 && afterOverwrite.first?.prefix == "MOV_",
              "同名覆盖不会攒出两条")

        // ---- 3. 旧格式：缺字段的 JSON 也要能读出来
        let legacy = """
        [{"name":"老预设","format":"%Y%m%d","prefix":"OLD_",
          "rules":[{"kind":"删除","position":1,"count":3}]}]
        """
        let legacyURL = PresetsStore.fileURL
        try? FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(legacy.utf8).write(to: legacyURL)

        let old = PresetsStore.load()
        check(old.count == 1, "旧格式（缺一堆字段）仍能读出来", "读到 \(old.count) 套")
        if let o = old.first {
            check(o.name == "老预设" && o.prefix == "OLD_", "旧格式里有的字段保住了")
            check(o.suffix == "" && o.pattern == .dateOnly, "缺的字段退回默认值")
            check(o.rules.count == 1 && o.rules[0].kind == .delete
                  && o.rules[0].position == 1 && o.rules[0].count == 3,
                  "旧规则读得出类型与位置")
            check(o.rules[0].cleanBrackets && o.rules[0].cleanSpaces,
                  "旧规则没写清理开关时按默认值 true 处理")
        }

        // ---- 4. 文件不存在时返回空表，不崩
        try? FileManager.default.removeItem(at: PresetsStore.fileURL)
        check(PresetsStore.load().isEmpty, "没有预设文件时返回空表")

        // ---- 5. 坏 JSON 不崩
        try? Data("{ 这不是 JSON".utf8).write(to: PresetsStore.fileURL)
        check(PresetsStore.load().isEmpty, "文件损坏时返回空表而不是崩")

        print(fails == 0 ? "  预设自检全部通过" : "  \(fails) 项失败")
        exit(fails == 0 ? 0 : 1)
    }
}
