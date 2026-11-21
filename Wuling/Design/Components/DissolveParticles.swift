import SwiftUI

/// 送别时，原物化作光点，缓缓向上飘散。
///
/// 每个粒子的参数都由固定种子算出，每一帧重新计算位置，不需要保存状态。
struct DissolveParticles: View {
    var colors: [Color]
    var startDate: Date
    var duration: Double = 2.6
    var count: Int = 170

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                guard elapsed >= 0 else { return }
                let palette = colors.isEmpty ? [Color.vermilion] : colors
                var rng = SeededRandom(seed: 1121)

                for index in 0..<count {
                    let originX = size.width * (0.18 + rng.next() * 0.64)
                    let originY = size.height * (0.2 + rng.next() * 0.65)
                    let delay = rng.next() * 0.7
                    let rise = 50 + rng.next() * 150
                    let drift = (rng.next() - 0.5) * 70
                    let radius = 0.8 + rng.next() * 2.4
                    let wobble = rng.next() * .pi * 2
                    let isSpark = rng.next() < 0.18

                    let local = elapsed - delay
                    let life = duration - delay
                    guard local > 0, local < life else { continue }
                    let p = local / life

                    let x = originX + drift * p + sin(local * 3 + wobble) * 5
                    let y = originY - rise * (p + p * p * 0.6)
                    let alpha = (1 - p) * min(1, local * 5)
                    let r = radius * (1 - p * 0.5)
                    let color = isSpark ? Color.vermilion : palette[index % palette.count]

                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
