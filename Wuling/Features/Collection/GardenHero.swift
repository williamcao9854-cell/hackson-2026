import SwiftData
import SwiftUI

/// 首页的园林：山水之间，同住的物灵以立牌的样子站在岸边。
/// 送别的物灵是水上的河灯，传出去的是远天的鸿雁。点一下岸边的物灵，进入它的详情。
struct GardenHero: View {
    var topInset: CGFloat
    var living: [Spirit]
    var lanterns: Int
    var geese: Int
    /// 整个图鉴本来就空着时，下方已有空态引导，岸边不再重复叠一块提示
    var showEmptyHint: Bool = true
    /// 轻点节气题签：换景
    var onChangeScene: (() -> Void)? = nil

    private let maxFigures = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                LandscapeHeader(topInset: topInset, lanterns: lanterns, geese: geese, onChangeScene: onChangeScene)

                // 岸：物灵站在这里，而不是飘在山腰上
                ShoreGround()
                    .frame(height: geo.size.height * 0.24)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)

                let shown = Array(living.prefix(maxFigures))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, spirit in
                    let placement = Self.placement(index: index, count: shown.count, in: geo.size)
                    NavigationLink {
                        SpiritDetailView(spirit: spirit)
                    } label: {
                        GardenFigure(spirit: spirit, height: placement.height, isBackRow: placement.isBackRow)
                    }
                    .buttonStyle(.plain)
                    .position(placement.center)
                    .zIndex(placement.isBackRow ? 0 : 1)
                }

                if living.count > maxFigures {
                    Text("还有 \(living.count - maxFigures) 位在图鉴里")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.clear, in: Capsule())
                        .position(x: geo.size.width / 2, y: geo.size.height - 14)
                }

                if living.isEmpty && showEmptyHint {
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

    /// 前排三位站在岸的前沿，大一些；后排站在它们之间、靠后，小一些。
    static func placement(index: Int, count: Int, in size: CGSize) -> (center: CGPoint, height: CGFloat, isBackRow: Bool) {
        let frontCount = min(count, 3)
        let backCount = max(0, count - 3)
        let isBackRow = index >= 3
        let slot = isBackRow ? index - 3 : index
        let slots = CGFloat(isBackRow ? backCount : frontCount)

        let frontHeight: CGFloat = min(150, size.height * 0.22)
        let height: CGFloat = isBackRow ? frontHeight * 0.72 : frontHeight
        // 后排落在前排两两之间
        let spread: CGFloat = isBackRow ? 0.56 : 0.72
        let start: CGFloat = (1 - spread) / 2
        let unitX: CGFloat = start + spread * (CGFloat(slot) + 0.5) / max(slots, 1)
        let footY: CGFloat = isBackRow ? size.height * 0.86 : size.height * 0.97
        let center = CGPoint(x: unitX * size.width, y: footY - height / 2)
        return (center, height, isBackRow)
    }
}

/// 一道水墨画的岸：起伏的岸线、淡墨晕开的地面、几块石头和几笔芦苇。
private struct ShoreGround: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let w = Double(size.width)
            let h = Double(size.height)
            let ink = colorScheme == .dark ? Color.white : Color(red: 0.22, green: 0.2, blue: 0.17)

            // 岸线：一条缓缓起伏的曲线
            var bank = Path()
            bank.move(to: CGPoint(x: 0, y: h * 0.32))
            let steps = 40
            for i in 0...steps {
                let x: Double = w * Double(i) / Double(steps)
                let wave: Double = sin(Double(i) * 0.45) * 5 + sin(Double(i) * 1.3) * 2
                bank.addLine(to: CGPoint(x: x, y: h * 0.3 + wave))
            }
            bank.addLine(to: CGPoint(x: w, y: h))
            bank.addLine(to: CGPoint(x: 0, y: h))
            bank.closeSubpath()
            let ground = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [ink.opacity(0.10), ink.opacity(0.04), Color.paper.opacity(0.0)]),
                startPoint: CGPoint(x: 0, y: h * 0.28), endPoint: CGPoint(x: 0, y: h))
            context.fill(bank, with: ground)

            // 岸线的墨痕：一笔淡墨描边
            var edge = Path()
            edge.move(to: CGPoint(x: 0, y: h * 0.32))
            for i in 0...steps {
                let x: Double = w * Double(i) / Double(steps)
                let wave: Double = sin(Double(i) * 0.45) * 5 + sin(Double(i) * 1.3) * 2
                edge.addLine(to: CGPoint(x: x, y: h * 0.3 + wave))
            }
            context.stroke(edge, with: .color(ink.opacity(0.18)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

            // 石头：几块扁圆的淡墨
            let stones: [(x: Double, y: Double, rx: Double, ry: Double)] = [
                (0.06, 0.52, 22, 9), (0.11, 0.6, 12, 5), (0.9, 0.48, 26, 10), (0.95, 0.58, 13, 6), (0.52, 0.86, 16, 5),
            ]
            for stone in stones {
                let rect = CGRect(x: stone.x * w - stone.rx, y: stone.y * h - stone.ry, width: stone.rx * 2, height: stone.ry * 2)
                context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.13)))
                let highlight = CGRect(x: stone.x * w - stone.rx * 0.6, y: stone.y * h - stone.ry * 0.9, width: stone.rx * 0.9, height: stone.ry * 0.5)
                context.fill(Path(ellipseIn: highlight), with: .color(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.25)))
            }

            // 芦苇：左右两丛细笔
            let reeds: [(x: Double, lean: Double)] = [(0.03, 6), (0.045, 10), (0.06, 3), (0.94, -7), (0.955, -3), (0.97, -10)]
            for reed in reeds {
                var stalk = Path()
                let baseX = reed.x * w
                let baseY = h * 0.5
                stalk.move(to: CGPoint(x: baseX, y: baseY))
                stalk.addQuadCurve(to: CGPoint(x: baseX + reed.lean, y: baseY - h * 0.42),
                                   control: CGPoint(x: baseX + reed.lean * 0.2, y: baseY - h * 0.2))
                context.stroke(stalk, with: .color(ink.opacity(0.28)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
    }
}

/// 岸边的一个物灵：小立牌 + 脚下的影子 + 名字
private struct GardenFigure: View {
    let spirit: Spirit
    var height: CGFloat
    var isBackRow: Bool
    @Environment(\.modelContext) private var modelContext
    /// 解码好的立牌图：只在图片变化时解码一次，并且在后台线程
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            if let image {
                StandeeView(figure: image, interactive: false)
                    .frame(width: height * 0.85, height: height)
            } else {
                SpiritArtView(data: spirit.spiritImageData, contentMode: .fill, maxDimension: 300)
                    .frame(width: height * 0.7, height: height * 0.7)
                    .clipShape(Circle())
                    .frame(height: height)
            }
            Text(spirit.name)
                .font(.system(size: isBackRow ? 11 : 13, weight: .semibold, design: .serif))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .glassEffect(.clear, in: Capsule())
        }
        .foregroundStyle(.ink)
        .opacity(isBackRow ? 0.92 : 1)
        .onAppear { FigureCache.ensureFigure(for: spirit, in: modelContext) }
        .task(id: spirit.figureImageData?.count ?? spirit.stickerImageData?.count ?? 0) {
            let data = spirit.figureImageData ?? spirit.stickerImageData
            image = await ImageDecoding.decode(data, maxDimension: 360)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spirit.name)，\(spirit.objectName)，同住")
        .accessibilityAddTraits(.isButton)
    }
}
