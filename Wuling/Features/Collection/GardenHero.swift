import SwiftData
import SwiftUI

/// 首页的园林：山水之间，同住的物灵以立牌的样子站在岸边。
/// 送别的物灵是水上的河灯，传出去的是远天的鸿雁。点一下岸边的物灵，进入它的详情。
struct GardenHero: View {
    var topInset: CGFloat
    var living: [Spirit]
    var lanterns: Int
    var geese: Int

    private let maxFigures = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                LandscapeHeader(topInset: topInset, lanterns: lanterns, geese: geese)

                let shown = Array(living.prefix(maxFigures))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, spirit in
                    let placement = Self.placement(index: index, count: shown.count, in: geo.size)
                    NavigationLink {
                        SpiritDetailView(spirit: spirit)
                    } label: {
                        GardenFigure(spirit: spirit, height: placement.height)
                    }
                    .buttonStyle(.plain)
                    .position(placement.center)
                    .zIndex(placement.depth)
                }

                if living.count > maxFigures {
                    Text("还有 \(living.count - maxFigures) 位在图鉴里")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.clear, in: Capsule())
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.97)
                }

                if living.isEmpty {
                    VStack(spacing: 4) {
                        Text("园林里还空着")
                            .font(.system(size: 14, weight: .semibold))
                        Text("去「遇见」一件旧物，它会住在这里")
                            .font(.system(size: 12))
                            .opacity(0.75)
                    }
                    .foregroundStyle(.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.86)
                }
            }
        }
    }

    /// 前后两排错落站开：后排小、略高，前排大、靠下
    static func placement(index: Int, count: Int, in size: CGSize) -> (center: CGPoint, height: CGFloat, depth: Double) {
        let slots = CGFloat(max(count, 1))
        let unitX: CGFloat = 0.14 + 0.72 * (CGFloat(index) + 0.5) / slots
        let backRow: Bool = count > 2 && !index.isMultiple(of: 2)
        let unitY: CGFloat = backRow ? 0.84 : 0.94
        let scale: CGFloat = backRow ? 0.8 : 1
        let height: CGFloat = min(110, size.height * 0.16) * scale
        let center = CGPoint(x: unitX * size.width, y: unitY * size.height - height / 2)
        return (center, height, backRow ? 0 : 1)
    }
}

/// 岸边的一个物灵：小立牌 + 名字
private struct GardenFigure: View {
    let spirit: Spirit
    var height: CGFloat
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 2) {
            if let data = spirit.figureImageData ?? spirit.stickerImageData, let image = UIImage(data: data) {
                StandeeView(figure: image, interactive: false)
                    .frame(width: height * 0.9, height: height)
            } else {
                SpiritArtView(data: spirit.spiritImageData, contentMode: .fill)
                    .frame(width: height * 0.7, height: height * 0.7)
                    .clipShape(Circle())
                    .frame(height: height)
            }
            Text(spirit.name)
                .font(.system(size: 11, weight: .semibold, design: .serif))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .glassEffect(.clear, in: Capsule())
        }
        .foregroundStyle(.ink)
        .onAppear { FigureCache.ensureFigure(for: spirit, in: modelContext) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spirit.name)，\(spirit.objectName)，同住")
        .accessibilityAddTraits(.isButton)
    }
}
