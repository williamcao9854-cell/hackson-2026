import SwiftUI

/// 一盏河灯：暖光、朱红灯身、一点火苗。送别完成时，它从物灵身边漂向园林的水面。
struct LanternGlyph: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            let flicker = 0.85 + 0.15 * sin(timeline.date.timeIntervalSinceReferenceDate * 9)
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height * 0.6)
                let glow = size.width * 0.9
                context.fill(Path(ellipseIn: CGRect(x: c.x - glow, y: c.y - glow, width: glow * 2, height: glow * 2)),
                             with: .radialGradient(Gradient(colors: [Color(red: 0.98, green: 0.76, blue: 0.45).opacity(0.55 * flicker), .clear]),
                                                   center: c, startRadius: 0, endRadius: glow))
                let body = CGRect(x: c.x - size.width * 0.28, y: c.y - size.height * 0.16, width: size.width * 0.56, height: size.height * 0.34)
                context.fill(Path(roundedRect: body, cornerRadius: size.width * 0.08), with: .color(Color(uiColor: UIColor(hex: 0xC8442F))))
                let flame = CGRect(x: c.x - size.width * 0.07, y: body.minY - size.height * 0.2 * flicker, width: size.width * 0.14, height: size.height * 0.2 * flicker)
                context.fill(Path(ellipseIn: flame), with: .color(Color(red: 1, green: 0.86, blue: 0.55)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// 一只鸿雁飞过。传灵发出、或收到物灵时出现。
struct GooseFlight: View {
    /// true：从左飞向右（送出）；false：从右飞来（收到）
    var leftToRight: Bool = true
    var duration: Double = 3.4

    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let p = timeline.date.timeIntervalSince(start) / duration
                guard p >= 0, p <= 1 else { return }
                let travel = size.width + 120
                let lead = leftToRight ? -60 + p * travel : size.width + 60 - p * travel
                let baseY = size.height * (0.65 - 0.35 * p)
                let t = timeline.date.timeIntervalSince(start)
                let ink = Color.ink.opacity(0.7 * min(1, (1 - p) * 4))
                for i in 0..<3 {
                    let rank = Double((i + 1) / 2)
                    let side: Double = i == 0 ? 0 : (i.isMultiple(of: 2) ? 1 : -1)
                    let x = lead + (leftToRight ? -1 : 1) * rank * 18
                    let y = baseY + side * rank * 9
                    let flap = sin(t * 7 + Double(i)) * 3
                    var bird = Path()
                    bird.move(to: CGPoint(x: x - 7, y: y - 1 + flap))
                    bird.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 3.5, y: y - 3.5 + flap))
                    bird.addQuadCurve(to: CGPoint(x: x + 7, y: y - 1 + flap), control: CGPoint(x: x + 3.5, y: y - 3.5 + flap))
                    context.stroke(bird, with: .color(ink), lineWidth: 1.4)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
