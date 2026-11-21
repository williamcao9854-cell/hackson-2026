import SwiftData
import SwiftUI
import TipKit

/// 首页：物灵图鉴。
struct CollectionView: View {
    @Query(sort: \Spirit.createdAt, order: .reverse) private var spirits: [Spirit]
    @State private var filter: Filter = .all
    @State private var showingEncounter = false
    @State private var showingAbout = false
    @State private var incoming: IncomingSpirit?
    @State private var incomingError: String?
    @State private var showingOnboarding = false
    @State private var showingReceive = false
    @AppStorage("wuling.onboarded") private var onboarded = false
    private let gardenTip = GardenTip()
    @Namespace private var zoom

    /// 隔空投送或从文件 App 打开的物灵
    struct IncomingSpirit: Identifiable {
        let id = UUID()
        let capsule: SpiritCapsule
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case living = "同住"
        case released = "已送别"
        case relayed = "已传出"
        var id: String { rawValue }
    }

    private var filtered: [Spirit] {
        switch filter {
        case .all: spirits
        case .living: spirits.filter { !$0.isReleased }
        case .released: spirits.filter { $0.isReleased && !$0.isRelayed }
        case .relayed: spirits.filter(\.isRelayed)
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        GardenHero(topInset: proxy.safeAreaInsets.top,
                                   living: spirits.filter { !$0.isReleased },
                                   lanterns: releasedCount, geese: relayedCount)
                            .frame(height: max(520, proxy.size.height * 0.74))

                        legendRow
                            .padding(.horizontal, Metrics.gutter)

                        if !spirits.isEmpty {
                            TipView(gardenTip)
                                .tipBackground(Color.card)
                                .padding(.horizontal, Metrics.gutter)
                                .padding(.top, 14)
                        }

                        if spirits.isEmpty {
                            EmptyCollectionView()
                                .padding(.top, 12)
                        } else {
                            Picker("筛选", selection: $filter) {
                                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, Metrics.gutter)
                            .padding(.top, 24)

                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(filtered) { spirit in
                                    NavigationLink {
                                        SpiritDetailView(spirit: spirit)
                                            .navigationTransition(.zoom(sourceID: spirit.id, in: zoom))
                                    } label: {
                                        SpiritCardView(spirit: spirit)
                                            .matchedTransitionSource(id: spirit.id, in: zoom)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Metrics.gutter)
                            .padding(.top, 20)
                            .animation(.smooth, value: filter)
                        }
                    }
                    .padding(.bottom, 120)
                }
                .ignoresSafeArea(edges: .top)
            }
            .background(PaperBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAbout = true
                    } label: {
                        Image(systemName: "info")
                    }
                    .accessibilityLabel("关于物灵")
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .fullScreenCover(isPresented: $showingEncounter) {
                EncounterView()
            }
            .fullScreenCover(isPresented: $showingReceive) {
                ReceiveView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView()
            }
            .onAppear { if !onboarded { showingOnboarding = true } }
            .onChange(of: onboarded) { _, done in if !done { showingOnboarding = true } }
            .fullScreenCover(item: $incoming) { item in
                ArrivalView(capsule: item.capsule)
            }
            .alert("没能收下这个物灵", isPresented: Binding(
                get: { incomingError != nil },
                set: { if !$0 { incomingError = nil } }
            )) {
                Button("好") { incomingError = nil }
            } message: {
                Text(incomingError ?? "")
            }
            .onOpenURL { url in
                guard url.pathExtension.lowercased() == SpiritCapsule.fileExtension else { return }
                do {
                    let capsule = try SpiritCapsule.read(from: url)
                    if showingEncounter || showingAbout || showingOnboarding || showingReceive {
                        // 先关掉正在打开的页面，等它退场后再弹出，否则 SwiftUI 会丢掉这次弹窗
                        showingEncounter = false
                        showingAbout = false
                        showingOnboarding = false
                        showingReceive = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(700))
                            incoming = IncomingSpirit(capsule: capsule)
                        }
                    } else {
                        incoming = IncomingSpirit(capsule: capsule)
                    }
                } catch {
                    incomingError = error.localizedDescription
                }
            }
        }
        .foregroundStyle(.ink)
    }

    private var livingCount: Int { spirits.filter { !$0.isReleased }.count }
    private var relayedCount: Int { spirits.filter(\.isRelayed).count }
    private var releasedCount: Int { spirits.count - livingCount - relayedCount }

    /// 园林下方的图例：岸边 = 同住，河灯 = 送别，鸿雁 = 传出。点一下筛选下面的图鉴。
    @ViewBuilder
    private var legendRow: some View {
        if !spirits.isEmpty {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    legendChip(symbol: "figure.stand", text: "岸边 · 同住", count: livingCount, filter: .living)
                    legendChip(symbol: "flame", text: "河灯 · 送别", count: releasedCount, filter: .released)
                    legendChip(symbol: "bird", text: "鸿雁 · 传出", count: relayedCount, filter: .relayed)
                }
            }
        }
    }

    private func legendChip(symbol: String, text: String, count: Int, filter target: Filter) -> some View {
        Button {
            withAnimation(.smooth) { filter = filter == target ? .all : target }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(text).font(.system(size: 12, weight: .medium))
                Text("\(count)").font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(filter == target ? Color.vermilion : Color.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel("\(text)，\(count) 个")
    }

    /// 底部：遇见（拍一件旧物）· 接灵（收下别人传来的物灵）
    private var bottomBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    showingEncounter = true
                } label: {
                    Label("遇见", systemImage: "camera.viewfinder")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.vermilion)
                .accessibilityHint("拍下一件旧物，唤醒它的物灵")

                Button {
                    showingReceive = true
                } label: {
                    Label("接灵", systemImage: "bird")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .foregroundStyle(.ink)
                .accessibilityHint("收下身边的人传给你的物灵")
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        // 按钮下面垫一层渐隐的纸色，免得盖住图鉴卡片上的字
        .background {
            LinearGradient(colors: [Color.paper.opacity(0), Color.paper.opacity(0.92), Color.paper],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

/// 图鉴为空时：一句竖排的"万物有灵"，加一段说明。
private struct EmptyCollectionView: View {
    var body: some View {
        VStack(spacing: 36) {
            HStack(alignment: .top, spacing: 26) {
                VerticalText(text: "道一声谢", font: .system(size: 22, weight: .regular, design: .serif), spacing: 6)
                    .foregroundStyle(.inkSecondary)
                    .padding(.top, 48)
                VerticalText(text: "万物有灵", font: .system(size: 34, weight: .semibold, design: .serif), spacing: 8)
            }

            VStack(spacing: 10) {
                Text("《抱朴子》里说：「万物之老者，\n其精悉能假托人形。」\n东西被人珍惜久了，就有了灵性。")
                Text("拍下一件你舍不得扔的旧物，\n唤醒它的物灵，然后安心放手。")
            }
            .font(.system(size: 15))
            .lineSpacing(5)
            .foregroundStyle(.inkSecondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    CollectionView()
        .modelContainer(PreviewData.container)
}
