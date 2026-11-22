import CoreHaptics
import Foundation

/// 长按送别的触感（Core Haptics）：
///
/// - 按住时，一股持续的震动从几乎感觉不到慢慢涨上来，越来越"实"；
///   上面叠着一下下心跳似的轻敲，越来越快——像屏住的一口气
/// - 送出去的一刻：重重一"咚"，再拖一小段渐弱的余震
/// - 中途松手：震动立刻停下，什么都不发生
///
/// 不支持 Core Haptics 的设备（iPad 等）返回 false，由调用方退回 SwiftUI 的 sensoryFeedback。
@MainActor
final class HoldHaptics {
    static var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    /// 开始蓄力。duration 和长按的时长一致。
    @discardableResult
    func begin(duration: Double) -> Bool {
        guard Self.isSupported, let engine = readyEngine() else { return false }
        do {
            let pattern = try Self.swell(duration: duration)
            let player = try engine.makeAdvancedPlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            self.player = player
            return true
        } catch {
            return false
        }
    }

    /// 中途松手
    func cancel() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    /// 送出去了
    func complete() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        guard Self.isSupported, let engine = readyEngine(),
              let pattern = try? Self.release(),
              let finale = try? engine.makePlayer(with: pattern)
        else { return }
        try? finale.start(atTime: CHHapticTimeImmediate)
    }

    private func readyEngine() -> CHHapticEngine? {
        if engine == nil {
            guard let created = try? CHHapticEngine() else { return nil }
            created.isAutoShutdownEnabled = true
            created.playsHapticsOnly = true
            // 系统把引擎停了（切后台、来电），下次用的时候重新启动
            created.resetHandler = { [weak created] in try? created?.start() }
            engine = created
        }
        do {
            try engine?.start()
        } catch {
            return nil
        }
        return engine
    }

    // MARK: - 图样

    private static func value(_ id: CHHapticEvent.ParameterID, _ v: Float) -> CHHapticEventParameter {
        CHHapticEventParameter(parameterID: id, value: v)
    }

    /// 蓄力：持续震动的强度、锐度沿曲线上扬，上面叠一串越来越密的轻敲
    private static func swell(duration: Double) throws -> CHHapticPattern {
        var events = [CHHapticEvent(eventType: .hapticContinuous,
                                    parameters: [value(.hapticIntensity, 1), value(.hapticSharpness, 0.2)],
                                    relativeTime: 0, duration: duration)]
        var t = 0.22
        var gap = 0.46
        while t < duration - 0.08 {
            let progress = Float(t / duration)
            events.append(CHHapticEvent(eventType: .hapticTransient,
                                        parameters: [value(.hapticIntensity, 0.28 + 0.6 * progress),
                                                     value(.hapticSharpness, 0.25 + 0.45 * progress)],
                                        relativeTime: t))
            gap = max(0.11, gap * 0.8)
            t += gap
        }
        let intensity = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 0.06),
            .init(relativeTime: duration * 0.45, value: 0.22),
            .init(relativeTime: duration * 0.8, value: 0.5),
            .init(relativeTime: duration, value: 0.78),
        ], relativeTime: 0)
        let sharpness = CHHapticParameterCurve(parameterID: .hapticSharpnessControl, controlPoints: [
            .init(relativeTime: 0, value: -0.2),
            .init(relativeTime: duration, value: 0.35),
        ], relativeTime: 0)
        return try CHHapticPattern(events: events, parameterCurves: [intensity, sharpness])
    }

    /// 送出：一记沉的"咚"，再拖 0.45 秒渐弱的余震
    private static func release() throws -> CHHapticPattern {
        let events = [
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [value(.hapticIntensity, 1), value(.hapticSharpness, 0.35)], relativeTime: 0),
            CHHapticEvent(eventType: .hapticContinuous,
                          parameters: [value(.hapticIntensity, 0.55), value(.hapticSharpness, 0.1)],
                          relativeTime: 0.02, duration: 0.45),
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [value(.hapticIntensity, 0.35), value(.hapticSharpness, 0.6)], relativeTime: 0.16),
        ]
        let fade = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0.02, value: 1),
            .init(relativeTime: 0.47, value: 0),
        ], relativeTime: 0)
        return try CHHapticPattern(events: events, parameterCurves: [fade])
    }
}
