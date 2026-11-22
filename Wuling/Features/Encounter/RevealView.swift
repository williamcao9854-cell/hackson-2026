import SwiftUI
import TipKit

/// ⑤ 初见：物灵卡揭晓。插画从朦胧中显现，名字一个字一个字竖着写出来。
struct RevealView: View {
    var model: EncounterModel
    var onFarewell: () -> Void
    var onKeep: () -> Void
    var onRelay: () -> Void
    private let renameTip = RenameTip()

    @State private var cardVisible = false
    @State private var artFocused = false
    @State private var revealedCharacters = 0
    @State private var detailsVisible = false
    @State private var renaming = false
    @State private var nameDraft = ""

    var body: some View {
        let profile = model.profile

        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("初见").eyebrow()
                    Text("它醒了")
                        .font(.system(size: 26, weight: .semibold))
                }
                .padding(.top, 64)
                .padding(.bottom, 24)

                card(profile: profile)
                    .padding(.horizontal, Metrics.gutter)
                    .scaleEffect(cardVisible ? 1 : 0.94)
                    .opacity(cardVisible ? 1 : 0)

                if let notice = model.notice {
                    Label(notice, systemImage: "wifi.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(.inkSecondary)
                        .padding(.top, 14)
                        .opacity(detailsVisible ? 1 : 0)
                }

                actions
                    .padding(.top, 28)
                    .opacity(detailsVisible ? 1 : 0)
                    .offset(y: detailsVisible ? 0 : 12)
            }
            .padding(.bottom, 32)
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: revealedCharacters)
        .alert("给它改个名字", isPresented: $renaming) {
            TextField("名字", text: $nameDraft)
            Button("好") {
                model.rename(nameDraft)
                revealedCharacters = Int.max
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("名字多长都可以，太长时会分成几列竖排。")
        }
        .task { await playReveal() }
    }

    private func card(profile: SpiritProfile?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SpiritArtView(data: model.spiritImageData)
                .aspectRatio(1, contentMode: .fit)
                .blur(radius: artFocused ? 0 : 18)
                .saturation(artFocused ? 1 : 0.3)
                .overlay(alignment: .topTrailing) {
                    VerticalText(text: profile?.name ?? "", font: .wlSpiritName(38), revealed: revealedCharacters)
                        .foregroundStyle(.inkOnArt)
                        .padding(.top, 20)
                        .padding(.trailing, 22)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard detailsVisible else { return }
                            nameDraft = profile?.name ?? ""
                            renaming = true
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("轻点可以改名")
                        .popoverTip(renameTip)
                }

            VStack(alignment: .leading, spacing: 10) {
                Text("Wuling · \(model.companionship.spiritAge)").eyebrow()
                Text(profile?.epithet ?? "")
                    .font(.system(size: 22, weight: .semibold))
                Text(profile?.personality ?? "")
                    .font(.wlQuote)
                    .lineSpacing(5)
                    .foregroundStyle(.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Label("轻点名字可以改名", systemImage: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(.inkSecondary)
                    .padding(.top, 2)
            }
            .padding(22)
            .opacity(detailsVisible ? 1 : 0)
        }
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 24, y: 14)
    }

    /// 三种去处，每一种都说清楚意味着什么
    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("它接下来去哪里？").font(.wlHeadline)
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    choice(seal: "同住", symbol: "figure.stand", title: "留它同住",
                           detail: "东西还留在身边，它会住在你园林的岸边", prominent: false, action: onKeep)
                    choice(seal: "送别", symbol: "flame", title: "送别它",
                           detail: "准备放手了。道一声谢，它化作一盏河灯", prominent: true, action: onFarewell)
                    choice(seal: "传灵", symbol: "bird", title: "传给别人",
                           detail: "把东西送人时，物灵带着故事一起过去", prominent: false, action: onRelay)
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private func choice(seal: String, symbol: String, title: String, detail: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SealStamp(text: seal, size: 38, rotation: .degrees(-6), style: prominent ? .yin : .yang)
                VStack(alignment: .leading, spacing: 3) {
                    Label(title, systemImage: symbol)
                        .font(.system(size: 16, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 13))
                        .opacity(0.75)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.5)
            }
            .foregroundStyle(.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(choiceGlass(prominent: prominent), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func choiceGlass(prominent: Bool) -> Glass {
        if prominent {
            return Glass.regular.tint(Color.vermilion.opacity(0.18)).interactive()
        }
        return Glass.regular.interactive()
    }

    private func playReveal() async {
        RitualSound.prepare()
        withAnimation(.wlLift) { cardVisible = true }
        try? await Task.sleep(for: .milliseconds(200))
        // 插画从朦胧中显现的同时，轻轻响一串风铃
        RitualSound.play(.awaken)
        withAnimation(.easeOut(duration: 1.4)) { artFocused = true }
        try? await Task.sleep(for: .milliseconds(1000))

        let count = model.profile?.name.count ?? 0
        for i in 1...max(count, 1) {
            withAnimation(.smooth(duration: 0.5)) { revealedCharacters = i }
            try? await Task.sleep(for: .milliseconds(380))
        }
        withAnimation(.wlCalm) { detailsVisible = true }
        try? await Task.sleep(for: .milliseconds(600))
        RenameTip.isReady = true
    }
}
