import SwiftUI

/// 和纸背景：底色 + 极淡的纤维纹理。
/// 纹理用固定种子生成，每次绘制都一样，不会闪烁。
struct PaperBackground: View {
    var color: Color = .paper

    var body: some View {
        color
            .overlay {
                PaperFibers()
            }
            .ignoresSafeArea()
    }
}

/// 纸的纤维：几百根细短的曲线。按深浅分成四组，每组拼成一条 Path 一次画完（4 次绘制，而不是几百次）。
struct PaperFibers: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 20261121)
            let fiberColor: Color = colorScheme == .dark ? .white : Color(red: 0.42, green: 0.35, blue: 0.25)
            let count = Int(size.width * size.height / 1400)
            var groups: [Path] = [Path(), Path(), Path(), Path()]
            for _ in 0..<count {
                let x: Double = rng.next() * Double(size.width)
                let y: Double = rng.next() * Double(size.height)
                let length: Double = 4 + rng.next() * 14
                let angle: Double = rng.next() * Double.pi
                let opacity: Double = 0.025 + rng.next() * 0.04
                let bucket: Int = min(3, Int((opacity - 0.025) / 0.01))
                let endX: Double = x + cos(angle) * length
                let endY: Double = y + sin(angle) * length
                let controlX: Double = x + cos(angle + 0.5) * length * 0.5
                let controlY: Double = y + sin(angle + 0.5) * length * 0.5
                groups[bucket].move(to: CGPoint(x: x, y: y))
                groups[bucket].addQuadCurve(to: CGPoint(x: endX, y: endY), control: CGPoint(x: controlX, y: controlY))
            }
            for index in 0..<groups.count {
                let opacity: Double = 0.03 + Double(index) * 0.01
                context.stroke(groups[index], with: .color(fiberColor.opacity(opacity)), lineWidth: 0.6)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
