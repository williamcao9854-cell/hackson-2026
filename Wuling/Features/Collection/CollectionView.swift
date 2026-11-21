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
        var id: String { rawValue }
    }

    private var filtered: [Spirit] {
        switch filter {
        case .all: spirits
        case .living: spirits.filter { !$0.isReleased }
        case .released: spirits.filter(\.isReleased)
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 8)

                    if spirits.isEmpty {
                        EmptyCollectionView()
                            .padding(.top, 56)
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
                encounterButton
            }
            .fullScreenCover(isPresented: $showingEncounter) {
                EncounterView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
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
                    showingEncounter = false
                    incoming = IncomingSpirit(capsule: capsule)
                } catch {
                    incomingError = error.localizedDescription
                }
            }
        }
        .foregroundStyle(.ink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("物灵")
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                SealStamp(text: "图鉴", size: 30, rotation: .degrees(-6))
                    .offset(y: 2)
            }
            Text("万物有灵。谢谢它们陪过你。")
                .font(.system(size: 15))
                .foregroundStyle(.inkSecondary)
            if !spirits.isEmpty {
                let living = spirits.filter { !$0.isReleased }.count
                Text("同住 \(living)　·　已送别 \(spirits.count - living)")
                    .font(.wlCaption)
                    .monospacedDigit()
                    .foregroundStyle(.inkSecondary)
                    .padding(.top, 2)
            }
        }
    }

    private var encounterButton: some View {
        Button {
            showingEncounter = true
        } label: {
            Label("遇见", systemImage: "camera.viewfinder")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 22)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(.vermilion)
        .padding(.bottom, 8)
        .accessibilityHint("拍下一件旧物，唤醒它的物灵")
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
                Text("日本的传说里，器物被人珍惜久了，\n就会生出灵魂，叫作「付丧神」。")
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
