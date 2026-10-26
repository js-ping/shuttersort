import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: Theme.sidebarWidth)
            Divider()
            DetailPane()
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toastText {
                ToastView(text: toast)
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: state.toastText)
        .overlay {
            if dropTargeted { DropOverlay() }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    state.showHelp = true
                } label: {
                    Label("说明书", systemImage: "book")
                }
                .help("使用说明书")

                Button {
                    state.loadHistory()
                } label: {
                    Label("历史", systemImage: "clock.arrow.circlepath")
                }
                .help("改名记录与撤销")

                Button {
                    state.undo(nil)
                } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                }
                .help("撤销上一次改名")
            }
        }
        .onAppear {
            // 从命令行直接跑可执行文件时不会自动到前台，这里补一下
            NSApplication.shared.activate(ignoringOtherApps: true)
            // 核对深浅色用：`--light` / `--dark` 强制指定外观，正常启动不受影响
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--light") {
                NSApp.appearance = NSAppearance(named: .aqua)
            } else if args.contains("--dark") {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
            if state.autoScanOnLaunch {
                state.autoScanOnLaunch = false
                state.startScan()
            }
        }
        .sheet(isPresented: $state.showHelp) { HelpSheet() }
        .sheet(isPresented: $state.showHistory) { HistorySheet() }
        .sheet(isPresented: $state.showConfirm) { ConfirmSheet() }
        .sheet(isPresented: $state.showCalibrate) { CalibrateSheet() }
        .sheet(item: $state.detailItem) { item in DetailSheet(item: item) }
        .alert("提示", isPresented: Binding(
            get: { state.alertText != nil },
            set: { if !$0 { state.alertText = nil } }
        )) {
            Button("知道了", role: .cancel) { state.alertText = nil }
        } message: {
            Text(state.alertText ?? "")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let url {
                    lock.lock(); urls.append(url); lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            state.addDropped(urls)
        }
        return true
    }
}

// MARK: - 提示与覆盖层

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }
}

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("松手，导入这些文件")
                    .font(.system(size: 15, weight: .semibold))
                Text("会在列表里定位并勾选；没被选中的文件不会被改名")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [9, 6]))
                .padding(12)
        )
        .allowsHitTesting(false)
    }
}
