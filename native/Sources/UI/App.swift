import SwiftUI

@main
struct ShutterSortApp: App {
    @StateObject private var state = AppState()

    /// `--open <目录>`：启动后直接扫描这个文件夹，跳过选择面板。
    /// 主要给截图脚本和「从终端打开某个目录」用，平时双击启动不涉及。
    private let launchFolder: URL? = {
        let argv = CommandLine.arguments
        guard let i = argv.firstIndex(of: "--open"), i + 1 < argv.count else { return nil }
        let path = argv[i + 1]
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return URL(fileURLWithPath: path)
    }()

    init() {
        // `--version` 只打印版本号就退出，留给打包脚本和 CI 做冒烟测试用。
        // 不加这个的话，命令行里带参数跑会直接开个窗口挂住。
        if CommandLine.arguments.contains("--version") {
            let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "dev"
            #if arch(arm64)
            let arch = "arm64"
            #elseif arch(x86_64)
            let arch = "x86_64"
            #else
            let arch = "unknown"
            #endif
            print("拍摄时间改名器 \(v)（macOS 原生版 · \(arch)）")
            exit(0)
        }
    }

    var body: some Scene {
        Window("拍摄时间改名器", id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 1040, minHeight: 620)
                .task {
                    if let f = launchFolder, !state.scanning, state.rows.isEmpty {
                        state.openFolder(at: f)
                    }
                }
        }
        .defaultSize(width: 1360, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("选择文件夹…") { state.chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("选择文件…") { state.chooseFiles() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button("导出 CSV…") { state.exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!state.hasResult)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销上一次改名") { state.undo(nil) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("改名记录…") { state.loadHistory() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("使用说明书") { state.showHelp = true }
                    .keyboardShortcut("/", modifiers: .command)
            }
        }
    }
}
