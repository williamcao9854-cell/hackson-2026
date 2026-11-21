import SwiftUI

/// 一盏河灯：暖光、朱红灯身、一点火苗。送别完成时，它从物灵身边漂向园林的水面。
struct LanternGlyph: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            let time: Double = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Self.draw(context, width: Double(size.width), height: Double(size.height), time: time)
            }
        }
        .accessibilityHidden(true)
    }

    private static func draw(_ context: GraphicsContext, width: Double, height: Double, time: Double) {
        let flicker: Double = 0.85 + 0.15 * sin(time * 9)
        let cx: Double = width / 2
        let cy: Double = height * 0.6
        let glow: Double = width * 0.9
        let warm = Color(red: 0.98, green: 0.76, blue: 0.43).opacity(0.55 * flicker)
        let glowRect = CGRect(x: cx - glow, y: cy - glow, width: glow * 2, height: glow * 2)
        let glowShading = GraphicsContext.Shading.radialGradient(Gradient(colors: [warm, Color.clear]),
                                                                 center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: glow)
        context.fill(Path(ellipseIn: glowRect), with: glowShading)

        let bodyWidth: Double = width * 0.56
        let bodyHeight: Double = height * 0.34
        let bodyTop: Double = cy - height * 0.16
        let bodyRect = CGRect(x: cx - bodyWidth / 2, y: bodyTop, width: bodyWidth, height: bodyHeight)
        let corner: Double = width * 0.08
        context.fill(Path(roundedRect: bodyRect, cornerRadius: corner), with: .color(Color(uiColor: UIColor(hex: 0xC8442F))))

        let flameWidth: Double = width * 0.14
        let flameHeight: Double = height * 0.2 * flicker
        let flameRect = CGRect(x: cx - flameWidth / 2, y: bodyTop - flameHeight, width: flameWidth, height: flameHeight)
        context.fill(Path(ellipseIn: flameRect), with: .color(Color(red: 1, green: 0.86, blue: 0.55)))
    }
}

/// 一只鸿雁飞过（三只排成人字）。传灵发出、或收到物灵时出现。
struct GooseFlight: View {
    /// true：从左飞向右（送出）；false：从右飞来（收到）
    var leftToRight: Bool = true
    var duration: Double = 3.4

    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed: Double = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                Self.draw(context, width: Double(size.width), height: Double(size.height),
                          elapsed: elapsed, duration: duration, leftToRight: leftToRight)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func draw(_ context: GraphicsContext, width: Double, height: Double,
                             elapsed: Double, duration: Double, leftToRight: Bool) {
        let progress: Double = elapsed / duration
        guard progress >= 0, progress <= 1 else { return }
        let travel: Double = width + 120
        let direction: Double = leftToRight ? 1 : -1
        let startX: Double = leftToRight ? -60 : width + 60
        let lead: Double = startX + direction * progress * travel
        let baseY: Double = height * (0.65 - 0.35 * progress)
        let fade: Double = min(1, (1 - progress) * 4)
        let ink = Color.ink.opacity(0.7 * fade)

        for i in 0..<3 {
            let rank = Double((i + 1) / 2)
            let side: Double = i == 0 ? 0 : (i.isMultiple(of: 2) ? 1 : -1)
            let x: Double = lead - direction * rank * 18
            let y: Double = baseY + side * rank * 9
            let flap: Double = sin(elapsed * 7 + Double(i)) * 3
            var bird = Path()
            bird.move(to: CGPoint(x: x - 7, y: y - 1 + flap))
            bird.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 3.5, y: y - 3.5 + flap))
            bird.addQuadCurve(to: CGPoint(x: x + 7, y: y - 1 + flap), control: CGPoint(x: x + 3.5, y: y - 3.5 + flap))
            context.stroke(bird, with: .color(ink), lineWidth: 1.4)
        }
    }
}
