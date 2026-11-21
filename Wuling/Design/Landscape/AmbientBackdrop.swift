import SwiftUI

/// 其他页面的背景：同一幅山水，淡淡地铺在纸上，上半部分化入纸色，不影响阅读。
/// 让每个页面都还在"同一座园林"里，而不是一张张白纸。
struct AmbientBackdrop: View {
    /// 山水的浓淡：0 只有纸，1 完整山水
    var intensity: Double = 0.5
    var lanterns: Int = 0
    var geese: Int = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PaperBackground()
            TimelineView(.everyMinute) { timeline in
                LivingLandscape(scene: LandscapeScene(date: timeline.date, isDark: colorScheme == .dark,
                                                      lanterns: lanterns, geese: geese))
            }
            .opacity(intensity)
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.3), location: 0.35),
                    .init(color: .black, location: 0.8),
                ], startPoint: .top, endPoint: .bottom)
            }
            .animation(.wlCalm, value: intensity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
