import SwiftUI

/// 向外扩散的墨线涟漪：寻找身边的人、等待物灵飞来时用
struct InkRipples: View {
    var rings: Int = 4
    var period: Double = 3.6
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let elapsed: Double = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                let w = Double(size.width)
                let h = Double(size.height)
                let maxRadius: Double = min(w, h) / 2
                for i in 0..<rings {
                    let offset: Double = Double(i) / Double(rings)
                    let p: Double = (elapsed / period + offset).truncatingRemainder(dividingBy: 1)
                    let r: Double = maxRadius * (0.22 + 0.78 * p)
                    let rect = CGRect(x: w / 2 - r, y: h / 2 - r, width: r * 2, height: r * 2)
                    let opacity: Double = 0.22 * (1 - p)
                    context.stroke(Path(ellipseIn: rect), with: .color(Color.ink.opacity(opacity)), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 传灵的三步：写下 → 盖章 → 传出
struct RelaySteps: View {
    /// 1、2、3
    var current: Int
    private let titles = ["写下", "盖章", "传出"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                let step = index + 1
                let reached: Bool = step <= current
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(reached ? Color.vermilion : Color.clear)
                            .overlay { Circle().strokeBorder(reached ? Color.clear : Color.ink.opacity(0.25), lineWidth: 1) }
                        Text("\(step)")
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundStyle(reached ? Color.paper : Color.inkSecondary)
                    }
                    .frame(width: 20, height: 20)
                    Text(titles[index])
                        .font(.system(size: 13, weight: step == current ? .semibold : .regular))
                        .foregroundStyle(reached ? Color.ink : Color.inkSecondary)
                }
                if index < 2 {
                    Rectangle()
                        .fill(step < current ? Color.vermilion.opacity(0.6) : Color.hairline)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                }
            }
        }
        .animation(.wlCalm, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(current) 步，共 3 步：\(titles[max(0, min(2, current - 1))])")
    }
}
