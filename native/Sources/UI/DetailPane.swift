import SwiftUI

struct DetailPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()
            filterBar
            if state.hasResult {
                table
            } else {
                emptyState
            }
            Divider()
            bottomBar
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - 统计

    private var statsBar: some View {
        HStack(spacing: 9) {
            statCell("扫描文件", state.stats.total, .primary)
            statCell("待改名", state.stats.rename, Theme.accent)
            statCell("无时间戳", state.stats.skip, state.stats.skip > 0 ? .orange : .primary)
            statCell("无需改动", state.stats.same, .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func statCell(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    // MARK: - 筛选

    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("筛选：文件名 / 时间 / 来源…", text: $state.filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .frame(maxWidth: 240)

            Picker("", selection: $state.statusFilter) {
                ForEach(AppState.StatusFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 112)

            Spacer(minLength: 6)

            Text("已选 \(state.selectedRenamable) / \(state.stats.rename) 个待改名")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button("全选") { state.selectAll() }.controlSize(.small)
            Button("清空") { state.selectNone() }.controlSize(.small)
            Button("反选") { state.invertSelection() }.controlSize(.small)

            Button {
                state.exportCSV()
            } label: {
                Label("导出 CSV", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .disabled(!state.hasResult)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 9)
    }

    // MARK: - 表格

    /// 列宽。快照工具也读这里，免得改了界面而验收脚本还按旧宽度渲染。
    enum ColWidth {
        static let timeMin: CGFloat = 176
        static let timeIdeal: CGFloat = 186
        static let newNameIdeal: CGFloat = 188
    }

    private var table: some View {
        Table(state.visiblePlan, selection: $state.selection) {
            TableColumn("") { item in
                ThumbnailCell(item: item)
            }
            .width(30)

            TableColumn("原文件名") { item in
                Text(item.name)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(item.status == .skip ? Color.secondary : Color.primary)
            }
            .width(min: 96, ideal: 140)

            TableColumn("新文件名") { item in
                NewNameCell(item: item)
            }
            .width(min: 120, ideal: ColWidth.newNameIdeal)

            TableColumn("拍摄时间") { item in
                TimeCell(item: item)
            }
            .width(min: ColWidth.timeMin, ideal: ColWidth.timeIdeal)

            TableColumn("来源") { item in
                Text(Theme.shortSource(item.source))
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.sourceColor(item.source))
                    .help(item.source)
            }
            .width(min: 66, ideal: 90)

            TableColumn("大小") { item in
                Text(item.sizeText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 46, ideal: 54)

            TableColumn("状态") { item in
                Text(item.status.text)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .foregroundStyle(statusColor(item.status))
            }
            .width(min: 56, ideal: 66)
        }
        .tableStyle(.inset)
        .contextMenu(forSelectionType: String.self) { paths in
            if let path = paths.first,
               let item = state.plan.first(where: { $0.path == path }) {
                Button("查看详情…") { state.detailItem = item }
                Button("在访达中显示") { state.revealInFinder(path) }
                Divider()
                Button("复制原文件名") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.name, forType: .string)
                }
                if item.status == .ok {
                    Button("复制新文件名") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.newName, forType: .string)
                    }
                }
            }
        } primaryAction: { paths in
            // 双击行 = 查看详情
            if let path = paths.first,
               let item = state.plan.first(where: { $0.path == path }) {
                state.detailItem = item
            }
        }
    }

    private func statusColor(_ s: PlanStatus) -> Color {
        switch s {
        case .ok: return Theme.accent
        case .same: return .secondary
        case .skip: return .orange
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 13) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 46, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text(state.scanning ? "正在读取…" : "还没选文件")
                .font(.system(size: 15, weight: .medium))
            Text(state.scanning
                 ? state.stageText
                 : "左边点「选择文件夹」挑一个目录，或者点「选择文件」直接点名几个文件。\n也可以把文件从访达直接拖进这个窗口。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Text("全部在本机处理 · 不联网 · 只做重命名，不改文件内容")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
            if state.useExifTool && state.exifToolAvailable {
                Text("exiftool \(state.exifToolVersion)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

// MARK: - 单元格

struct ThumbnailCell: View {
    let item: PlanItem

    var body: some View {
        ThumbnailImage(path: item.path, isVideo: Scanner.videoExts.contains(item.ext))
            .frame(width: Theme.thumbSize, height: Theme.thumbSize)
            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
    }
}

struct ThumbnailImage: View {
    let path: String
    let isVideo: Bool
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .overlay(
                        Image(systemName: isVideo ? "film" : "photo")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    )
            }
        }
        .task(id: path) {
            let p = path
            let img = await Task.detached(priority: .utility) {
                Thumbnailer.cached(URL(fileURLWithPath: p), maxPixel: 88)
            }.value
            image = img
        }
    }
}

struct NewNameCell: View {
    let item: PlanItem

    var body: some View {
        HStack(spacing: 4) {
            if item.status == .skip {
                Text("—").foregroundStyle(.tertiary)
            } else {
                Text(item.newName)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(item.status == .same ? Color.secondary : Color.primary)
                if !item.conflict.isEmpty {
                    Text(item.conflict)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(0.13))
                        )
                        .fixedSize()
                }
            }
        }
    }
}

struct TimeCell: View {
    @EnvironmentObject private var state: AppState
    let item: PlanItem

    var body: some View {
        if let t = item.displayTime {
            HStack(spacing: 4) {
                HStack(spacing: 0) {
                    Text(t.stamp)
                        .font(.system(size: 10.5, design: .monospaced))
                    if t.micro != 0 {
                        Text(String(format: ".%03d", t.micro / 1000))
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                if !state.offsetShortLabel.isEmpty,
                   let orig = item.originalTime, orig != t {
                    Text(state.offsetShortLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(0.13))
                        )
                        .fixedSize()
                        .help("原始时间 \(orig.stamp)")
                }
            }
            .lineLimit(1)
        } else {
            Text("无")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
        }
    }
}
