import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 11) {
                    scopeCard
                    namingCard
                    sourceCard
                    correctionCard
                }
                .padding(12)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 1 选择范围

    private var scopeCard: some View {
        Card(index: 1, title: "选择范围") {
            VStack(alignment: .leading, spacing: 8) {
                // 路径 + 清空挤在同一行：清空自己占一行的样子太浪费纵向空间，
                // 而且一个蓝色链接孤零零摆在那儿，看着像主要动作。
                HStack(spacing: 6) {
                    Text(state.scopeDescription)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(state.folder == nil && state.pickedFiles.isEmpty
                                         ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.055))
                        )
                    if state.folder != nil || !state.pickedFiles.isEmpty {
                        Button("清空") { state.clearScope() }
                            .controlSize(.small)
                            .fixedSize()
                    }
                }

                HStack(spacing: 7) {
                    Button {
                        state.chooseFolder()
                    } label: {
                        Text("选择文件夹").frame(maxWidth: .infinity)
                    }
                    Button {
                        state.chooseFiles()
                    } label: {
                        Text("选择文件").frame(maxWidth: .infinity)
                    }
                }
                .controlSize(.small)

                Toggle("包含子文件夹", isOn: $state.recursive)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .onChange(of: state.recursive) { _, _ in
                        if state.folder != nil { state.startScan() }
                    }
                Hint(text: "递归扫描所有下级目录")

                Toggle("只处理照片和视频", isOn: $state.onlyMedia)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .onChange(of: state.onlyMedia) { _, _ in
                        if state.folder != nil { state.startScan() }
                    }
            }
        }
    }

    // MARK: - 2 命名规则

    private var namingCard: some View {
        Card(index: 2, title: "命名规则") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $state.format) {
                    ForEach(RenameOptions.formatPresets, id: \.self) { f in
                        Text("\(f)  →  \(PyFormat.strftime(f, PyFormat.now))").tag(f)
                    }
                    Text("自定义…").tag("__custom__")
                }
                .labelsHidden()
                .controlSize(.small)
                .onChange(of: state.format) { _, v in
                    state.useCustomFormat = (v == "__custom__")
                    state.optionsChanged()
                }

                if state.useCustomFormat {
                    TextField("例如 %Y年%m月%d日", text: $state.customFormat)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))
                        .controlSize(.small)
                        .onChange(of: state.customFormat) { _, _ in state.optionsChanged() }
                }

                Picker("", selection: $state.pattern) {
                    ForEach(NamePattern.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .onChange(of: state.pattern) { _, _ in state.optionsChanged() }

                HStack(spacing: 8) {
                    labeledField("前缀", text: $state.prefix, width: 74)
                    labeledField("后缀", text: $state.suffix, width: 74)
                }

                Divider().padding(.vertical, 1)

                editSection

                Divider().padding(.vertical, 1)

                Toggle("按日期归档到子文件夹", isOn: $state.archive)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .onChange(of: state.archive) { _, _ in state.optionsChanged() }

                if state.archive {
                    TextField("%Y/%Y-%m", text: $state.archiveFormat)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))
                        .controlSize(.small)
                        .onChange(of: state.archiveFormat) { _, _ in state.optionsChanged() }
                }
            }
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
                .controlSize(.small)
                .frame(width: width)
                .onChange(of: text.wrappedValue) { _, _ in state.optionsChanged() }
        }
    }

    // MARK: - 按位置增删

    /// 拼好的名字 → 按字符序号插 / 删。
    ///
    /// 之所以不做成「在哪段文字前后」那种锚点写法：日期段长度随格式变，
    /// 锚点经常找不到；序号虽然要数，但结果恒等于人眼看到的第 N 个字。
    private var editSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("按位置增删字符").font(.system(size: 11.5))
                Spacer()
                Button {
                    state.addEdit()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.borderless)
                .help("添加一条位置规则")
            }

            if state.edits.isEmpty {
                Hint(text: "想在第几位插一段、或从第几位删几个字时用。负数从末尾数（−1 = 最后一位）。")
            } else {
                ForEach($state.edits) { $edit in
                    editRow($edit)
                }
                HStack(spacing: 3) {
                    Text("预览")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Text(state.editSample)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func editRow(_ edit: Binding<NameEdit>) -> some View {
        let e = edit.wrappedValue
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Toggle("", isOn: edit.enabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("取消勾选可临时停用这条，不用删掉")

                Picker("", selection: edit.kind) {
                    ForEach(NameEdit.Kind.allCases) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .labelsHidden()
                .frame(width: 56)
                .controlSize(.small)

                Text("第").font(.system(size: 10.5)).foregroundStyle(.secondary)
                SignedIntField(value: edit.position) {}
                    .frame(width: 40)
                Text("位").font(.system(size: 10.5)).foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    state.removeEdit(e.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("删除这条规则")
            }

            if e.kind == .insert {
                TextField("要插入的文字", text: edit.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .controlSize(.small)
            } else {
                HStack(spacing: 5) {
                    Text("删").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    SignedIntField(value: edit.count) {}
                        .frame(width: 40)
                    Text("个字符").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .opacity(e.enabled ? 1 : 0.5)
        // 整行只在这里报一次变，内部的数字框和外框都不用各自再报
        .onChange(of: edit.wrappedValue) { _, _ in state.optionsChanged() }
    }

    // MARK: - 3 时间戳来源

    private var sourceCard: some View {
        Card(index: 3, title: "时间戳来源") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $state.fallback) {
                    ForEach(FallbackMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .onChange(of: state.fallback) { _, _ in state.rebuildPlan(immediate: true) }

                // 版本号并进标签里，省一行 —— 右下角那条状态栏本来也一直显示着它
                Toggle("用 exiftool 增强（\(state.exifToolAvailable ? state.exifToolVersion : "未安装")）",
                       isOn: $state.useExifTool)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .disabled(!state.exifToolAvailable)
                    .onChange(of: state.useExifTool) { _, _ in state.startScan() }

                Divider().padding(.vertical, 1)

                Toggle("从文件名解析日期", isOn: $state.parseFilename)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .onChange(of: state.parseFilename) { _, _ in state.startScan() }

                Toggle("读同名 .xmp 旁车", isOn: $state.readXmpSidecar)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .onChange(of: state.readXmpSidecar) { _, _ in state.startScan() }

                Toggle("读 Google Takeout .json", isOn: $state.readTakeoutJSON)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .onChange(of: state.readTakeoutJSON) { _, _ in state.startScan() }
            }
        }
    }

    // MARK: - 4 时间校正

    private var correctionCard: some View {
        Card(index: 4, title: "时间校正", badge: state.offsetLabel) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $state.correctionOn) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("整体调整拍摄时间").font(.system(size: 11.5))
                        Text("相机时区设错、出国忘了调时钟时用")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .onChange(of: state.correctionOn) { _, _ in state.optionsChanged() }

                if state.correctionOn {
                    HStack(spacing: 7) {
                        numberField("天", value: $state.corrDays)
                        numberField("时", value: $state.corrHours)
                        numberField("分", value: $state.corrMinutes)
                    }

                    Button {
                        state.openCalibrate()
                    } label: {
                        Text("不知道差多少？用选中行反推…")
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .disabled(state.selection.isEmpty)

                    Hint(text: "文件名按「原时间 \(state.offsetLabel)」生成。"
                         + "只影响这次改名，不会改动文件里的元数据。")
                }
            }
        }
    }

    private func numberField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
            SignedIntField(value: value) { state.optionsChanged() }
        }
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(spacing: 7) {
            if state.scanning {
                VStack(spacing: 4) {
                    ProgressView(value: state.progress)
                        .progressViewStyle(.linear)
                    Text(state.stageText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    state.requestRename()
                } label: {
                    Text(state.selectedRenamable > 0
                         ? "开始改名（\(state.selectedRenamable) 个）"
                         : "开始改名")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .disabled(state.selectedRenamable == 0)

                Text("原地重命名，不改文件内容 · 每次改名都有撤销记录")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

extension Optional where Wrapped == URL {
    var isNilOrEmpty: Bool { self == nil }
}

/// 可以输负数的整数输入框（天 / 时 / 分）。
///
/// 不用 `TextField(value:format:.number)`：那个在「刚敲下减号」的那一下会把输入吞掉，
/// 想填 −8 小时得靠光标技巧。这里自己拿字符串兜住输入过程：
/// 只有**能完整解析成整数**时才回写绑定值，所以 `-`、`-8`、空串都不会被抢走。
struct SignedIntField: View {
    @Binding var value: Int
    var onChange: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11.5, design: .monospaced))
            .controlSize(.small)
            .multilineTextAlignment(.center)
            .focused($focused)
            .onAppear { text = String(value) }
            .onChange(of: text) { _, new in
                // 只留数字和减号，顺手挡掉粘贴进来的怪字符
                let cleaned = new.filter { $0.isNumber || $0 == "-" }
                if cleaned != new { text = cleaned; return }
                if cleaned.isEmpty {
                    if value != 0 { value = 0; onChange() }
                    return
                }
                // "-" / "-0" 这类中间状态解析不成整数，原样留着别动
                if let n = Int(cleaned), n != value {
                    value = n
                    onChange()
                }
            }
            .onChange(of: value) { _, new in
                // 外部改了值（比如「用选中行反推」回填）时同步文本框
                if Int(text) != new { text = String(new) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = String(value) }
            }
    }
}
