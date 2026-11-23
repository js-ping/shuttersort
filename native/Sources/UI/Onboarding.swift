import SwiftUI

/// 首次启动的三步引导。只在第一次打开时出现，看完不再打扰。
/// 想再看一次：菜单栏「帮助 → 使用引导」。
struct OnboardingView: View {
    var onClose: (_ dontShowAgain: Bool) -> Void

    @State private var dontShow = true

    private let steps: [(String, String, String)] = [
        ("1", "把文件夹拖进窗口", "整个文件夹拖进来最省事；也可以点「选择文件夹」，或只点名几个文件。"),
        ("2", "看右边的预览",           "每个文件改完叫什么，一眼可见。看着不对就别点，这时候什么都还没改。"),
        ("3", "点「开始改名」",         "只有打了勾的那几个会被改。改错了在「历史」里一键撤销，关掉软件也还能撤。"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("三步就完事")
                        .font(.system(size: 17, weight: .semibold))
                    Text("它只改文件名，不动照片内容。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 18)

            ForEach(steps, id: \.0) { n, title, body in
                HStack(alignment: .top, spacing: 12) {
                    Text(n)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.accentColor))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 13, weight: .medium))
                        Text(body).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 14)
            }

            Divider().padding(.vertical, 4)

            HStack {
                Toggle("下次启动不再显示", isOn: $dontShow)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                Spacer()
                Button("开始使用") { onClose(dontShow) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 520)
    }
}
