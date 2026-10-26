import SwiftUI

/// 配色与视觉常量。
///
/// 全程用系统语义色，深浅色自动跟随 —— 原生 app 不该硬编码背景色，
/// 否则用户切到浅色模式就成了一眼假。
enum Theme {

    /// 品牌紫，只用于主按钮等少量强调
    static let accent = Color(red: 0.62, green: 0.44, blue: 0.95)

    static let sidebarWidth: CGFloat = 344
    static let rowHeight: CGFloat = 30
    static let thumbSize: CGFloat = 22

    /// 时间戳来源标签的颜色。同一个来源永远同一个色，方便扫一眼看整批数据的质量分布。
    static func sourceColor(_ source: String) -> Color {
        let s = source.lowercased()
        if s.contains("缺失") { return .secondary }
        if s.contains("文件系统") { return .yellow }
        if s.contains("旁车") { return .purple }
        if s.contains("文件名") { return .orange }
        if s.contains("quicktime") || s.contains("mvhd") || s.contains("mdhd")
            || s.contains("heif") { return .blue }
        if s.contains("exif") || s.contains("xmp") || s.contains("png")
            || s.contains("tiff") { return .green }
        return .teal
    }

    /// 来源标签的短名（表格里列宽有限，长标签要折行很难看）
    static func shortSource(_ source: String) -> String {
        if source == "缺失" { return "缺失" }
        var s = source
        if s.hasPrefix("exiftool·") { s = String(s.dropFirst("exiftool·".count)) }
        s = s.replacingOccurrences(of: "内嵌·", with: "")
        s = s.replacingOccurrences(of: "旁车·", with: "")
        s = s.replacingOccurrences(of: "文件名·", with: "")
        s = s.replacingOccurrences(of: "文件系统·", with: "")
        return s
    }
}

/// 侧栏的卡片容器
struct Card<Content: View>: View {
    let index: Int
    let title: String
    var badge: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("\(index)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    )
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
                if !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.accent.opacity(0.14))
                        )
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

/// 说明性小字
struct Hint: View {
    let text: String
    var warn = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(warn ? Color.orange : Color.secondary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}
