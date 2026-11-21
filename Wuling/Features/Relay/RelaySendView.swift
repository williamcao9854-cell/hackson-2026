import SwiftData
import SwiftUI

/// 传给下一位主人：写几句话 → 盖上我的名章 → 隔空投送。
struct RelaySendView: View {
    @Bindable var spirit: Spirit
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("wuling.mySeal") private var mySeal = ""

    @State private var sealDraft = ""
    @State private var noteToNext = ""
    @State private var shareMemory = true
    @State private var memoryDraft = ""
    @State private var stamped = false
    @State private var capsule: SpiritCapsule?
    @State private var outgoingChapters: [RelayChapter] = []
    @FocusState private var focused: Bool

    private var normalizedSeal: String { RelayLogic.normalizedSeal(sealDraft) }
    private var canStamp: Bool { normalizedSeal.count >= 1 && !stamped }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    preview

                    field(title: "你的名章", note: "1～4 个字，会刻在它身上，一直传下去") {
                        TextField("比如：小林", text: $sealDraft)
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .focused($focused)
                            .disabled(stamped)
                            .onChange(of: sealDraft) { _, value in
                                if value.count > 4 { sealDraft = String(value.prefix(4)) }
                            }
                    }

                    field(title: "写给下一位主人", note: nil) {
                        TextField("比如：它怕潮，下雨天别带它出门。", text: $noteToNext, axis: .vertical)
                            .font(.wlBody)
                            .lineLimit(2...4)
                            .focused($focused)
                            .disabled(stamped)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $shareMemory) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("附上我和它的记忆").font(.wlHeadline)
                                Text("关掉的话，下一位主人只会看到你的名章和留言")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.inkSecondary)
                            }
                        }
                        .tint(.vermilion)
                        .disabled(stamped)

                        if shareMemory {
                            TextField("你和它的一段故事", text: $memoryDraft, axis: .vertical)
                                .font(.wlBody)
                                .lineLimit(2...5)
                                .focused($focused)
                                .disabled(stamped)
                                .padding(14)
                                .background(Color.card, in: RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                                        .strokeBorder(Color.hairline, lineWidth: 1)
                                }
                        }
                    }
                }
                .padding(Metrics.gutter)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { actions }
            .background(PaperBackground())
            .foregroundStyle(.ink)
            .navigationTitle("传给下一位")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .animation(.wlCalm, value: shareMemory)
            .sensoryFeedback(.impact(weight: .heavy), trigger: stamped)
        }
        .onAppear {
            sealDraft = mySeal
            memoryDraft = spirit.memory
        }
    }

    // MARK: - 卡片预览：盖章后，我的名章落在最后

    private var preview: some View {
        HStack(alignment: .top, spacing: 16) {
            SpiritArtView(data: spirit.spiritImageData, contentMode: .fill)
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(spirit.name)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                Text(spirit.epithet)
                    .font(.system(size: 14))
                    .foregroundStyle(.inkSecondary)
                Spacer(minLength: 4)
                CollectorSeals(seals: previewSeals, size: 30)
                    .animation(.spring(response: 0.32, dampingFraction: 0.6), value: stamped)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 112)
    }

    /// 以前的主人 + 我（盖章后才出现）
    private var previewSeals: [String] {
        let previous = spirit.chapters.filter { $0.passedAt != nil }.map(\.ownerSeal)
        return stamped ? previous + [normalizedSeal] : previous
    }

    // MARK: - 底部：盖章 → 投送 → 传好了

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if let capsule {
                ShareLink(item: capsule, preview: SharePreview("物灵 · \(spirit.name)", image: Image(systemName: "seal"))) {
                    Label("隔空投送给 TA", systemImage: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.vermilion)

                Button {
                    spirit.relay(chapters: outgoingChapters, noteToNext: noteToNext.trimmingCharacters(in: .whitespacesAndNewlines))
                    try? modelContext.save()
                    dismiss()
                } label: {
                    Text("已经传出去了")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .tint(.ink)
            } else {
                Button {
                    stamp()
                } label: {
                    Label("盖上名章", systemImage: "seal.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.vermilion)
                .disabled(!canStamp)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 8)
    }

    private func stamp() {
        focused = false
        mySeal = normalizedSeal
        outgoingChapters = RelayLogic.chaptersForSending(
            existing: spirit.chapters,
            mySeal: normalizedSeal,
            myStart: spirit.myStart,
            companionship: spirit.receivedAt == nil ? spirit.companionship : nil,
            memory: shareMemory ? memoryDraft : "",
            noteToNext: noteToNext
        )
        capsule = spirit.makeCapsule(chapters: outgoingChapters)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { stamped = true }
    }

    private func field<Content: View>(title: String, note: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.wlHeadline)
            content()
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.hairline).frame(height: 1)
                }
            if let note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(.inkSecondary)
            }
        }
    }
}
