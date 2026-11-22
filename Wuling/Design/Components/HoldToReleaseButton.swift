import SwiftUI

/// 长按送别。
///
/// 按住时，一圈朱红进度沿印章外圈走完，圈里的朱砂一点点洇满；
/// 触感（Core Haptics）和一段和音一起慢慢涨上来，印章越来越"沉"，快满时微微发颤。
/// 走满的一刻：印章重重落下，一圈朱色的波纹荡开。
/// 中途松手，进度会温柔地退回去，声音像一口气轻轻呼出，什么都不会发生。
/// 使用 VoiceOver 时，双击即可完成，不需要长按。
struct HoldToReleaseButton: View {
    var duration: Double = 2.4
    var label: String = "送别"
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var isPressing = false
    @State private var pressStart: Date?
    @State private var hapticStep = 0
    @State private var completed = false
    @State private var burst = false
    @State private var hapticTask: Task<Void, Never>?
    @State private var haptics = HoldHaptics()
    /// 这台设备用 Core Haptics；不支持时退回分段的 sensoryFeedback
    @State private var richHaptics = false

    private let steps = 6

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // 送出去时荡开的一圈朱色波纹
                Circle()
                    .stroke(Color.vermilion.opacity(burst ? 0 : 0.55), lineWidth: burst ? 1 : 6)
                    .frame(width: 118, height: 118)
                    .scaleEffect(burst ? 1.9 : 1)
                    .opacity(completed ? 1 : 0)
                Circle()
                    .fill(Color.vermilion.opacity(isPressing ? 0.12 : 0.06))
                    .frame(width: 132, height: 132)
                // 圈里的朱砂随进度洇开
                Circle()
                    .fill(RadialGradient(colors: [Color.vermilion.opacity(0.28), Color.vermilion.opacity(0.05)],
                                         center: .center, startRadius: 0, endRadius: 60))
                    .frame(width: 116, height: 116)
                    .scaleEffect(max(0.001, progress))
                    .blur(radius: 6 * (1 - progress))
                Circle()
                    .stroke(Color.hairline, lineWidth: 2)
                    .frame(width: 118, height: 118)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.vermilion, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 118, height: 118)
                seal
            }
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 60) {
                complete()
            } onPressingChanged: { pressing in
                pressing ? begin() : cancel()
            }

            Text(completed ? "已送别" : (isPressing ? "再等一下……" : "长按印章，送它离开"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.inkSecondary)
                .contentTransition(.opacity)
                .animation(.wlCalm, value: isPressing)
        }
        .sensoryFeedback(trigger: hapticStep) { _, step in
            guard step > 0, !richHaptics else { return nil }
            let weight: SensoryFeedback.Weight = step < 3 ? .light : (step < 5 ? .medium : .heavy)
            return .impact(weight: weight, intensity: min(1, 0.35 + Double(step) * 0.11))
        }
        .sensoryFeedback(trigger: completed) { _, done in
            done && !richHaptics ? .success : nil
        }
        .disabled(completed)
        .onAppear {
            richHaptics = HoldHaptics.isSupported
            RitualSound.prepare([.holdSwell, .scatter])
        }
        .onDisappear {
            if isPressing { cancel() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("长按三秒送别。使用旁白时，双击即可。")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
    }

    /// 印章：按下去变"沉"（缩小），快满时微微发颤，越接近终点颤得越明显（减弱动态效果时不颤）。
    /// 始终包在同一个 TimelineView 里（不按时暂停），免得切换结构时丢掉缩放动画。
    private var seal: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isPressing || reduceMotion)) { timeline in
            let elapsed = pressStart.map { timeline.date.timeIntervalSince($0) } ?? 0
            let p = isPressing ? min(1, max(0, elapsed / duration)) : 0
            let shake = reduceMotion ? 0 : pow(p, 2.2) * 1.6
            SealStamp(text: label, size: 66, rotation: .zero)
                .scaleEffect(completed ? 1 : (isPressing ? 0.86 : 1))
                .animation(completed ? .spring(response: 0.28, dampingFraction: 0.42) : .wlLift, value: isPressing)
                .offset(x: sin(elapsed * 71) * shake, y: cos(elapsed * 57) * shake * 0.6)
        }
    }

    private func begin() {
        guard !completed else { return }
        isPressing = true
        pressStart = .now
        withAnimation(.linear(duration: duration)) { progress = 1 }
        RitualSound.beginHold()
        AmbientMusic.duck(for: duration + 0.5)
        if richHaptics {
            richHaptics = haptics.begin(duration: duration)
        }
        hapticTask?.cancel()
        hapticTask = Task { @MainActor in
            for step in 1...steps {
                try? await Task.sleep(for: .seconds(duration / Double(steps + 1)))
                if Task.isCancelled { return }
                hapticStep = step
            }
        }
    }

    private func cancel() {
        isPressing = false
        pressStart = nil
        hapticTask?.cancel()
        hapticStep = 0
        guard !completed else { return }
        haptics.cancel()
        RitualSound.endHold(completed: false)
        withAnimation(.smooth(duration: 0.4)) { progress = 0 }
    }

    private func complete() {
        guard !completed else { return }
        hapticTask?.cancel()
        isPressing = false
        pressStart = nil
        withAnimation(.smooth(duration: 0.2)) { progress = 1 }
        completed = true
        haptics.complete()
        RitualSound.endHold(completed: true)
        RitualSound.play(.scatter)
        withAnimation(.easeOut(duration: 0.9)) { burst = true }
        onComplete()
    }
}

#Preview {
    HoldToReleaseButton { }
        .padding(40)
        .background(PaperBackground())
}
