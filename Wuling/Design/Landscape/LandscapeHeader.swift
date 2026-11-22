import SwiftUI

/// 图鉴首页顶部：一幅会随时辰、节气变化的山水，右侧竖排节气与物候（Liquid Glass 题签）。
///
/// 送别的物灵化作水面的河灯，传出去的物灵化作远天的鸿雁。每个人的园林都不一样。
/// 轻点题签可以换景；轻点山水，水面会泛起涟漪。
struct LandscapeHeader: View {
    var topInset: CGFloat
    var lanterns: Int
    var geese: Int
    /// 轻点题签：打开换景面板
    var onChangeScene: (() -> Void)? = nil
    /// 有一封没读的节气来信时，标题下面亮起「一封来信」
    var letter: SeasonalLetter? = nil
    var onOpenLetter: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SceneChoice.storageKey) private var choice: SceneChoice = .auto
    @AppStorage(SceneChoice.showcaseKey) private var showcase = false

    var body: some View {
        // 每分钟刷新一次时辰与节气
        TimelineView(.everyMinute) { timeline in
            let date = timeline.date
            let scene = LandscapeScene(date: date, isDark: colorScheme == .dark, choice: choice,
                                       lanterns: showcase ? max(lanterns, 4) : lanterns,
                                       geese: showcase ? max(geese, 5) : geese)
            let term = choice.solarTerm(for: date)
            content(scene: scene, term: term)
        }
    }

    private func content(scene: LandscapeScene, term: SolarTerm) -> some View {
        let textColor: Color = scene.isNight ? Color(uiColor: UIColor(hex: 0xEDE8DF)) : Color.inkOnArt
        return ZStack(alignment: .topLeading) {
            LivingLandscape(scene: scene, frameRate: 24, interactive: true)

            // 底部化入纸色，和下面的图鉴自然衔接。
            // 盖一层渐变的纸，而不是给整块画面加 mask：每帧省一次离屏渲染
            LinearGradient(stops: [
                .init(color: Color.paper.opacity(0), location: 0.8),
                .init(color: Color.paper, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)

            // 标题
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    Text("物灵")
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                    SealStamp(text: "图鉴", size: 30, rotation: .degrees(-6))
                        .offset(y: 2)
                }
                Text("万物有灵。谢谢它们陪过你。")
                    .font(.system(size: 15))
                    .opacity(0.75)
            }
            .foregroundStyle(textColor)
            .padding(.top, topInset + 4)
            .padding(.leading, Metrics.gutter)
            .allowsHitTesting(false)

            if let letter, let onOpenLetter {
                LetterBadge(messenger: letter.messenger, textColor: textColor, action: onOpenLetter)
                    .padding(.top, topInset + 92)
                    .padding(.leading, Metrics.gutter)
                    .transition(.opacity.combined(with: .offset(y: -6)))
                    .accessibilityLabel("一封来信，来自\(letter.spiritName)")
            }

            // 节气 · 物候：也是换景的入口
            Button {
                onChangeScene?()
            } label: {
                VStack(spacing: 8) {
                    VerticalText(text: term.name, font: .system(size: 19, weight: .semibold, design: .serif), spacing: 1)
                    Rectangle().fill(textColor.opacity(0.35)).frame(width: 1, height: 12)
                    VerticalText(text: term.pentad, font: .system(size: 12, weight: .regular, design: .serif), spacing: 1)
                        .opacity(0.8)
                    if onChangeScene != nil {
                        Image(systemName: "mountain.2")
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.65)
                            .padding(.top, 2)
                    }
                }
                .foregroundStyle(textColor)
                .padding(.vertical, 14)
                .padding(.horizontal, 10)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.clear.interactive(), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, Metrics.gutter)
            .padding(.top, topInset + 70)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("节气：\(term.name)，\(term.pentad)")
            .accessibilityHint(onChangeScene == nil ? "" : "轻点换一幅景")
            .accessibilityAddTraits(onChangeScene == nil ? [] : .isButton)
        }
    }
}

#Preview {
    ScrollView {
        LandscapeHeader(topInset: 60, lanterns: 3, geese: 2)
            .frame(height: 380)
    }
    .ignoresSafeArea()
    .background(PaperBackground())
}
