import SwiftUI

/// 图鉴首页顶部：一幅会随时辰、节气变化的山水，
/// 月亮（或太阳）前悬着一片 Liquid Glass 的"月洞门"，右侧竖排今天的节气与物候。
///
/// 送别的物灵化作水面的河灯，传出去的物灵化作远天的鸿雁。每个人的园林都不一样。
struct LandscapeHeader: View {
    var topInset: CGFloat
    var lanterns: Int
    var geese: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 每分钟刷新一次时辰与节气
        TimelineView(.everyMinute) { timeline in
            let date = timeline.date
            let scene = LandscapeScene(date: date, isDark: colorScheme == .dark, lanterns: lanterns, geese: geese)
            let term = SolarTerm(date: date)
            content(scene: scene, term: term)
        }
    }

    private func content(scene: LandscapeScene, term: SolarTerm) -> some View {
        let textColor: Color = scene.isNight ? Color(uiColor: UIColor(hex: 0xEDE8DF)) : Color.inkOnArt
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                LivingLandscape(scene: scene)

                // 月洞门：一片圆形的透明玻璃悬在日月前，折射后面的山水
                Color.clear
                    .frame(width: 92, height: 92)
                    .glassEffect(.clear, in: Circle())
                    .position(scene.celestialPosition(in: geo.size))
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

                // 节气 · 物候
                VStack(spacing: 8) {
                    VerticalText(text: term.name, font: .system(size: 19, weight: .semibold, design: .serif), spacing: 1)
                    Rectangle().fill(textColor.opacity(0.35)).frame(width: 1, height: 12)
                    VerticalText(text: term.pentad, font: .system(size: 12, weight: .regular, design: .serif), spacing: 1)
                        .opacity(0.8)
                }
                .foregroundStyle(textColor)
                .padding(.vertical, 14)
                .padding(.horizontal, 10)
                .glassEffect(.clear, in: Capsule())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, Metrics.gutter)
                .padding(.top, topInset + 70)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("今日节气：\(term.name)，\(term.pentad)")
            }
            // 底部化入纸色，和下面的图鉴自然衔接
            .mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
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
