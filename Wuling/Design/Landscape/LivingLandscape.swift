import CoreMotion
import os
import SwiftUI

/// 会呼吸的水墨山水：随时辰、节气变化，倾斜手机有景深。
struct LivingLandscape: View {
    var scene: LandscapeScene

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let motion = MotionParallax.shared
    @State private var start = Date.now
    @State private var motionStarted = false
    @State private var isVisible = true

    var body: some View {
        let paused = reduceMotion || !isVisible || scenePhase != .active
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: paused)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
                scene.draw(context, size: size, t: t, tilt: reduceMotion ? .zero : motion.tilt)
            }
        }
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
        .accessibilityHidden(true)
    }
}

/// 读取设备倾斜，平滑后给山水、立牌做景深错动。
/// 全 App 共用一个 CMMotionManager（Apple 建议只创建一个），回调放在后台队列避免占主线程。
final class MotionParallax: @unchecked Sendable {
    static let shared = MotionParallax()

    private let lock = OSAllocatedUnfairLock(initialState: CGSize.zero)
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "wuling.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()
    private var users = 0

    var tilt: CGSize {
        lock.withLock { $0 }
    }

    @MainActor
    func start() {
        users += 1
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 20
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // 手机正常竖握时 pitch 约 0.8 弧度，以此为中心
            let x = max(-1, min(1, motion.attitude.roll / 0.5))
            let y = max(-1, min(1, (motion.attitude.pitch - 0.8) / 0.5))
            lock.withLock { current in
                current = CGSize(width: current.width * 0.88 + x * 0.12,
                                 height: current.height * 0.88 + y * 0.12)
            }
        }
    }

    @MainActor
    func stop() {
        users = max(0, users - 1)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }
}
