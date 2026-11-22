import CoreMotion
import os
import SwiftUI

/// 会呼吸的水墨山水：随时辰、节气变化，倾斜手机有景深。
///
/// - 换景时，新的一幅从题签处像一滴墨在宣纸上晕开，盖住旧的一幅
/// - 第一次打开 App 时，首页的山水也这样从纸上晕开（只放一次）
/// - 首页可以点：点在水上荡开涟漪，并响一个水音（从左到右排成五声音阶，连着点像在弹水）；
///   点在山和天上晕开一点淡墨，"嗒"地一声
struct LivingLandscape: View {
    var scene: LandscapeScene
    /// 每秒画几帧：首页 24 帧；其他页面的淡背景 15 帧就够，省电
    var frameRate: Double
    /// 首页可以点出涟漪
    var interactive: Bool
    /// 换景时新景从哪里晕开（默认是右上角的节气题签）
    var revealOrigin: UnitPoint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let motion = MotionParallax.shared
    @State private var start = Date.now
    @State private var motionStarted = false
    @State private var isVisible = true
    @State private var ripples: [LandscapeScene.Ripple] = []
    @State private var tapCount = 0
    @State private var canvasSize: CGSize = .zero
    /// 当前稳定显示的景；换景时它成为"旧景"
    @State private var shown: LandscapeScene?
    @State private var outgoing: LandscapeScene?
    @State private var revealStart: Date?

    private static let revealDuration: Double = 1.6
    @MainActor private static var introPlayed = false

    init(scene: LandscapeScene, frameRate: Double = 24, interactive: Bool = false,
         revealOrigin: UnitPoint = UnitPoint(x: 0.9, y: 0.4)) {
        self.scene = scene
        self.frameRate = frameRate
        self.interactive = interactive
        self.revealOrigin = revealOrigin
        // 开场晕开要从第一帧就开始，否则会先闪一下完整的画面
        let intro = interactive && !Self.introPlayed
        _revealStart = State(initialValue: intro ? Date.now : nil)
    }

    var body: some View {
        let paused = reduceMotion || !isVisible || scenePhase != .active
        TimelineView(.animation(minimumInterval: 1.0 / frameRate, paused: paused)) { timeline in
            canvas(at: timeline.date)
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .gesture(SpatialTapGesture().onEnded { value in addRipple(at: value.location) },
                 including: interactive ? .all : .none)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: tapCount)
        .onAppear {
            isVisible = true
            if shown == nil { shown = scene }
            if interactive && !Self.introPlayed {
                Self.introPlayed = true
                if reduceMotion {
                    revealStart = nil
                } else if let revealStart {
                    finishReveal(startedAt: revealStart)
                }
            }
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
        .onChange(of: scene.signature) { _, _ in
            beginReveal()
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func canvas(at date: Date) -> some View {
        let t: Double = reduceMotion ? 0 : date.timeIntervalSince(start)
        let tilt: CGSize = reduceMotion ? .zero : motion.tilt
        let current = scene
        let marks = ripples
        if let revealStart {
            let raw: Double = date.timeIntervalSince(revealStart) / Self.revealDuration
            let progress: Double = Self.ease(min(1, max(0, raw)))
            ZStack {
                // 旧景垫在下面；开场时没有旧景，底下就是纸
                if let outgoing {
                    Canvas { context, size in
                        outgoing.draw(context, size: size, t: t, tilt: tilt)
                    }
                }
                Canvas { context, size in
                    current.draw(context, size: size, t: t, tilt: tilt, ripples: marks)
                }
                .mask {
                    InkSpreadMask(progress: progress, origin: revealOrigin)
                }
            }
        } else {
            // 平时只有一块画布、没有遮罩：不产生额外的离屏渲染
            Canvas { context, size in
                current.draw(context, size: size, t: t, tilt: tilt, ripples: marks)
            }
        }
    }

    private static func ease(_ x: Double) -> Double {
        x * x * (3 - 2 * x)
    }

    private func beginReveal() {
        let previous = shown
        shown = scene
        guard let previous, !reduceMotion, isVisible, scenePhase == .active else {
            outgoing = nil
            revealStart = nil
            return
        }
        startReveal(from: previous)
    }

    private func startReveal(from previous: LandscapeScene) {
        outgoing = previous
        let began = Date.now
        revealStart = began
        finishReveal(startedAt: began)
    }

    /// 晕开结束后撤掉旧景和遮罩
    private func finishReveal(startedAt began: Date) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.revealDuration + 0.1))
            // 期间又换了一次景，就交给那一次收尾
            guard revealStart == began else { return }
            outgoing = nil
            revealStart = nil
        }
    }

    private func addRipple(at location: CGPoint) {
        playTapSound(at: location)
        guard !reduceMotion else { return }
        let now: Double = Date.now.timeIntervalSince(start)
        var kept = ripples.filter { now - $0.start < LandscapeScene.rippleLife }
        kept.append(LandscapeScene.Ripple(x: Double(location.x), y: Double(location.y), start: now))
        ripples = Array(kept.suffix(6))
        tapCount += 1
    }
}

extension LivingLandscape {
    /// 水面上：按左右位置挑一个五声音阶的音；水面以上：毛笔点纸
    fileprivate func playTapSound(at location: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        if Double(location.y) > Double(canvasSize.height) * LandscapeScene.waterLine {
            let notes = RitualSound.Cue.waterNotes
            let note = Int(Double(location.x / canvasSize.width) * Double(notes))
            RitualSound.play(.water(min(max(note, 0), notes - 1)))
        } else {
            RitualSound.play(.inkDot)
        }
    }
}

/// 换景的遮罩：一大团墨从起点晕开，旁边两小团先走一步，让边缘不那么规整，像墨在宣纸上洇开。
private struct InkSpreadMask: View {
    var progress: Double
    var origin: UnitPoint

    var body: some View {
        GeometryReader { geo in
            let w = Double(geo.size.width)
            let h = Double(geo.size.height)
            let reach: Double = (w * w + h * h).squareRoot() * 1.3
            let cx: Double = Double(origin.x) * w
            let cy: Double = Double(origin.y) * h
            let main: Double = max(1, reach * 2 * progress)
            let lead: Double = max(1, reach * 1.1 * progress)
            let small: Double = lead * 0.8
            ZStack {
                Circle()
                    .frame(width: main, height: main)
                    .position(x: cx, y: cy)
                Circle()
                    .frame(width: lead, height: lead)
                    .position(x: cx - w * 0.4 * progress, y: cy + h * 0.22 * progress)
                Circle()
                    .frame(width: small, height: small)
                    .position(x: cx + w * 0.05 * progress, y: cy + h * 0.5 * progress)
            }
            .blur(radius: 26)
        }
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

/// 静态的小幅山水（换景面板里的缩略图）：按手机首页的尺寸画，再整体缩小，比例和真实画面一致。
struct LandscapeThumbnail: View {
    var scene: LandscapeScene
    /// 用哪一刻的画面
    var moment: Double = 24

    var body: some View {
        Canvas { context, size in
            let k: Double = 0.32
            var ctx = context
            ctx.scaleBy(x: k, y: k)
            let virtual = CGSize(width: Double(size.width) / k, height: Double(size.height) / k)
            scene.draw(ctx, size: virtual, t: moment, tilt: .zero)
        }
        .accessibilityHidden(true)
    }
}
