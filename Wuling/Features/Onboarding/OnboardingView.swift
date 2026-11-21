import SwiftUI

/// 第一次打开时的引导：万物有灵 → 三种去处 → 只在你的手机上。
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("wuling.onboarded") private var onboarded = false
    @State private var page = 0

    var body: some View {
        ZStack {
            AmbientBackdrop(intensity: page == 1 ? 0.9 : 0.7, lanterns: page >= 1 ? 2 : 0, geese: page >= 1 ? 2 : 0)

            TabView(selection: $page) {
                pageOne.tag(0)
                pageTwo.tag(1)
                pageThree.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .foregroundStyle(.ink)
        .animation(.wlCalm, value: page)
    }

    // MARK: - 万物有灵

    private var pageOne: some View {
        VStack(spacing: 36) {
            Spacer()
            HStack(alignment: .top, spacing: 26) {
                VerticalText(text: "其精悉能假托人形", font: .system(size: 18, weight: .regular, design: .serif), spacing: 4, maxPerColumn: 8)
                    .foregroundStyle(.inkSecondary)
                    .padding(.top, 40)
                VerticalText(text: "万物之老者", font: .system(size: 34, weight: .semibold, design: .serif), spacing: 6)
            }
            VStack(spacing: 10) {
                Text("东西被人珍惜久了，就有了灵性。")
                Text("拍下一件你舍不得的旧物，\n唤醒它的物灵。")
                    .foregroundStyle(.inkSecondary)
            }
            .font(.system(size: 16))
            .multilineTextAlignment(.center)
            .lineSpacing(5)
            Text("—— 葛洪《抱朴子》").font(.system(size: 13, design: .serif)).foregroundStyle(.inkSecondary)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - 三种去处

    private var pageTwo: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("唤醒之后，它有三种去处").font(.system(size: 24, weight: .semibold))
            destination(symbol: "figure.stand", title: "同住", seal: "同住",
                        text: "东西还留在身边。它会以立牌的样子，住在你园林的岸边。")
            destination(symbol: "flame", title: "送别", seal: "送别",
                        text: "准备放手了。道一声谢，长按印章，它化作一盏河灯，漂在园林的水上。")
            destination(symbol: "bird", title: "传灵", seal: "传灵",
                        text: "把东西送给别人。物灵带着你们的故事和你的名章一起过去，像鸿雁传书。")
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func destination(symbol: String, title: String, seal: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            SealStamp(text: seal, size: 46, rotation: .degrees(-6), style: title == "同住" ? .yang : .yin)
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol).font(.wlHeadline)
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(.ink.opacity(0.8))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - 隐私

    private var pageThree: some View {
        VStack(spacing: 26) {
            Spacer()
            SealStamp(text: "物灵", size: 72, rotation: .degrees(-6))
            Text("只在你的手机上").font(.system(size: 24, weight: .semibold))
            VStack(alignment: .leading, spacing: 14) {
                Label("抠图、识别、起名，都在手机上完成", systemImage: "lock.shield")
                Label("照片不会上传，画物灵时只发送几句文字描述", systemImage: "photo.badge.checkmark")
                Label("你写下的记忆，只保存在这台手机上", systemImage: "text.book.closed")
            }
            .font(.system(size: 15))
            .padding(18)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Spacer()
            Button {
                onboarded = true
                dismiss()
            } label: {
                Text("走进园林")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.vermilion)
            .padding(.bottom, 56)
        }
        .padding(.horizontal, 28)
    }
}

#Preview {
    OnboardingView()
}
