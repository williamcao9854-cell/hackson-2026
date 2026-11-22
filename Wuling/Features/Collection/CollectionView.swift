import SwiftData
import SwiftUI

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
    @State private var showingScenes = false
    @State private var openLetter: SeasonalLetter?
    /// 在换景面板里点了「收一封节气来信」：等面板退场后再打开
    @State private var demoLetterPending = false
    @AppStorage(LetterPost.readKey) private var readLetters = ""
    @AppStorage("wuling.onboarded") private var onboarded = false
    @AppStorage(SceneChoice.storageKey) private var sceneChoice: SceneChoice = .auto
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
                let letter = unreadLetter
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        GardenHero(topInset: proxy.safeAreaInsets.top,
                                   living: spirits.filter { !$0.isReleased },
                                   lanterns: releasedCount, geese: relayedCount,
                                   showEmptyHint: !spirits.isEmpty,
                                   onChangeScene: { showingScenes = true },
                                   letter: letter,
                                   onOpenLetter: { presentLetter(letter) })
                            .frame(height: max(460, proxy.size.height * 0.62))

                        if spirits.isEmpty {
                            EmptyCollectionView()
                                .padding(.top, 12)
                        } else {
                            filterBar
                                .padding(.top, 16)

                            if filtered.isEmpty {
                                Text(emptyFilterMessage)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.inkSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 48)
                            } else {
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
                                .padding(.top, 18)
                                .animation(.smooth, value: filter)
                            }
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
                        showingScenes = true
                    } label: {
                        Image(systemName: "mountain.2")
                    }
                    .accessibilityLabel("换景")
                }
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
            .sheet(isPresented: $showingScenes, onDismiss: openDemoLetterIfNeeded) {
                SceneSheet(lanterns: releasedCount, geese: relayedCount) {
                    demoLetterPending = true
                }
            }
            .sheet(item: $openLetter) { letter in
                LetterView(letter: letter)
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
                    if showingEncounter || showingAbout || showingOnboarding || showingReceive || showingScenes || openLetter != nil {
                        // 先关掉正在打开的页面，等它退场后再弹出，否则 SwiftUI 会丢掉这次弹窗
                        showingEncounter = false
                        showingAbout = false
                        showingScenes = false
                        openLetter = nil
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
        // 换景时手动选了时辰：夜里整个 App 进入深色，其余时辰是和纸白
        .preferredColorScheme(sceneChoice.preferredColorScheme)
    }

    // MARK: - 节气来信

    private var letterSenders: [LetterPost.Sender] { spirits.filter(\.isReleased).map(\.letterSender) }

    /// 今天该来、还没读过的那封信
    private var unreadLetter: SeasonalLetter? {
        guard let letter = LetterPost.letter(on: .now, from: letterSenders) else { return nil }
        return LetterPost.isRead(letter.id, in: readLetters) ? nil : letter
    }

    /// 打开就算读过，首页的「一封来信」随之收起
    private func presentLetter(_ letter: SeasonalLetter?) {
        guard let letter else { return }
        withAnimation(.wlCalm) { readLetters = LetterPost.markingRead(letter.id, in: readLetters) }
        openLetter = letter
    }

    /// 换景面板完全退场后，再打开演示来信（两个弹窗挤在同一帧会被吞掉）
    private func openDemoLetterIfNeeded() {
        guard demoLetterPending else { return }
        demoLetterPending = false
        let letter = LetterPost.demo(on: .now, term: sceneChoice.solarTerm(for: .now), from: letterSenders)
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            openLetter = letter
        }
    }

    private var livingCount: Int { spirits.filter { !$0.isReleased }.count }
    private var relayedCount: Int { spirits.filter(\.isRelayed).count }
    private var releasedCount: Int { spirits.count - livingCount - relayedCount }

    private var emptyFilterMessage: String {
        switch filter {
        case .all: "还没有唤醒过物灵"
        case .living: "目前没有同住的物灵"
        case .released: "还没有送别过的物灵"
        case .relayed: "还没有传出过的物灵"
        }
    }

    /// 统一的图鉴筛选条（合并了原来的图例与分段选择器）
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    filterChip(symbol: nil, text: "全部", count: spirits.count, target: .all)
                    filterChip(symbol: "figure.stand", text: "同住", count: livingCount, target: .living)
                    filterChip(symbol: "flame", text: "送别", count: releasedCount, target: .released)
                    filterChip(symbol: "bird", text: "传出", count: relayedCount, target: .relayed)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 2)
        }
    }

    private func filterChip(symbol: String?, text: String, count: Int, target: Filter) -> some View {
        let selected = filter == target
        return Button {
            withAnimation(.smooth) { filter = target }
        } label: {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                }
                Text(text).font(.system(size: 13, weight: selected ? .semibold : .medium))
                Text("\(count)").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .opacity(selected ? 0.9 : 0.6)
            }
            .foregroundStyle(selected ? Color.vermilion : Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel("\(text)，\(count) 个")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
