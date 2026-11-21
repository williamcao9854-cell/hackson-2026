import SwiftData
import SwiftUI

/// 有一个物灵来到了你身边：看看它的来历，盖上你的名章，收下它。
struct ArrivalView: View {
    let capsule: SpiritCapsule
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("wuling.mySeal") private var mySeal = ""

    @State private var sealDraft = ""
    @State private var visible = false
    @State private var received = false
    @State private var isReturning = false
    @FocusState private var focused: Bool

    private var normalizedSeal: String { RelayLogic.normalizedSeal(sealDraft) }
    private var previousSeals: [String] { capsule.chapters.map(\.ownerSeal) }
    private var generation: Int { capsule.chapters.count + 1 }

    var body: some View {
        ZStack {
            AmbientBackdrop(intensity: 0.55, geese: 1)
            GooseFlight(leftToRight: false)
                .frame(height: 220)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 30)

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text(isReturning ? "Homecoming" : "Arrival").eyebrow()
                        Text(isReturning ? "它回来了" : "一个物灵来到了你身边")
                            .font(.system(size: 24, weight: .semibold))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 64)

                    card
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 24)
                        .scaleEffect(visible ? 1 : 0.94)
                        .opacity(visible ? 1 : 0)

                    if let note = RelayLogic.latestNote(in: capsule.chapters) {
                        VStack(spacing: 10) {
                            Text("「\(note.noteToNext)」")
                                .font(.system(size: 20, design: .serif))
                                .multilineTextAlignment(.center)
                                .lineSpacing(5)
                            Text("—— \(note.ownerSeal)")
                                .font(.system(size: 14))
                                .foregroundStyle(.inkSecondary)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 32)
                        .opacity(visible ? 1 : 0)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("流转").eyebrow()
                        RelayTimeline(chapters: capsule.chapters)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 40)
                    .padding(.bottom, 32)
                    .opacity(visible ? 1 : 0)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { bottom }
        }
        .overlay(alignment: .topLeading) {
            if !received {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(.ink)
                .padding(.leading, Metrics.gutter)
                .padding(.top, 8)
                .accessibilityLabel("暂不收下")
            }
        }
        .foregroundStyle(.ink)
        .sensoryFeedback(.impact(weight: .heavy), trigger: received)
        .onAppear {
            sealDraft = mySeal
            isReturning = RelayInbox.existing(lineage: capsule.lineageID, in: modelContext) != nil
            withAnimation(.wlLift.delay(0.15)) { visible = true }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.card
                .aspectRatio(1, contentMode: .fit)
                .overlay { SpiritArtView(data: capsule.spiritImage, contentMode: .fill) }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    VerticalText(text: capsule.name, font: .wlSpiritName(36))
                        .foregroundStyle(.inkOnArt)
                        .padding(.top, 20)
                        .padding(.trailing, 22)
                }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wuling · 第 \(generation) 代主人").eyebrow()
                    Text(capsule.epithet)
                        .font(.system(size: 20, weight: .semibold))
                    Text(capsule.personality)
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.ink.opacity(0.8))
                        .lineLimit(3)
                }
                Spacer(minLength: 12)
                CollectorSeals(seals: received ? previousSeals + [normalizedSeal] : previousSeals, size: 30, limit: 3)
                    .animation(.spring(response: 0.32, dampingFraction: 0.6), value: received)
            }
            .padding(20)
        }
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 24, y: 14)
    }

    @ViewBuilder
    private var bottom: some View {
        VStack(spacing: 12) {
            if received {
                Button {
                    dismiss()
                } label: {
                    Text("收入图鉴")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.vermilion)
            } else {
                HStack(spacing: 12) {
                    TextField("你的名章", text: $sealDraft)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .focused($focused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.card, in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.hairline, lineWidth: 1) }
                        .frame(maxWidth: 150)

                    Button {
                        receive()
                    } label: {
                        Text("盖章，收下它")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.vermilion)
                    .disabled(normalizedSeal.isEmpty)
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 8)
    }

    private func receive() {
        focused = false
        mySeal = normalizedSeal
        RelayInbox.receive(capsule, mySeal: normalizedSeal, in: modelContext)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { received = true }
    }
}
