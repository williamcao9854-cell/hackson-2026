import SwiftUI

/// ⑤ 初见：物灵卡揭晓。插画从朦胧中显现，名字一个字一个字竖着写出来。
struct RevealView: View {
    var model: EncounterModel
    var onFarewell: () -> Void
    var onKeep: () -> Void

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
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            actions
                .opacity(detailsVisible ? 1 : 0)
                .offset(y: detailsVisible ? 0 : 12)
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

    private var actions: some View {
        VStack(spacing: 10) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: onKeep) {
                        Text("留它同住")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.ink)

                    Button(action: onFarewell) {
                        Text("送别它")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.vermilion)
                }
            }
            Text("送别之后，就可以安心放手了。物灵会替你记住它。")
                .font(.system(size: 12))
                .foregroundStyle(.inkSecondary)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 8)
    }

    private func playReveal() async {
        withAnimation(.wlLift) { cardVisible = true }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.easeOut(duration: 1.4)) { artFocused = true }
        try? await Task.sleep(for: .milliseconds(1000))

        let count = model.profile?.name.count ?? 0
        for i in 1...max(count, 1) {
            withAnimation(.smooth(duration: 0.5)) { revealedCharacters = i }
            try? await Task.sleep(for: .milliseconds(380))
        }
        withAnimation(.wlCalm) { detailsVisible = true }
    }
}
