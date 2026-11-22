import SwiftUI

/// 小组件里的一幅小山水：天色随时辰，近山随季节，水上漂着河灯。
/// 用 Shape 画（小组件里没有动画，也不该耗电），和 App 首页同一套意思：远山淡、近山浓、水面倒影。
struct InkLandscape: View {
    var phase: Almanac.Phase
    var season: Almanac.Season
    var lanterns: Int
    /// 水面在画面里的高度（0…1，从上往下）
    var waterLine: CGFloat = 0.68
    /// 日月放在哪儿（相对位置），避开文字
    var celestial = UnitPoint(x: 0.3, y: 0.24)

    var body: some View {
        let palette = WidgetPalette(phase: phase, season: season)
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: palette.sky, startPoint: .top, endPoint: .init(x: 0.5, y: waterLine))

                // 日 / 月
                Circle()
                    .fill(palette.celestial.opacity(0.22))
                    .frame(width: h * 0.34, height: h * 0.34)
                    .blur(radius: 8)
                    .position(x: w * celestial.x, y: h * celestial.y)
                Circle()
                    .fill(palette.celestial)
                    .frame(width: h * 0.13, height: h * 0.13)
                    .position(x: w * celestial.x, y: h * celestial.y)

                // 远山到近山
                ForEach(Array(palette.mountains.enumerated()), id: \.offset) { index, color in
                    let layer = Self.layers[index]
                    Ridge(seed: layer.seed, base: waterLine - layer.lift, amplitude: layer.amplitude)
                        .fill(color)
                    // 倒影：以水线为镜，淡淡的
                    Ridge(seed: layer.seed, base: waterLine - layer.lift, amplitude: layer.amplitude)
                        .fill(color.opacity(0.35))
                        .scaleEffect(x: 1, y: -1, anchor: UnitPoint(x: 0.5, y: waterLine))
                        .mask(alignment: .top) {
                            Rectangle().padding(.top, h * waterLine)
                        }
                }

                // 水
                LinearGradient(colors: palette.water, startPoint: .top, endPoint: .bottom)
                    .frame(height: h * (1 - waterLine))
                    .offset(y: h * waterLine)
                Rectangle()
                    .fill(palette.waterline)
                    .frame(height: 0.7)
                    .offset(y: h * waterLine)
                // 几道水纹
                ForEach(0..<3, id: \.self) { k in
                    streak(k, palette: palette, size: geo.size)
                }

                // 河灯
                ForEach(0..<min(lanterns, Self.lanternSpots.count), id: \.self) { k in
                    lantern(k, palette: palette, size: geo.size)
                }
            }
        }
    }

    private func streak(_ k: Int, palette: WidgetPalette, size: CGSize) -> some View {
        let step = CGFloat(k)
        let width: CGFloat = size.width * (0.18 + 0.08 * step)
        let x: CGFloat = size.width * (0.22 + 0.27 * step)
        let y: CGFloat = size.height * (waterLine + 0.07 + 0.08 * step)
        return Capsule()
            .fill(palette.waterline.opacity(0.7))
            .frame(width: width, height: 0.8)
            .position(x: x, y: y)
    }

    private func lantern(_ k: Int, palette: WidgetPalette, size: CGSize) -> some View {
        let spot = Self.lanternSpots[k]
        let side: CGFloat = size.height * 0.11 * spot.scale
        let x: CGFloat = size.width * spot.x
        let y: CGFloat = size.height * (waterLine + (1 - waterLine) * spot.depth)
        return LanternMark(glow: palette.glow, ink: palette.lanternBase)
            .frame(width: side, height: side)
            .position(x: x, y: y)
    }

    private static let layers: [(seed: Double, lift: CGFloat, amplitude: CGFloat)] = [
        (1.3, 0.2, 0.16), (4.2, 0.1, 0.13), (7.7, 0.03, 0.09),
    ]

    /// 河灯的位置：第一盏是「青履君」的，之后点「放灯」一盏盏添上去
    private static let lanternSpots: [(x: CGFloat, depth: CGFloat, scale: CGFloat)] = [
        (0.58, 0.32, 1.0), (0.32, 0.55, 1.15), (0.8, 0.5, 1.1), (0.18, 0.28, 0.85),
        (0.46, 0.72, 1.25), (0.7, 0.2, 0.8), (0.9, 0.75, 1.2),
    ]
}

/// 一道山脊，填到画面底部（被水盖住的部分看不见）
struct Ridge: Shape {
    var seed: Double
    /// 山脚的高度（0…1，从上往下）
    var base: CGFloat
    var amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let steps = 56
        let peak = 0.25 + 0.5 * (seed * 0.37).truncatingRemainder(dividingBy: 1)
        for i in 0...steps {
            let u = Double(i) / Double(steps)
            var lift = 0.55 * sin(u * 5.1 + seed) + 0.3 * sin(u * 11.3 + seed * 2.1) + 0.15 * sin(u * 23.7 + seed * 3.7)
            lift += 0.6 * exp(-pow(u - peak, 2) / 0.02)
            let y = base - amplitude * CGFloat(lift)
            path.addLine(to: CGPoint(x: rect.minX + CGFloat(u) * rect.width, y: rect.minY + y * rect.height))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 一盏河灯：墨色的灯座，暖光的纸罩，一圈光晕
struct LanternMark: View {
    var glow: Color
    var ink: Color

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [glow.opacity(0.55), glow.opacity(0)], center: .center, startRadius: 0, endRadius: s * 0.9))
                    .frame(width: s * 1.8, height: s * 1.8)
                    .offset(y: -s * 0.15)
                Path { p in
                    // 纸罩
                    p.move(to: CGPoint(x: s * 0.28, y: s * 0.62))
                    p.addLine(to: CGPoint(x: s * 0.34, y: s * 0.18))
                    p.addLine(to: CGPoint(x: s * 0.66, y: s * 0.18))
                    p.addLine(to: CGPoint(x: s * 0.72, y: s * 0.62))
                    p.closeSubpath()
                }
                .fill(glow)
                Path { p in
                    // 灯座
                    p.move(to: CGPoint(x: s * 0.12, y: s * 0.62))
                    p.addQuadCurve(to: CGPoint(x: s * 0.88, y: s * 0.62), control: CGPoint(x: s * 0.5, y: s * 0.86))
                    p.addLine(to: CGPoint(x: s * 0.78, y: s * 0.56))
                    p.addLine(to: CGPoint(x: s * 0.22, y: s * 0.56))
                    p.closeSubpath()
                }
                .fill(ink)
                Circle()
                    .fill(Color(red: 1, green: 0.97, blue: 0.9))
                    .frame(width: s * 0.12, height: s * 0.12)
                    .position(x: s * 0.5, y: s * 0.4)
            }
            .frame(width: s, height: s)
        }
    }
}

/// 竖排文字：一字一行
struct VerticalLabel: View {
    var text: String
    var font: Font
    var spacing: CGFloat = 0

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
            }
        }
        .font(font)
    }
}

/// 朱印：两个字竖排
struct SealMark: View {
    var text: String
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
            .fill(WidgetPalette.vermilion)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: max(0.8, size * 0.04))
                    .padding(size * 0.08)
            }
            .overlay {
                VStack(spacing: -size * 0.04) {
                    ForEach(Array(text.prefix(2).enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                    }
                }
                .font(.system(size: size * 0.32, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            }
            .rotationEffect(.degrees(-6))
    }
}

/// 和 App 的 Theme 一致的颜色；天色按时辰，近山按季节
struct WidgetPalette {
    static let vermilion = Color(red: 0.784, green: 0.267, blue: 0.184)   // #C8442F

    let sky: [Color]
    let celestial: Color
    let mountains: [Color]
    let water: [Color]
    let waterline: Color
    let glow: Color
    let lanternBase: Color
    /// 文字色（夜里是浅色）
    let ink: Color
    let secondary: Color
    /// 信笺的底色
    let paper: Color
    let isNight: Bool

    init(phase: Almanac.Phase, season: Almanac.Season) {
        func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
            Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255, opacity: opacity)
        }
        let near: UInt32 = switch season {
        case .spring: 0x56684F
        case .summer: 0x3F5A45
        case .autumn: 0x6E5238
        case .winter: 0x5F6670
        }
        isNight = phase == .night
        glow = hex(0xFFC46E)
        switch phase {
        case .dawn:
            sky = [hex(0xE6D3CB), hex(0xF3E9DF)]
            celestial = hex(0xE0866A)
            mountains = [hex(0x8C8F96, 0.35), hex(0x5E636B, 0.45), hex(near, 0.7)]
            water = [hex(0x9BA3A8, 0.25), hex(0x5E6970, 0.4)]
        case .day:
            sky = [hex(0xEDE6DA), hex(0xF4F0E8)]
            celestial = hex(0xC8442F, 0.8)
            mountains = [hex(0x3A3B37, 0.14), hex(0x3A3B37, 0.24), hex(near, 0.6)]
            water = [hex(0x2E3B3A, 0.06), hex(0x2E3B3A, 0.2)]
        case .dusk:
            sky = [hex(0xE3BE98), hex(0xF1E0C8)]
            celestial = hex(0xD5603A)
            mountains = [hex(0x6B5A55, 0.3), hex(0x4A403E, 0.42), hex(near, 0.72)]
            water = [hex(0x6B5040, 0.15), hex(0x3D302A, 0.35)]
        case .night:
            sky = [hex(0x0E1218), hex(0x1B1E24)]
            celestial = hex(0xEFE6D2)
            mountains = [hex(0x2C3036, 0.7), hex(0x23272C, 0.85), hex(0x15181C)]
            water = [hex(0x0D1416, 0.85), hex(0x080B0C)]
        }
        waterline = isNight ? hex(0xEDE8DF, 0.16) : hex(0xFFFFFF, 0.55)
        lanternBase = isNight ? hex(0xEDE8DF) : hex(0x1C1A17)
        ink = isNight ? hex(0xEDE8DF) : hex(0x1C1A17)
        secondary = isNight ? hex(0x9A9388) : hex(0x6F695F)
        paper = isNight ? hex(0x1F1C17, 0.88) : hex(0xFBF8F2, 0.9)
    }
}
