import SwiftData
import SwiftUI

/// 物灵详情：大图、竖排名字、它的故事、灵貌 ⇄ 原貌、分享。
struct SpiritDetailView: View {
    @Bindable var spirit: Spirit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showOriginal = false
    @State private var showingFarewell = false
    @State private var showingRelay = false
    @State private var confirmingDelete = false
    @State private var shareImage: Image?
    @State private var renaming = false
    @State private var nameDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                artwork
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 8)

                info
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 28)

                if !spirit.chapters.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("流转").eyebrow()
                            Spacer()
                            Text("第 \(spirit.chapters.count) 代主人")
                                .font(.wlCaption)
                                .foregroundStyle(.inkSecondary)
                        }
                        RelayTimeline(chapters: spirit.chapters)
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 36)
                }

                if spirit.isReleased {
                    farewellRecord
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 32)
                } else {
                    livingFooter
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 32)
                }
            }
            .padding(.bottom, 48)
        }
        .background(PaperBackground())
        .foregroundStyle(.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let shareImage {
                    ShareLink(item: shareImage, preview: SharePreview(spirit.name, image: shareImage)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("改名", systemImage: "pencil") {
                        nameDraft = spirit.name
                        renaming = true
                    }
                    Button("从图鉴中移除", systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .alert("给它改个名字", isPresented: $renaming) {
            TextField("名字", text: $nameDraft)
            Button("好") {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                spirit.name = trimmed
                try? modelContext.save()
                renderShareImage()
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("移除「\(spirit.name)」？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                modelContext.delete(spirit)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("它的插画和记忆都会从这台手机上删除。")
        }
        .fullScreenCover(isPresented: $showingFarewell) {
            ZStack {
                PaperBackground()
                FarewellView(
                    sticker: spirit.stickerImageData.flatMap(UIImage.init(data:)),
                    spiritImageData: spirit.spiritImageData,
                    spiritName: spirit.name,
                    palette: spirit.palette,
                    suggestion: "谢谢你，陪我\(spirit.companionship.phrase)。"
                ) { note in
                    spirit.release(note: note)
                    try? modelContext.save()
                } onFinish: {
                    showingFarewell = false
                    renderShareImage()
                } onCancel: {
                    showingFarewell = false
                }
            }
            .foregroundStyle(.ink)
        }
        .sheet(isPresented: $showingRelay, onDismiss: renderShareImage) {
            RelaySendView(spirit: spirit)
        }
        .task {
            // 等进入详情的转场动画结束，再渲染分享图，避免卡顿
            try? await Task.sleep(for: .milliseconds(700))
            renderShareImage()
        }
    }

    // MARK: - 插画（灵貌 / 原貌）

    private var artwork: some View {
        ZStack {
            if showOriginal, let data = spirit.stickerImageData, let sticker = UIImage(data: data) {
                StickerView(image: sticker, lifted: true)
                    .padding(56)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                SpiritArtView(data: spirit.spiritImageData)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            VerticalText(text: spirit.name, font: .wlSpiritName(40))
                .foregroundStyle(.inkOnArt)
                .padding(.top, 22)
                .padding(.trailing, 22)
                .opacity(showOriginal ? 0 : 1)
        }
        .overlay(alignment: .bottomLeading) {
            if spirit.stickerImageData != nil {
                Button {
                    withAnimation(.smooth(duration: 0.45)) { showOriginal.toggle() }
                } label: {
                    Label(showOriginal ? "灵貌" : "原貌", systemImage: showOriginal ? "sparkles" : "photo")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.glass)
                .foregroundStyle(.ink)
                .padding(14)
                .accessibilityHint(showOriginal ? "查看物灵插画" : "查看物品原本的样子")
            }
        }
        .sensoryFeedback(.selection, trigger: showOriginal)
    }

    // MARK: - 信息

    private var info: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wuling · \(WLFormat.serial(spirit.serial))").eyebrow()

            Text(spirit.epithet)
                .font(.system(size: 26, weight: .semibold))

            Text(metaItems.filter { !$0.isEmpty }.joined(separator: "　·　"))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(.inkSecondary)

            Text(spirit.personality)
                .font(.wlQuote)
                .lineSpacing(6)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)

            if !spirit.memory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("关于它").font(.wlHeadline)
                    Text(spirit.memory)
                        .font(.wlBody)
                        .lineSpacing(5)
                        .foregroundStyle(.ink.opacity(0.85))
                }
                .padding(.top, 18)
            }

            if spirit.isPlaceholderArt {
                Label("这张是离线水彩剪影", systemImage: "wifi.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(.inkSecondary)
                    .padding(.top, 6)
            }
        }
    }

    /// 自己唤醒的：颜色 · 相伴多久 · 遇见于；从别人那里接过来的：颜色 · 接过于 · 第几代
    private var metaItems: [String] {
        if let received = spirit.receivedAt {
            return [spirit.colorName, "接过于 \(WLFormat.date(received))", "第 \(max(1, spirit.chapters.count)) 代主人"]
        }
        return [spirit.colorName, "相伴\(spirit.companionship.title)", "遇见于 \(WLFormat.date(spirit.createdAt))"]
    }

    // MARK: - 送别记录 / 同住

    private var farewellRecord: some View {
        HStack(alignment: .center, spacing: 18) {
            SealStamp(text: spirit.departureSeal, size: 60)
            VStack(alignment: .leading, spacing: 6) {
                if spirit.isRelayed {
                    Text("写给下一位主人")
                        .font(.system(size: 12))
                        .foregroundStyle(.inkSecondary)
                }
                Text("「\(spirit.farewellNote.isEmpty ? "谢谢你。" : spirit.farewellNote)」")
                    .font(.wlQuote)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = spirit.releasedAt {
                    Text("\(spirit.isRelayed ? "传出" : "送别")于 \(WLFormat.date(date))")
                        .font(.wlCaption)
                        .monospacedDigit()
                        .foregroundStyle(.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
    }

    private var livingFooter: some View {
        VStack(spacing: 12) {
            Text("它还和你住在一起。要把它送给别人，就让物灵和故事一起跟过去；要放手，就为它办一场送别。")
                .font(.system(size: 14))
                .foregroundStyle(.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        showingRelay = true
                    } label: {
                        Text("传给下一位")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.ink)

                    Button {
                        showingFarewell = true
                    } label: {
                        Text("送别它")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.vermilion)
                }
            }
        }
    }

    // MARK: - 分享

    private func renderShareImage() {
        let renderer = ImageRenderer(content: ShareCardView(spirit: spirit).environment(\.colorScheme, .light))
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            shareImage = Image(uiImage: uiImage)
        }
    }
}

#Preview {
    NavigationStack {
        SpiritDetailView(spirit: PreviewData.sample)
    }
    .modelContainer(PreviewData.container)
}
