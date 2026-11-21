import CoreMotion
import SwiftUI

/// 会呼吸的水墨山水：随时辰、节气变化，倾斜手机有景深。
struct LivingLandscape: View {
    var scene: LandscapeScene

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let motion = MotionParallax.shared
    @State private var start = Date.now
    @State private var motionStarted = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
                scene.draw(context, size: size, t: t, tilt: reduceMotion ? .zero : motion.tilt)
            }
        }
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
        .accessibilityHidden(true)
    }
}

/// 读取设备倾斜，平滑后给山水、立牌做景深错动。
/// 全 App 共用一个 CMMotionManager（Apple 建议只创建一个），用引用计数开关。
/// 不是 @Observable：画布每帧都会重绘，直接读最新值即可，避免每次更新都触发界面刷新。
final class MotionParallax {
    static let shared = MotionParallax()

    private(set) var tilt: CGSize = .zero
    private let manager = CMMotionManager()
    private var users = 0

    func start() {
        users += 1
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // 手机正常竖握时 pitch 约 0.8 弧度，以此为中心
            let x = max(-1, min(1, motion.attitude.roll / 0.5))
            let y = max(-1, min(1, (motion.attitude.pitch - 0.8) / 0.5))
            tilt = CGSize(width: tilt.width * 0.88 + x * 0.12, height: tilt.height * 0.88 + y * 0.12)
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }
}
