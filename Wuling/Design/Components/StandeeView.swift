import SwiftUI

/// 亚克力立牌：把物灵从插画里抠出来，做成一块有厚度、站在玻璃底座上的立牌。
///
/// 手指左右拖动可以转它，倾斜手机它也会跟着转；不碰它时会轻轻摇摆。
/// 厚度用几层错开的剪影模拟，转动时侧边露出来，高光随角度扫过，看起来像一块真的亚克力。
struct StandeeView: View {
    var figure: UIImage
    /// 详情页可以拖动、轻点会跳一下；园林里的小立牌只随手机倾斜轻轻晃
    var interactive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let motion = MotionParallax.shared
    @State private var drag: CGSize = .zero
    @State private var hop = false
    @State private var phaseSeed = Double.random(in: 0...10)

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let idle = reduceMotion ? 0 : sin(t * 0.55 + phaseSeed) * (interactive ? 7 : 5)
                let tilt = reduceMotion ? .zero : motion.tilt
                let yaw = max(-42, min(42, idle + Double(tilt.width) * 16 + Double(drag.width) / 5))
                let pitch = max(-12, min(12, -Double(tilt.height) * 5 - Double(drag.height) / 14))
                standee(size: geo.size, yaw: yaw, pitch: pitch)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture, including: interactive ? .all : .none)
        .onTapGesture {
            guard interactive else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { hop = true }
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { hop = false }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hop)
        .onAppear { if !reduceMotion { motion.start() } }
        .onDisappear { if !reduceMotion { motion.stop() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("物灵立牌")
        .accessibilityHint(interactive ? "左右拖动可以转动它" : "")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { drag = $0.translation }
            .onEnded { _ in
                withAnimation(.spring(response: 0.7, dampingFraction: 0.5)) { drag = .zero }
            }
    }

    private func standee(size: CGSize, yaw: Double, pitch: Double) -> some View {
        let image = Image(uiImage: figure).resizable().scaledToFit()
        let turn = sin(yaw * .pi / 180)
        // 每层剪影错开的距离：转得越多，侧边露得越多
        let step = CGFloat(-turn) * max(0.8, size.width / 170)
        let layers = 7

        return ZStack(alignment: .bottom) {
            // 地上的影子
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: size.width * 0.62 * (1 - abs(turn) * 0.2), height: max(6, size.height * 0.05))
                .blur(radius: max(3, size.width / 40))
                .offset(x: CGFloat(-turn) * size.width * 0.05, y: size.height * 0.005)

            // 玻璃底座
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: size.width * 0.6, height: max(8, size.height * 0.07))
                .glassEffect(.regular, in: Capsule())

            // 立牌本体
            ZStack {
                ForEach(0..<layers, id: \.self) { i in
                    image
                        .renderingMode(.template)
                        .foregroundStyle(i == 0 ? Color(white: 0.76) : Color(white: 0.95))
                        .offset(x: step * CGFloat(layers - i))
                }
                image
                // 亚克力高光：随角度扫过
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.6), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: UnitPoint(x: 0.05 + yaw / 45, y: 0),
                    endPoint: UnitPoint(x: 0.45 + yaw / 45, y: 1)
                )
                .mask { image }
                .opacity(0.4)
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .frame(height: size.height * 0.84)
            .scaleEffect(hop ? 1.06 : 1, anchor: .bottom)
            .offset(y: hop ? -size.height * 0.04 : 0)
            .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), anchor: .bottom, perspective: 0.45)
            .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.45)
            .padding(.bottom, max(4, size.height * 0.035))
        }
        .frame(width: size.width, height: size.height)
    }
}
