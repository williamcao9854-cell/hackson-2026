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
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var sent = false
    @State private var shareError: String?
    @FocusState private var focused: Bool

    private var normalizedSeal: String { RelayLogic.normalizedSeal(sealDraft) }
    private var canStamp: Bool { normalizedSeal.count >= 1 && !stamped }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    preview

                    field(title: "你的名章", note: "会刻在它身上，一直传下去") {
                        TextField("比如：小林", text: $sealDraft)
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .focused($focused)
                            .disabled(stamped)
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
            .sensoryFeedback(.success, trigger: sent)
            .sheet(isPresented: $showingShare) {
                if let shareURL {
                    ActivitySheet(items: [shareURL]) { completed in
                        showingShare = false
                        if completed { markRelayed() }
                    }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
                }
            }
            .alert("没能打包这个物灵", isPresented: Binding(
                get: { shareError != nil },
                set: { if !$0 { shareError = nil } }
            )) {
                Button("好") { shareError = nil }
            } message: {
                Text(shareError ?? "")
            }
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
            if sent {
                Label("已传出。愿它在新主人那里也被好好珍惜。", systemImage: "checkmark.seal")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.vermilion)
                    .padding(.vertical, 12)
            } else if let capsule {
                Button {
                    share(capsule)
                } label: {
                    Label("传给下一位", systemImage: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.vermilion)

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.wlCalm) {
                            stamped = false
                            self.capsule = nil
                        }
                    } label: {
                        Text("重新填写")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.ink)

                    Button {
                        markRelayed()
                    } label: {
                        Text("已经交给 TA 了")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.ink)
                }
                Text("隔空投送、微信、信息都可以，对方用物灵打开就能收下")
                    .font(.system(size: 12))
                    .foregroundStyle(.inkSecondary)
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
        capsule = spirit.makeCapsule(chapters: outgoingChapters).compressedForTransfer()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { stamped = true }
    }

    private func share(_ capsule: SpiritCapsule) {
        do {
            shareURL = try capsule.writeTemporaryFile()
            showingShare = true
        } catch {
            shareError = error.localizedDescription
        }
    }

    /// 发送成功（或用户确认已经交出去）后：标记"已传出"，停一下让人看到结果，再关闭
    private func markRelayed() {
        guard !sent else { return }
        spirit.relay(chapters: outgoingChapters, noteToNext: noteToNext.trimmingCharacters(in: .whitespacesAndNewlines))
        try? modelContext.save()
        withAnimation(.wlCalm) { sent = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            dismiss()
        }
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
