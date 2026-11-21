import SwiftUI

/// 其他页面的背景：同一幅山水，淡淡地铺在纸上，上半部分化入纸色，不影响阅读。
/// 让每个页面都还在"同一座园林"里，而不是一张张白纸。换景后，这里也跟着换。
struct AmbientBackdrop: View {
    /// 山水的浓淡：0 只有纸，1 完整山水
    var intensity: Double = 0.5
    var lanterns: Int = 0
    var geese: Int = 0

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SceneChoice.storageKey) private var choice: SceneChoice = .auto

    var body: some View {
        ZStack {
            Color.paper
            TimelineView(.everyMinute) { timeline in
                LivingLandscape(scene: LandscapeScene(date: timeline.date, isDark: colorScheme == .dark, choice: choice,
                                                      lanterns: lanterns, geese: geese,
                                                      showsCelestial: false, isAmbient: true),
                                frameRate: 15,
                                revealOrigin: UnitPoint(x: 0.5, y: 0.75))
            }
            .opacity(intensity)
            // 上半部分化入纸色：盖一层渐变的纸，而不是 mask，省掉每帧一次离屏渲染
            LinearGradient(stops: [
                .init(color: Color.paper, location: 0),
                .init(color: Color.paper.opacity(0.7), location: 0.35),
                .init(color: Color.paper.opacity(0), location: 0.8),
            ], startPoint: .top, endPoint: .bottom)
            // 纸纹在最上面，像画在纸上
            PaperFibers()
        }
        .animation(.wlCalm, value: intensity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
