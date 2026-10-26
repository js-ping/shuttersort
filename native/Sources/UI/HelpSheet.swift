import SwiftUI

/// 使用说明书。
///
/// 内容与 README、以及 Python 版的帮助页保持一致 —— 三处只改一处是最容易出岔子的地方，
/// 所以这里的措辞直接照搬那两份，别自己另写一套说法。
struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("使用说明书")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    quickStart
                    scopeSection
                    sourceSection
                    namingSection
                    burstSection
                    correctionSection
                    safetySection
                    faqSection
                }
                .padding(20)
            }

            Divider()

            HStack {
                Text("原生应用 · 不联网 · 全部在本机处理")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
        }
        .frame(width: 660, height: 620)
    }

    // MARK: - 各节

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            h("拍摄时间改名器是干什么的")
            p("iPhone 拍的照片和视频，导出到电脑后名字永远是一串流水号 —— IMG_8734.HEIC、IMG_8734.MOV、"
              + "IMG_8741.HEIC。名字里没有时间，几百张堆在一起就是一团乱麻。")
            p("它把文件名换成**真实拍摄时间**（读的是文件内嵌的 EXIF / 视频容器元数据），"
              + "让整个文件夹自动按时间排序，跟手机相册里看到的一致。")
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 7) {
            h("30 秒上手")
            box("① 左边点「选择文件夹」挑一个目录，或者点「选择文件」直接点名几个文件"
                + "（也可以把文件从访达拖进窗口）→　② 右边出现预览（此时文件还没被改）"
                + "→　③ 点「开始改名」→　④ 确认。")
            box("第一次用？建议先把要整理的文件夹复制一份副本出来试手 —— 确认预览结果符合预期了，"
                + "再去动原件。改坏了也无所谓，副本删掉重来即可。", warn: true)
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            h("处理范围：整批，还是只挑几个")
            kv("选择文件夹", "扫整个目录。勾上「包含子文件夹」连里面的子目录一起扫；"
               + "相册里想只处理某一年，就取消勾选、直接选那一年的目录。")
            kv("选择文件", "不扫目录，只处理你点名的这几个文件。可以反复点、多次追加，"
               + "也能跨文件夹混着选。选完不会管目录里其它文件。")
            kv("直接拖拽", "把文件从访达拖到窗口即可加入。已经选过文件时，拖进来的是追加；"
               + "如果当前是文件夹模式、且拖进来的文件本来就在这个文件夹里，"
               + "则退化为「把这几行选中」，不会打乱范围。")
            box("文件模式下路径框会清空，取而代之的是「已选 N 个文件」的提示，"
                + "右边有「清空」按钮，点一下回到空状态重新选。", warn: false)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            h("时间是从哪儿来的")
            p("程序按固定优先级依次尝试，第一个成功的就是结果。表格里那个彩色标签就是告诉你用了哪一层：")
            kv("exiftool·…", "系统 exiftool 读出来的标准元数据（装了就用，覆盖度最高）")
            kv("内嵌·EXIF", "照片内嵌的 EXIF 拍摄时间，最准确")
            kv("内嵌·mvhd / mdhd", "视频容器自带的创建时间")
            kv("内嵌·XMP", "Adobe / 修图软件写入的 XMP 时间")
            kv("内嵌·PNG tIME", "PNG 图片内的时间块")
            kv("内嵌·HEIF Exif", "HEIC 照片里藏在 iloc 指向的 Exif item 中的时间")
            kv("旁车 JSON / XMP", "Google Takeout 导出时附带的 .json，或同名 .xmp")
            kv("文件名 …", "从文件名里解析，如 DJI_20251108_164116_0042")
            kv("文件系统 …", "文件本身的创建/修改时间（需要你手动开启兜底）")
            box("微信、QQ、WhatsApp 转发过的图片视频，元数据常被剥掉。这时要么靠文件名，"
                + "要么开「文件时间兜底」—— 但兜底拿到的是接收时间，不一定是拍摄时间，自己判断。",
                warn: true)
        }
    }

    private var namingSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            h("命名规则怎么填")
            kv("日期格式", "%Y%m%d_%H%M%S → 20240506_153008，下拉里没想要的可以选「自定义」")
            kv("命名方式", "决定日期和原文件名怎么拼：仅日期 / 日期_原名 / 原名_日期 / 仅原名")
            kv("前缀 / 后缀", "默认前缀 IMG_，所以结果是 IMG_20240506_153008.jpg；"
               + "改成 旅行_ 之类可方便按事件分组")
            kv("按日期归档", "勾上后会移动到 2024/2024-05 这类子文件夹里")
            box("冲突处理：目标名已存在时自动加 _1、_2 后缀；冲突检测会排除「文件自身」"
                + "和「本轮即将腾出的旧名」，所以重复执行结果稳定 —— "
                + "已经改好的文件再次扫描时会显示「无需改动」，不会被再改一次。")
        }
    }

    private var burstSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            h("连拍为什么不会乱")
            p("连拍一秒能拍好几张，全都落在同一秒里。程序会读 EXIF 的 SubSecTimeOriginal（亚秒部分），"
              + "同一秒内按亚秒先后排 —— 所以谁拿 _1 谁拿 _2 跟快门顺序一致，换台机器重扫也不会对调。"
              + "表格里的时间会带 3 位小字显示亚秒。")
            box("部分安卓机不写亚秒，这时用文件修改时间兜底，再不行用文件名兜底 —— "
                + "三级排序，结果始终稳定，不会出现「扫两次编号不一样」的情况。")
        }
    }

    private var correctionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            h("时间校正怎么用")
            p("相机时区设错、出国忘了调时钟、拷来一批时间全错的老照片 —— 勾上左栏「4 时间校正」，"
              + "填天 / 时 / 分 三个框（负数就是往前拨），文件名就按校正后的时间生成。")
            kv("正数 / 负数", "正数往后拨，负数往前拨。填 0 天 8 时 0 分 就是整体加 8 小时")
            kv("反推差多少", "不确定差多少时，选中一行 → 点「不知道差多少？用选中行反推…」"
               + "→ 填这张照片真实的拍摄时间 → 偏移量自动算好填回去")
            kv("怎么看效果", "表格里校正过的行带橙色偏移标签（如 +8h），鼠标悬停可看原始时间；"
               + "「新文件名」一列也是校正后的结果")
            box("校正只影响生成的文件名，绝不改写文件里的 EXIF。原值始终保留，"
                + "随时把偏移改回 0 重来一次，结果就回去了。", warn: true)
        }
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            h("安全吗")
            bullet("改名是原地重命名，不复制、不压缩、不动画质")
            bullet("同名冲突自动加 _1 _2，不会覆盖任何文件")
            bullet("每次改名自动生成撤销记录，工具栏「撤销」可一键还原（跨会话有效）")
            bullet("完全在本机处理，不联网、不上传任何数据")
            bullet("正式动手前先用「导出 CSV」存档一份原始文件名，是最保险的做法")
        }
    }

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            h("常见问题")
            qa("为什么有些文件显示「无时间戳」？",
               "这类文件的元数据被处理掉了（聊天软件转发、截图工具、在线编辑器），"
               + "可以在「时间戳来源」里开文件时间兜底，或直接跳过它们。")
            qa("时间差了几小时？",
               "相机时区设置错误留下的历史遗留问题，EXIF 里的时间本身就没有时区。"
               + "本工具优先使用带时区的时间源（内嵌 creationdate / 带 OffsetTimeOriginal 的 EXIF），"
               + "会自动换算成本机时间。如果差的是固定偏移（比如每次都差 8 小时），"
               + "直接用左栏「时间校正」整体平移即可 —— 只改文件名，不动元数据。")
            qa("视频时间整整早 / 晚了一个时区？",
               "视频容器里的创建时间是按 UTC 存的（1904 纪元秒数），需要换算回本地时间才准。"
               + "这一条两个版本都已经处理好了；判断方法：看「来源」，"
               + "写着 内嵌·mvhd 创建时间 的一直是对的。")
            qa("会影响视频播放吗？", "不会。只是改文件名，文件内容一个字节都没动。")
        }
    }

    // MARK: - 排版小工具

    private func h(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .padding(.top, 2)
    }

    private func p(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func box(_ text: String, warn: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(warn ? Color.orange : Color.secondary)
            .lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(warn ? Color.orange.opacity(0.09) : Color.primary.opacity(0.04))
            )
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(k)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 118, alignment: .leading)
            Text(v)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·").font(.system(size: 12, weight: .bold)).foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func qa(_ q: String, _ a: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(q).font(.system(size: 11.5, weight: .medium))
            Text(a)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
