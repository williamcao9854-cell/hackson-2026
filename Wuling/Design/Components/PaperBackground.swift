import SwiftUI

/// 和纸背景：底色 + 极淡的纤维纹理。
/// 纹理用固定种子生成，每次绘制都一样，不会闪烁。
struct PaperBackground: View {
    var color: Color = .paper

    var body: some View {
        color
            .overlay {
                PaperFibers()
                    .drawingGroup()
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }
}

private struct PaperFibers: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 20261121)
            let fiberColor: Color = colorScheme == .dark ? .white : Color(red: 0.42, green: 0.35, blue: 0.25)
            let count = Int(size.width * size.height / 900)
            for _ in 0..<count {
                let x = rng.next() * size.width
                let y = rng.next() * size.height
                let length = 4 + rng.next() * 14
                let angle = rng.next() * .pi
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addQuadCurve(
                    to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                    control: CGPoint(x: x + cos(angle + 0.5) * length * 0.5, y: y + sin(angle + 0.5) * length * 0.5)
                )
                let opacity = 0.025 + rng.next() * 0.04
                context.stroke(path, with: .color(fiberColor.opacity(opacity)), lineWidth: 0.6)
            }
        }
    }
}

/// 简单的确定性随机数（线性同余），用于纹理和粒子。
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    /// 0..<1
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

#Preview {
    PaperBackground()
}
