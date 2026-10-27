import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 11) {
                    scopeCard
                    namingCard
                    rulesCard
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

    // MARK: - 3 改名规则

    private var rulesCard: some View {
        Card(index: 3, title: "改名规则",
             badge: state.rules.isEmpty ? "" : "\(state.rules.filter(\.enabled).count) 条") {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 6) {
                    Text(state.rules.isEmpty
                         ? "对拼好的名字做微调：去前缀、插分隔符、统一大小写。"
                         : "从上往下依次执行，前一条的结果是后一条的输入。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    addRuleMenu
                }

                ForEach(Array(state.rules.enumerated()), id: \.element.id) { idx, _ in
                    ruleRow($state.rules[idx], input: state.ruleInputSample(before: idx))
                }

                if !state.rules.isEmpty {
                    previewBlock
                }
            }
        }
    }

    private var addRuleMenu: some View {
        Menu {
            ForEach(NameRule.Kind.allCases) { k in
                Button {
                    state.addRule(k)
                } label: {
                    Text("\(k.rawValue) — \(k.hint)")
                }
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("添加一条改名规则")
    }

    private func ruleRow(_ rule: Binding<NameRule>, input: String) -> some View {
        let r = rule.wrappedValue
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Toggle("", isOn: rule.enabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("取消勾选可临时停用这条，不用删掉")

                Picker("", selection: rule.kind) {
                    ForEach(NameRule.Kind.allCases) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .labelsHidden()
                .frame(width: 72)
                .controlSize(.small)

                Spacer(minLength: 0)

                Button { state.moveRule(r.id, up: true) } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(state.rules.first?.id == r.id)
                .help("上移一位")

                Button { state.moveRule(r.id, up: false) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(state.rules.last?.id == r.id)
                .help("下移一位")

                Button { state.removeRule(r.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("删除这条规则")
            }

            ruleFields(rule)

            // 位置类规则配一条可点的字符标尺 —— 数位置是这套规则最容易出错的环节，
            // 与其让人盯着数字数，不如让他点那个字符
            if r.kind == .delete || (r.kind == .insert && r.anchor == .position) {
                positionRuler(rule, input: input)
            }

            Text(r.summary)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .opacity(r.enabled ? 1 : 0.45)
        // 整条只在这里报一次变，里面的数字框 / 下拉都不用各自再报
        .onChange(of: rule.wrappedValue) { _, _ in state.optionsChanged() }
    }

    /// 每条规则按类型只显示自己用得到的字段 —— 一个「宽结构」撑五种规则，
    /// 全铺出来会有七八行空控件，看着像坏了。
    @ViewBuilder
    private func ruleFields(_ rule: Binding<NameRule>) -> some View {
        let r = rule.wrappedValue
        switch r.kind {
        case .insert:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Picker("", selection: rule.anchor) {
                        ForEach(NameRule.Anchor.allCases) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    .controlSize(.small)

                    if r.anchor == .position {
                        Text("第").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        SignedIntField(value: rule.position) {}
                            .frame(width: 40)
                        Text("位后").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    } else {
                        TextField("那段文字", text: rule.anchorText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .controlSize(.small)
                    }
                    Spacer(minLength: 0)
                }
                TextField("要插入的文字", text: rule.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .controlSize(.small)
            }

        case .delete:
            HStack(spacing: 5) {
                Text("第").font(.system(size: 10.5)).foregroundStyle(.secondary)
                SignedIntField(value: rule.position) {}
                    .frame(width: 40)
                Text("位起").font(.system(size: 10.5)).foregroundStyle(.secondary)

                if r.toEnd {
                    Text("删到底").font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    SignedIntField(value: rule.count) {}
                        .frame(width: 40)
                    Text("个").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }

                Toggle("到末尾", isOn: rule.toEnd)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10.5))
                    .help("勾上就一路删到最后一个字符，上面的数量不参与")

                Spacer(minLength: 0)
            }

        case .replace:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    TextField("要找的文字", text: rule.text)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .controlSize(.small)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    TextField("换成（留空=移除）", text: rule.replacement)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .controlSize(.small)
                }
                Toggle("区分大小写", isOn: rule.caseSensitive)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10.5))
            }

        case .strip:
            HStack(spacing: 5) {
                Text("去掉所有").font(.system(size: 10.5)).foregroundStyle(.secondary)
                Picker("", selection: rule.charset) {
                    ForEach(NameRule.Charset.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                Spacer(minLength: 0)
            }

        case .changeCase:
            HStack(spacing: 5) {
                Picker("", selection: rule.caseStyle) {
                    ForEach(NameRule.CaseStyle.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                Spacer(minLength: 0)
            }
        }
    }

    /// 一条可点的字符标尺：点哪个字符，位置就设成几。
    ///
    /// 显示的是「这条规则执行前的名字」，所以前面若有替换/剥离把长度改短了，
    /// 这里看到的就是改短之后的样子 —— 和规则实际看到的完全一致，不会点着 A 改到 B。
    private func positionRuler(_ rule: Binding<NameRule>, input: String) -> some View {
        let r = rule.wrappedValue
        let chars = Array(input)
        let limit = 26
        let shown = Array(chars.prefix(limit))

        // 当前命中的字符下标（0-based）。插入规则标在插入点左边那个字符上
        let hit: Int? = {
            guard !chars.isEmpty else { return nil }
            if r.kind == .delete {
                let s = r.position > 0
                    ? min(r.position - 1, chars.count)
                    : max(0, chars.count + r.position)
                return s < chars.count ? s : nil
            }
            let p = r.position > 0
                ? min(r.position, chars.count)
                : max(0, chars.count + r.position + 1)
            return p - 1 >= 0 && p - 1 < chars.count ? p - 1 : nil
        }()

        return HStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, ch in
                let tip = "第 \(i + 1) 位：" + Self.rulerGlyph(ch)
                Button {
                    rule.wrappedValue.position = i + 1
                    state.optionsChanged()
                } label: {
                    Text(Self.rulerGlyph(ch))
                        .font(.system(size: 9.5, weight: i == hit ? .semibold : .regular,
                                      design: .monospaced))
                        // 命中时反白 —— 淡紫底上压深字，`_` 这种细笔画根本看不清
                        .foregroundStyle(i == hit ? Color.white : Color.secondary.opacity(0.9))
                        // 格子只比字形略宽：留白了会看着像名字里真有空格
                        .frame(width: 7.5, height: 14)
                        .background(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(i == hit ? Theme.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(tip)
            }
            if chars.count > limit {
                Text("…")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .help("名字超过 \(limit) 个字符，后面几位请在左边的数字框里直接填")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 标尺里那些「看不见的字符」得画成看得见的符号 ——
    /// 否则空格和「这里什么都没有」长得一模一样，数位必然数错。
    private static func rulerGlyph(_ ch: Character) -> String {
        switch ch {
        case " ": return "·"
        case "\t": return "→"
        case "\u{3000}": return "□"
        default: return String(ch)
        }
    }

    /// 规则下方那两行示例：原名 → 规则链跑完的名字
    private var previewBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("原").font(.system(size: 9)).foregroundStyle(.tertiary)
                Text(state.ruleSampleBefore)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 4) {
                Text("新").font(.system(size: 9)).foregroundStyle(.tertiary)
                Text(state.ruleSampleAfter)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    // MARK: - 4 时间戳来源

    private var sourceCard: some View {
        Card(index: 4, title: "时间戳来源") {
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

    // MARK: - 5 时间校正

    private var correctionCard: some View {
        Card(index: 5, title: "时间校正", badge: state.offsetLabel) {
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
