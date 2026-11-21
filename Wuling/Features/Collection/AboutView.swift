import SwiftUI

/// 关于物灵：灵感、隐私、技术。路演时也可以直接打开给评委看。
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 12) {
                        SealStamp(text: "物灵", size: 52, rotation: .degrees(-6))
                        Text("把记忆留下，\n把东西放下。")
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                            .lineSpacing(4)
                    }

                    block(title: "灵感") {
                        Text("日本民间传说，器物被人珍惜久了，就会生出灵魂，叫作「付丧神」。直到今天，日本还保留着「人形供养」「针供养」的习俗：扔掉玩偶和旧针之前，要先为它们办一场感谢的仪式。")
                        Text("整理房间时最难的，往往不是东西本身，而是东西背后的记忆。物灵替你记住它，你就可以安心放手。")
                    }

                    block(title: "传灵") {
                        Text("把旧物送给别人时，物灵和它的故事也可以一起过去。每经过一位主人，物灵身上就多一枚他的名章，就像古画上一代代收藏者盖下的鉴藏印。")
                        row("square.and.arrow.up", "通过隔空投送传递，不经过任何服务器")
                        row("hand.raised", "要不要附上你的那段记忆，由你决定")
                    }

                    block(title: "隐私") {
                        row("lock.shield", "抠图、物品识别、起名，全部在这台手机上完成")
                        row("photo.badge.checkmark", "照片不会上传，生成插画时只发送「物品类别、颜色、陪伴时长」这几项文字")
                        row("text.book.closed", "你写下的记忆只保存在本机")
                    }

                    block(title: "技术") {
                        row("viewfinder", "Vision 主体抠图")
                        row("cpu", "Core ML · MobileNetV2 设备端物品识别")
                        row("apple.intelligence", "Foundation Models 设备端起名（支持 Apple 智能的设备）")
                        row("paintbrush.pointed", "AMD 图像生成 API 绘制物灵")
                        HStack(spacing: 8) {
                            Circle()
                                .fill(SpiritForge.isImageAPIConfigured ? Color.green : Color.inkSecondary)
                                .frame(width: 7, height: 7)
                            Text(SpiritForge.isImageAPIConfigured ? "图像服务已连接" : "图像服务未配置，使用离线水彩剪影")
                                .font(.system(size: 12))
                                .foregroundStyle(.inkSecondary)
                        }
                        .padding(.top, 4)
                    }

                    Text("hackson-2026 · Track 1 · Apple Human-Centered Care")
                        .font(.wlCaption)
                        .foregroundStyle(.inkSecondary)
                }
                .padding(Metrics.gutter)
                .padding(.bottom, 24)
            }
            .background(PaperBackground())
            .foregroundStyle(.ink)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func block<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).eyebrow()
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .font(.wlBody)
            .lineSpacing(5)
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.vermilion)
                .frame(width: 22)
            Text(text)
        }
    }
}

#Preview {
    AboutView()
}
