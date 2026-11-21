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
    @Environment(\.scenePhase) private var scenePhase
    private let motion = MotionParallax.shared
    @State private var drag: CGSize = .zero
    @State private var hop = false
    @State private var phaseSeed = Double.random(in: 0...10)
    @State private var motionStarted = false
    @State private var isVisible = false

    var body: some View {
        let paused = reduceMotion || !isVisible || scenePhase != .active
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: interactive ? 1.0 / 30 : 1.0 / 10, paused: paused)) { timeline in
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
            isVisible = true
            guard !reduceMotion, !motionStarted else { return }
            motion.start()
            motionStarted = true
        }
        .onDisappear {
            isVisible = false
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
        // 亚克力厚度：转得越多，侧边露得越多（首页多立牌用轻量层数避免压爆 GPU）
        let layers = interactive ? 9 : 3
        let step: CGFloat = -turn * max(1.0, w / 130)

        let baseWidth: CGFloat = w * 0.66
        let baseHeight: CGFloat = max(10, h * 0.11)
        let footY: CGFloat = h - baseHeight * 0.55          // 立牌的脚落在底座中间偏后
        let bodyHeight: CGFloat = footY * 0.97
        let shadowWidth: CGFloat = baseWidth * 1.15
        let shadowHeight: CGFloat = baseHeight * 0.9
        let hopLift: CGFloat = hop ? -h * 0.05 : 0
        let hopScale: CGFloat = hop ? 1.05 : 1
        let shine = CGFloat(yaw / 40)
        let shineStart = UnitPoint(x: -0.1 + shine, y: 0)
        let shineEnd = UnitPoint(x: 0.4 + shine, y: 1)
        let yawAngle = Angle.degrees(yaw)
        let pitchAngle = Angle.degrees(pitch)

        return ZStack(alignment: .top) {
            // 地上的影子
            Ellipse()
                .fill(Color.black.opacity(0.16))
                .frame(width: shadowWidth, height: shadowHeight)
                .blur(radius: max(4, w / 28))
                .offset(x: -turn * w * 0.06, y: h - shadowHeight * 0.75)

            // 椭圆玻璃底座：有一点透视，像真的放在桌上
            ZStack {
                if interactive {
                    Ellipse()
                        .fill(Color.white.opacity(0.12))
                        .glassEffect(.regular, in: Ellipse())
                } else {
                    Ellipse()
                        .fill(Color.white.opacity(0.5))
                }
                Ellipse()
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.8)
                    .padding(1)
                // 底座上的倒影（详情页交互大立牌渲染；首页多小立牌跳过离屏 blur+mask 降 GPU 压力）
                if interactive {
                    image
                        .scaleEffect(x: 1, y: -1)
                        .frame(height: bodyHeight * 0.35)
                        .opacity(0.14)
                        .blur(radius: 1.5)
                        .mask(Ellipse())
                }
            }
            .frame(width: baseWidth, height: baseHeight)
            .offset(y: h - baseHeight)

            // 立牌本体
            ZStack {
                ForEach(0..<layers, id: \.self) { i in
                    // 越靠后的层越暗：亚克力的侧面
                    let depth: Double = Double(layers - i) / Double(layers)
                    let tone: Double = 0.97 - depth * 0.22
                    let shift: CGFloat = step * CGFloat(layers - i)
                    silhouette
                        .foregroundStyle(Color(white: tone))
                        .offset(x: shift, y: -abs(shift) * 0.15)
                }
                image
                    .shadow(color: .black.opacity(0.15), radius: 0.6)
                // 高光：随角度扫过（仅交互大立牌启用离屏 mask，首页多立牌保持流畅）
                if interactive {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.65), location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: shineStart,
                        endPoint: shineEnd
                    )
                    .mask { image }
                    .opacity(0.42)
                }
            }
            // 宽的物品（椅子、电脑）会被宽度限制而变矮：贴底对齐，脚始终落在底座上
            .frame(width: w * 0.9, height: bodyHeight, alignment: .bottom)
            .scaleEffect(hopScale, anchor: .bottom)
            .offset(y: footY - bodyHeight + hopLift)
            .rotation3DEffect(yawAngle, axis: (x: 0, y: 1, z: 0), anchor: .bottom, perspective: 0.5)
            .rotation3DEffect(pitchAngle, axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
        }
        .frame(width: w, height: h, alignment: .top)
    }
}
