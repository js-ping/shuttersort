import AppKit
import Foundation

// MARK: - 「时间戳来源」切换的回归测试
//
// 这条路径曾经是坏的：把「时间戳来源」从「跳过」改成「用文件修改时间」，
// 右侧列表纹丝不动 —— 因为切换只重算了新文件名，没有重新取时间。
// 用户会以为选项没生效，然后手工去勾选那些「无时间戳」的行，白忙一场。
//
// 这里把行为钉死：
//   1. 切到「修改时间」→ 原本无时间的行全部拿到时间，来源标成「文件系统·修改时间」
//   2. 再切「创建时间」→ 旧的修改时间必须被替换掉，不能留着冒充创建时间
//   3. 再切回「跳过」→ 兜底来的时间要全部剥掉，退回「无时间戳」
//   4. 全程有 EXIF 的行不受影响 —— 兜底不该覆盖真正的拍摄时间
//
// 用法：fallback-test <样本目录>

@main
struct FallbackTest {

    @MainActor
    static func main() {
        let argv = CommandLine.arguments
        let corpus = argv.count > 1 ? argv[1] : ""
        guard !corpus.isEmpty else {
            print("用法：fallback-test <样本目录>")
            exit(2)
        }

        var fails = 0
        func check(_ cond: Bool, _ label: String, _ extra: String = "") {
            print((cond ? "  ✓ " : "  ✗ ") + label + (cond ? "" : "　\(extra)"))
            if !cond { fails += 1 }
        }

        let st = AppState()
        st.fallback = .skip
        st.openFolder(at: URL(fileURLWithPath: corpus))

        let deadline = Date().addingTimeInterval(180)
        while (st.scanning || st.plan.isEmpty) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        guard !st.plan.isEmpty else {
            print("  ✗ 扫描没出结果，样本目录对吗：\(corpus)")
            exit(1)
        }

        // 基线：跳过模式下有多少行没有时间
        let baseSkipped = st.plan.filter { $0.status == .skip }.count
        let baseRows = st.plan.count
        let withRealTime = st.plan.filter { $0.status != .skip }
        let realStamps = withRealTime.map { "\($0.path)|\($0.displayTime?.stampWithMicroIfAny ?? "")" }

        print("基线：\(baseRows) 个文件，其中 \(baseSkipped) 个无时间戳")

        // ---- 1. 切到「修改时间」
        st.fallback = .modified
        st.applyFallbackChange()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        check(st.plan.filter { $0.status == .skip }.count == 0,
              "切到修改时间后不再有「无时间戳」",
              "还剩 \(st.plan.filter { $0.status == .skip }.count) 个")
        let modRows = st.plan.filter { $0.source == "文件系统·修改时间" }
        check(modRows.count == baseSkipped,
              "兜底填补的行数正好等于原来的 \(baseSkipped) 个",
              "实际 \(modRows.count)")
        check(st.plan.allSatisfy { $0.status == .ok || $0.status == .same },
              "所有行都算出了新文件名")
        check(modRows.allSatisfy { st.selection.contains($0.path) },
              "兜底救回来的行自动勾上（否则按钮还写着改 0 个）")

        // ---- 2. 切到「创建时间」：旧的修改时间必须被换掉
        st.fallback = .created
        st.applyFallbackChange()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let createdRows = st.plan.filter { $0.source == "文件系统·创建时间" }
        let leftoverMod = st.plan.filter { $0.source == "文件系统·修改时间" }
        check(leftoverMod.isEmpty, "切到创建时间后没有残留的「修改时间」",
              "残留 \(leftoverMod.count) 个")
        check(createdRows.count == baseSkipped,
              "创建时间填补的行数仍然等于 \(baseSkipped)",
              "实际 \(createdRows.count)")

        // ---- 3. 切回「跳过」：兜底全撤掉
        st.fallback = .skip
        st.applyFallbackChange()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let fsleft = st.plan.filter { $0.source.hasPrefix("文件系统·") }
        check(fsleft.isEmpty, "切回跳过模式后兜底来源全部撤掉", "还剩 \(fsleft.count) 个")
        check(st.plan.filter { $0.status == .skip }.count == baseSkipped,
              "「无时间戳」数量回到基线 \(baseSkipped)",
              "实际 \(st.plan.filter { $0.status == .skip }.count)")

        // ---- 4. 真正的拍摄时间不该被兜底改写
        let after = st.plan.filter { $0.status != .skip }
            .map { "\($0.path)|\($0.displayTime?.stampWithMicroIfAny ?? "")" }
        check(after == realStamps, "有真实时间的行，时间一个都没变",
              "连兜底都改了本来就有时间的行")

        print(fails == 0 ? "  时间戳来源切换自检全部通过" : "  \(fails) 项失败")
        exit(fails == 0 ? 0 : 1)
    }
}
