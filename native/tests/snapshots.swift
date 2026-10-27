import AppKit
import SwiftUI

// MARK: - 界面快照
//
// 把真实的 SwiftUI 视图离屏渲染成 PNG，不依赖屏幕、不需要应用窗口。
//
// 为什么要有这个：界面改动最容易出的问题是「布局挤了、字被裁了、深浅色下看不清」，
// 而这些只有在真正画出来的时候才看得出来。截图要有人盯着屏幕、还要系统不锁屏；
// 这个工具随时能跑，也能在 CI 上跑。
//
// 局限（写在这里免得误判）：
//   · `Table` / `List` 是 AppKit 支撑的控件，离屏渲染出来会是空白 ——
//     表格本身要看真窗口，但单元格、侧栏、各种弹窗都能在这里看
//
// 用法：
//   snapshots --corpus <样本目录> --out <输出目录> [--dark]

struct SnapArgs {
    var corpus = ""
    var out = "snapshots-out"
    var dark = false

    static func parse() -> SnapArgs {
        var a = SnapArgs()
        let argv = Array(CommandLine.arguments.dropFirst())
        var i = 0
        while i < argv.count {
            switch argv[i] {
            case "--corpus": if i + 1 < argv.count { a.corpus = argv[i + 1]; i += 1 }
            case "--out": if i + 1 < argv.count { a.out = argv[i + 1]; i += 1 }
            case "--dark": a.dark = true
            case "--light": a.dark = false
            default: break
            }
            i += 1
        }
        return a
    }
}

@MainActor
final class Snapper {
    let state = AppState()
    let outDir: URL

    init(outDir: URL) {
        self.outDir = outDir
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    /// 扫一遍并把主线程 runloop 跑到扫描结束
    func load(corpus: String, offsetHours: Int) {
        state.folder = URL(fileURLWithPath: corpus)
        state.scope = .folder
        if offsetHours != 0 {
            state.correctionOn = true
            state.corrHours = offsetHours
        }
        state.startScan()
        let deadline = Date().addingTimeInterval(60)
        while state.scanning, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        // 让防抖那一层也过掉
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    }

    /// 离屏渲染一张图。
    ///
    /// 用 NSHostingView + cacheDisplay，而不是 ImageRenderer —— 后者画不出
    /// ScrollView / Button / List / Table（会渲染成一块「不可用」的占位），
    /// 而那几样恰好是界面里最主要的部分。AppKit 这条老路在 CI 这种没有屏幕的
    /// 机器上也能跑。
    func shoot<C: View>(_ name: String, _ content: C, width: CGFloat, height: CGFloat) {
        let size = NSSize(width: width, height: height)
        let host = NSHostingView(rootView: content.environmentObject(state))
        host.frame = NSRect(origin: .zero, size: size)

        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.appearance = NSApp.appearance
        win.collectionBehavior = [.transient]
        win.isReleasedWhenClosed = false

        // 让 SwiftUI 把布局、异步加载（缩略图、历史记录）都跑完
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        }

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            print("  ✗ 建不出位图：\(name)")
            return
        }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("  ✗ 编码失败：\(name)")
            return
        }
        let url = outDir.appendingPathComponent(name + ".png")
        do {
            try png.write(to: url)
            print("  → \(url.lastPathComponent)  \(Int(size.width))×\(Int(size.height))")
        } catch {
            print("  ✗ 写文件失败：\(name) \(error.localizedDescription)")
        }
        win.contentView = nil
    }

    func run(corpus: String) {
        load(corpus: corpus, offsetHours: 8)
        print("扫描完成：\(state.plan.count) 项（待改名 \(state.stats.rename)"
              + " / 无需改动 \(state.stats.same) / 无时间戳 \(state.stats.skip)）")

        let W = DetailPane.ColWidth.self

        // 侧栏五张卡 + 底栏（默认状态：规则链为空，应显示引导文字）
        state.rules = []
        state.rebuildPlan(immediate: true)
        shoot("sidebar", SidebarView(), width: Theme.sidebarWidth, height: 780)

        // 侧栏 + 五种规则各一条，专门看那块 UI 排得下排不下
        state.rules = [
            { var r = NameRule(); r.kind = .insert; r.anchor = .position
              r.position = 4; r.text = "-"; return r }(),
            { var r = NameRule(); r.kind = .delete; r.position = 1; r.count = 4; return r }(),
            { var r = NameRule(); r.kind = .replace; r.text = "IMG_"; r.replacement = "照片_"; return r }(),
            { var r = NameRule(); r.kind = .strip; r.charset = .space; return r }(),
            { var r = NameRule(); r.kind = .changeCase; r.caseStyle = .lower; return r }(),
        ]
        state.rebuildPlan(immediate: true)
        shoot("sidebar-rules", SidebarView(), width: Theme.sidebarWidth, height: 1180)

        // 只留两条真正干活的规则，拍表格看「新文件名」列的实际结果
        state.rules = [
            { var r = NameRule(); r.kind = .replace; r.text = "IMG_"; r.replacement = "照片_"; return r }(),
            { var r = NameRule(); r.kind = .insert; r.anchor = .position
              r.position = 4; r.text = "-"; return r }(),
        ]
        state.rebuildPlan(immediate: true)
        shoot("detail-pane-rules", DetailPane(),
              width: 1360 - Theme.sidebarWidth - 1, height: 800)

        // 恢复干净状态，后面的图不受影响
        state.rules = []
        state.rebuildPlan(immediate: true)

        // 表格里的单元格：列宽够不够，只有按真实列宽渲染才看得出来
        if let withBadge = state.plan.first(where: { $0.status == .ok && $0.displayTime != nil }) {
            shoot("cell-time", cellRow(AnyView(TimeCell(item: withBadge, offsetLabel: state.offsetShortLabel))),
                  width: W.timeIdeal, height: 26)
        }
        if let sub = state.plan.first(where: { ($0.displayTime?.micro ?? 0) != 0 }) {
            shoot("cell-time-subsec", cellRow(AnyView(TimeCell(item: sub, offsetLabel: state.offsetShortLabel))),
                  width: W.timeIdeal, height: 26)
        }
        if let conflict = state.plan.first(where: { !$0.conflict.isEmpty }) {
            shoot("cell-newname", cellRow(AnyView(NewNameCell(item: conflict))),
                  width: W.newNameIdeal, height: 26)
        }

        // 整个右半栏（含表格）
        shoot("detail-pane", DetailPane(),
              width: 1360 - Theme.sidebarWidth - 1, height: 800)

        // 五个弹窗，尺寸照各自声明的来
        if let item = state.plan.first(where: { $0.status == .ok }) {
            shoot("sheet-detail", DetailSheet(item: item), width: 620, height: 540)
        }
        shoot("sheet-confirm", ConfirmSheet(), width: 540, height: 460)
        shoot("sheet-calibrate", CalibrateSheet(), width: 480, height: 380)
        shoot("sheet-help", HelpSheet(), width: 660, height: 620)
        // 帮助页是 ScrollView，620 只拍得到开头。整页拉长再拍一张，
        // 用来核对新增小节（以及以后任何加进来的内容）排版有没有问题。
        shoot("sheet-help-full", HelpSheet(height: 1500), width: 660, height: 1500)

        state.loadHistory()
        state.showHistory = false
        shoot("sheet-history", HistorySheet(), width: 580, height: 440)
    }

    /// 单元格外面套一层，模拟表格里的实际画法（左对齐 + 右侧留白）
    private func cellRow(_ inner: AnyView) -> some View {
        HStack(spacing: 0) {
            inner
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

@main
struct SnapshotTool {
    static func main() {
        let args = SnapArgs.parse()
        guard !args.corpus.isEmpty else {
            FileHandle.standardError.write(
                Data("用法：snapshots --corpus <样本目录> --out <输出目录> [--dark]\n".utf8))
            exit(2)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: args.dark ? .darkAqua : .aqua)

        // main() 本身就在主线程上跑，这里直接当主 actor 用
        MainActor.assumeIsolated {
            print("== 渲染界面快照（\(args.dark ? "深色" : "浅色")）==")
            Snapper(outDir: URL(fileURLWithPath: args.out)).run(corpus: args.corpus)
            print("完成")
        }
    }
}
