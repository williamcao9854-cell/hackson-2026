import SwiftUI

/// 朱印。用于「已送别」，也用作 App 的标识。
///
/// 印章边缘做了轻微的"斑驳"处理，像真的盖在纸上。
struct SealStamp: View {
    /// 印文，建议 2～4 个字，竖排两列
    var text: String = "已送别"
    var size: CGFloat = 64
    var rotation: Angle = .degrees(-8)

    var body: some View {
        let columns = Self.columns(for: text)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(Color.vermilion)
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .strokeBorder(Color.paper.opacity(0.9), lineWidth: max(1, size * 0.03))
                .padding(size * 0.07)
            HStack(spacing: size * 0.02) {
                // 竖排、从右往左
                ForEach(Array(columns.enumerated().reversed()), id: \.offset) { _, column in
                    VStack(spacing: -size * 0.02) {
                        ForEach(Array(column.enumerated()), id: \.offset) { _, character in
                            Text(String(character))
                                .font(.system(size: size * (columns.count > 1 ? 0.26 : 0.34), weight: .heavy, design: .serif))
                        }
                    }
                }
            }
            .foregroundStyle(Color.paper)
        }
        .frame(width: size, height: size)
        .mask { SealGrain(size: size) }
        .rotationEffect(rotation)
        .accessibilityLabel(text)
    }

    /// 3 个字：右列 2 个、左列 1 个；4 个字：每列 2 个；1～2 个字：一列。
    static func columns(for text: String) -> [[Character]] {
        let chars = Array(text)
        switch chars.count {
        case 0...2: return [chars]
        case 3: return [Array(chars[0...1]), [chars[2]]]
        default: return [Array(chars[0...1]), Array(chars[2...min(3, chars.count - 1)])]
        }
    }
}

/// 印泥的颗粒感：大部分不透明，随机散布一些浅色小点。
private struct SealGrain: View {
    var size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.black))
            var rng = SeededRandom(seed: UInt64(size * 1000))
            // 在不透明底上"擦掉"一些小点，形成印泥没沾匀的斑驳感
            context.blendMode = .destinationOut
            let dots = Int(size * 1.4)
            for _ in 0..<dots {
                let r = 0.4 + rng.next() * size * 0.018
                let rect = CGRect(x: rng.next() * canvasSize.width, y: rng.next() * canvasSize.height, width: r, height: r)
                context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.2 + rng.next() * 0.45)))
            }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        SealStamp()
        SealStamp(text: "物灵", size: 44, rotation: .zero)
        SealStamp(text: "同住", size: 52, rotation: .degrees(6))
    }
    .padding(40)
    .background(PaperBackground())
}
