import SwiftUI

/// 长按送别。
///
/// 按住时，一圈朱红进度沿印章外圈走完；触感随进度由轻到重。
/// 中途松手，进度会温柔地退回去，什么都不会发生。
/// 使用 VoiceOver 时，双击即可完成，不需要长按。
struct HoldToReleaseButton: View {
    var duration: Double = 2.4
    var label: String = "送别"
    var onComplete: () -> Void

    @State private var progress: Double = 0
    @State private var isPressing = false
    @State private var hapticStep = 0
    @State private var completed = false
    @State private var hapticTask: Task<Void, Never>?

    private let steps = 6

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.vermilion.opacity(isPressing ? 0.12 : 0.06))
                    .frame(width: 132, height: 132)
                Circle()
                    .stroke(Color.hairline, lineWidth: 2)
                    .frame(width: 118, height: 118)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.vermilion, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 118, height: 118)
                SealStamp(text: label, size: 66, rotation: .zero)
                    .scaleEffect(isPressing ? 0.9 : 1)
                    .animation(.wlLift, value: isPressing)
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
            guard step > 0 else { return nil }
            let weight: SensoryFeedback.Weight = step < 3 ? .light : (step < 5 ? .medium : .heavy)
            return .impact(weight: weight, intensity: min(1, 0.35 + Double(step) * 0.11))
        }
        .sensoryFeedback(.success, trigger: completed)
        .disabled(completed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("长按三秒送别。使用旁白时，双击即可。")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
    }

    private func begin() {
        guard !completed else { return }
        isPressing = true
        withAnimation(.linear(duration: duration)) { progress = 1 }
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
        hapticTask?.cancel()
        hapticStep = 0
        guard !completed else { return }
        withAnimation(.smooth(duration: 0.4)) { progress = 0 }
    }

    private func complete() {
        guard !completed else { return }
        hapticTask?.cancel()
        isPressing = false
        withAnimation(.smooth(duration: 0.2)) { progress = 1 }
        completed = true
        onComplete()
    }
}

#Preview {
    HoldToReleaseButton { }
        .padding(40)
        .background(PaperBackground())
}
