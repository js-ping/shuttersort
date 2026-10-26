import SwiftUI

// MARK: - 详情

struct DetailSheet: View {
    @EnvironmentObject private var state: AppState
    let item: PlanItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ThumbnailImage(path: item.path, isVideo: Scanner.videoExts.contains(item.ext))
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.status != .skip {
                        Text(item.newName)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(item.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("时间") {
                        if let orig = item.originalTime {
                            if let shifted = item.shiftedTime, shifted != orig {
                                row("原始时间", orig.stampWithMicroIfAny, mono: true)
                                row("校正后", shifted.stampWithMicroIfAny, mono: true,
                                    accent: true, note: state.offsetLabel)
                            } else {
                                row("拍摄时间", orig.stampWithMicroIfAny, mono: true)
                            }
                        } else {
                            row("拍摄时间", "无（元数据里没有可用时间）", mono: false)
                        }
                        row("来源", item.source)
                        if !item.note.isEmpty {
                            row("说明", item.note, mono: false, wrap: true)
                        }
                        if let d = item.duration, d > 0 {
                            row("时长", String(format: "%.1f 秒", d), mono: true)
                        }
                        row("大小", item.sizeText, mono: true)
                    }

                    if !item.exif.isEmpty {
                        section("原始元数据") {
                            ForEach(item.exif.keys.sorted(), id: \.self) { key in
                                if let v = item.exif[key], !v.isEmpty, v.count < 220 {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(key)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 130, alignment: .leading)
                                        Text(v)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button("在访达中显示") {
                    state.revealInFinder(item.path)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .frame(width: 620, height: 540)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 5) { content() }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false,
                     accent: Bool = false, note: String = "", wrap: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: mono ? .monospaced : .default))
                .foregroundStyle(accent ? Theme.accent : Color.primary)
                .textSelection(.enabled)
                .lineLimit(wrap ? nil : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - 确认

struct ConfirmSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private var todo: [PlanItem] {
        state.plan.filter { $0.status == .ok && state.selection.contains($0.path) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.accent)
                Text("确认改名 \(todo.count) 个文件")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    paramGrid
                    if state.offsetSeconds != 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                            Text("时间校正 \(state.offsetLabel)：文件名按校正后的时间生成，"
                                 + "文件里的元数据不会改动。")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange.opacity(0.09))
                        )
                    }

                    Text("前几个样例")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(todo.prefix(6)) { it in
                            HStack(spacing: 6) {
                                Text(it.name)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                                Text(it.newName)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        if todo.count > 6 {
                            Text("…还有 \(todo.count - 6) 个")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )

                    Text("改名是原地重命名，不复制、不动画质。每次都会写一份撤销记录，"
                         + "重启之后依然能一键还原。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("确认改名") {
                    state.performRename()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .frame(width: 540, height: 460)
    }

    private var paramGrid: some View {
        VStack(alignment: .leading, spacing: 5) {
            kv("日期格式", state.useCustomFormat && !state.customFormat.isEmpty
               ? state.customFormat : state.format, mono: true)
            kv("命名方式", state.pattern.rawValue)
            kv("前缀 / 后缀", "\(state.prefix.isEmpty ? "（空）" : state.prefix) / "
               + "\(state.suffix.isEmpty ? "（空）" : state.suffix)", mono: true)
            if state.archive {
                kv("归档", state.archiveFormat, mono: true)
            }
            kv("范围", todo.first.map { $0.dir } ?? "", mono: false)
            if state.stats.same > 0 {
                kv("无需改动", "\(state.stats.same) 个（已经是对的，不会被再改一次）")
            }
            if state.stats.skip > 0 {
                kv("跳过", "\(state.stats.skip) 个（没有时间戳）")
            }
        }
    }

    private func kv(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(k)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(v)
                .font(.system(size: 11, design: mono ? .monospaced : .default))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - 历史

struct HistorySheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("改名记录")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(state.history.count) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            if state.history.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                    Text("还没有改名记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(state.history) { entry in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.time)
                                .font(.system(size: 12, design: .monospaced))
                            Text(entry.folder.isEmpty ? "—" : entry.folder)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text("\(entry.count) 个")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("还原") {
                            state.undo(entry.file)
                            dismiss()
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Text("还原是倒序执行的，遇到名字被占用会跳过并告诉你。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .frame(width: 580, height: 440)
    }
}

// MARK: - 反推偏移

struct CalibrateSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    // 用六个数字框而不是 DatePicker：DatePicker 跟随系统区域格式，
    // 在这台机器上显示成「3/ 4/2022 上午 5:06」，跟界面里到处用的
    // YYYY-MM-DD HH:MM:SS 两套写法混在一起，还容易把 3/4 误读成 4 月 3 日。
    @State private var year = 0
    @State private var month = 1
    @State private var day = 1
    @State private var hour = 0
    @State private var minute = 0
    @State private var second = 0
    @State private var prepared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.accent)
                Text("按真实拍摄时间反推偏移")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 13) {
                if let item = state.calibrateItem {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("选中的文件")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Text(item.name)
                            .font(.system(size: 12, design: .monospaced))
                        Text("现在识别为 \(item.originalTime?.stampWithMicroIfAny ?? "无时间戳")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.045))
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("它的真实拍摄时间是什么")
                        .font(.system(size: 11, weight: .medium))
                    HStack(alignment: .bottom, spacing: 6) {
                        numField("年", $year, width: 62)
                        numField("月", $month, width: 42)
                        numField("日", $day, width: 42)
                        Spacer().frame(width: 8)
                        numField("时", $hour, width: 42)
                        numField("分", $minute, width: 42)
                        numField("秒", $second, width: 42)
                        Spacer(minLength: 0)
                    }
                    if !valid, let why = invalidReason {
                        Text(why)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                    }
                }

                Text("填的是这张照片真正拍下的时刻 —— 比如你知道那顿饭是 19:30 吃的，"
                     + "而文件说是 11:30，程序就会算出 +8 小时的偏移，整批一起平移。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)

            Spacer(minLength: 0)

            Divider()

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("算出来并用上") {
                    apply()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!valid)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .frame(width: 480, height: 380)
        .onAppear(perform: prepare)
    }

    private func numField(_ label: String, _ value: Binding<Int>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            // 用 SignedIntField 而不是 TextField(value:format:)：数字格式会给
            // 四位数加千位分隔符，年份会变成「2,022」
            SignedIntField(value: value) {}
                .frame(width: width)
        }
    }

    private func prepare() {
        guard !prepared, let t = state.calibrateItem?.originalTime else { return }
        prepared = true
        year = t.year; month = t.month; day = t.day
        hour = t.hour; minute = t.minute; second = t.second
    }

    /// 时间合不合法（2 月 30 日这类要挡掉，不能把错的偏移算进去）
    private var invalidReason: String? {
        if year < 1900 || year > 2200 { return "年份看起来不对（\(year)）" }
        if month < 1 || month > 12 { return "月份要在 1–12 之间" }
        if day < 1 || day > 31 { return "日要在 1–31 之间" }
        if hour < 0 || hour > 23 { return "小时要在 0–23 之间" }
        if minute < 0 || minute > 59 { return "分钟要在 0–59 之间" }
        if second < 0 || second > 59 { return "秒要在 0–59 之间" }
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        if WallTime(components: c)?.isPlausible != true {
            return "这个日期不存在（\(month) 月没有 \(day) 号）"
        }
        return nil
    }

    private var valid: Bool { invalidReason == nil }

    private func apply() {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        guard let t = WallTime(components: c), t.isPlausible else { return }
        state.applyCalibration(trueTime: t)
    }
}
