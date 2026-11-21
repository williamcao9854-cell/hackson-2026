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
    @State private var motionStarted = false

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: interactive ? 1.0 / 30 : 1.0 / 15, paused: reduceMotion)) { timeline in
                let angles = Self.angles(time: timeline.date.timeIntervalSinceReferenceDate,
                                         seed: phaseSeed, sway: interactive ? 7 : 5,
                                         tilt: reduceMotion ? CGSize.zero : motion.tilt,
                                         drag: drag, still: reduceMotion)
                standee(size: geo.size, yaw: angles.yaw, pitch: angles.pitch)
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
        .onAppear {
            guard !reduceMotion, !motionStarted else { return }
            motion.start()
            motionStarted = true
        }
        .onDisappear {
            guard motionStarted else { return }
            motion.stop()
            motionStarted = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("物灵立牌")
        .accessibilityHint(interactive ? "左右拖动可以转动它" : "")
    }

    /// 摇摆 + 倾斜 + 拖动，合成立牌的转角（度）
    private static func angles(time: Double, seed: Double, sway: Double, tilt: CGSize, drag: CGSize, still: Bool) -> (yaw: Double, pitch: Double) {
        let idle: Double = still ? 0 : sin(time * 0.55 + seed) * sway
        let tiltX = Double(tilt.width)
        let tiltY = Double(tilt.height)
        let dragX = Double(drag.width)
        let dragY = Double(drag.height)
        let rawYaw: Double = idle + tiltX * 16 + dragX / 5
        let rawPitch: Double = -tiltY * 5 - dragY / 14
        let yaw: Double = min(42, max(-42, rawYaw))
        let pitch: Double = min(12, max(-12, rawPitch))
        return (yaw, pitch)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { drag = $0.translation }
            .onEnded { _ in
                withAnimation(.spring(response: 0.7, dampingFraction: 0.5)) { drag = .zero }
            }
    }

    private func standee(size: CGSize, yaw: Double, pitch: Double) -> some View {
        // renderingMode 只能用在 Image 上，所以剪影要在 resizable / scaledToFit 之前设置
        let image = Image(uiImage: figure).resizable().scaledToFit()
        let silhouette = Image(uiImage: figure).renderingMode(.template).resizable().scaledToFit()
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let turn = CGFloat(sin(yaw * Double.pi / 180))
        // 每层剪影错开的距离：转得越多，侧边露得越多
        let step: CGFloat = -turn * max(0.8, w / 170)
        // 详情页的大立牌 7 层；园林里的小立牌 4 层就够了，省电
        let layers = interactive ? 7 : 4
        let shadowWidth: CGFloat = w * 0.62 * (1 - abs(turn) * 0.2)
        let shadowHeight: CGFloat = max(6, h * 0.05)
        let shadowBlur: CGFloat = max(3, w / 40)
        let shadowX: CGFloat = -turn * w * 0.05
        let shadowY: CGFloat = h * 0.005
        let baseWidth: CGFloat = w * 0.6
        let baseHeight: CGFloat = max(8, h * 0.07)
        let bodyHeight: CGFloat = h * 0.84
        let hopLift: CGFloat = hop ? -h * 0.04 : 0
        let hopScale: CGFloat = hop ? 1.06 : 1
        let bottomPadding: CGFloat = max(4, h * 0.035)
        let shine = CGFloat(yaw / 45)
        let shineStart = UnitPoint(x: 0.05 + shine, y: 0)
        let shineEnd = UnitPoint(x: 0.45 + shine, y: 1)
        let yawAngle = Angle.degrees(yaw)
        let pitchAngle = Angle.degrees(pitch)

        return ZStack(alignment: .bottom) {
            // 地上的影子
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: shadowWidth, height: shadowHeight)
                .blur(radius: shadowBlur)
                .offset(x: shadowX, y: shadowY)

            // 底座：大立牌用 Liquid Glass，园林里的小立牌用普通半透明，减轻渲染压力
            if interactive {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: baseWidth, height: baseHeight)
                    .glassEffect(.regular, in: Capsule())
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5) }
                    .frame(width: baseWidth, height: baseHeight)
            }

            // 立牌本体
            ZStack {
                ForEach(0..<layers, id: \.self) { i in
                    let edge: Color = i == 0 ? Color(white: 0.76) : Color(white: 0.95)
                    let shift: CGFloat = step * CGFloat(layers - i)
                    silhouette
                        .foregroundStyle(edge)
                        .offset(x: shift)
                }
                image
                // 亚克力高光：随角度扫过
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.6), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: shineStart,
                    endPoint: shineEnd
                )
                .mask { image }
                .opacity(0.4)
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .frame(height: bodyHeight)
            .scaleEffect(hopScale, anchor: .bottom)
            .offset(y: hopLift)
            .rotation3DEffect(yawAngle, axis: (x: 0, y: 1, z: 0), anchor: .bottom, perspective: 0.45)
            .rotation3DEffect(pitchAngle, axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.45)
            .padding(.bottom, bottomPadding)
        }
        .frame(width: w, height: h)
    }
}
