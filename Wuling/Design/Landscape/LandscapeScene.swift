import SwiftUI

/// 一幅水墨山水的"配方"：由时辰、节气、深浅色模式，以及用户的图鉴（河灯、鸿雁）决定。
///
/// 画法参考传统山水的层次：远山淡、近山浓，山脚化入雾中留白；
/// 配色取低饱和的青绿与墨色，白天像《千里江山图》褪了色的青绿，夜里是一纸墨色。
struct LandscapeScene {
    var phase: DayPhase
    var season: SolarTerm.Season
    /// 已送别的物灵：化作水面上的河灯
    var lanterns: Int
    /// 已传出的物灵：化作远天的鸿雁
    var geese: Int

    init(date: Date, isDark: Bool, lanterns: Int, geese: Int) {
        phase = isDark ? .night : DayPhase(date: date)
        season = SolarTerm(date: date).season
        self.lanterns = lanterns
        self.geese = geese
    }

    var isNight: Bool { phase == .night }

    // MARK: - 配色

    struct Palette {
        var skyTop: Color
        var skyBottom: Color
        var mountains: [Color]   // 远 → 近
        var celestial: Color
        var celestialGlow: Color
        var ink: Color           // 柳枝、鸿雁、涟漪
    }

    var palette: Palette {
        func c(_ hex: UInt32, _ opacity: Double = 1) -> Color { Color(uiColor: UIColor(hex: hex)).opacity(opacity) }
        // 季节给山色一点偏移：春夏偏青绿，秋偏赭，冬偏灰
        let seasonal: [UInt32] = switch season {
        case .spring: [0x8FA9A0, 0x5E8279, 0x3C5F57]
        case .summer: [0x86A39A, 0x4F7A70, 0x2F574F]
        case .autumn: [0xA8A08C, 0x857A62, 0x5C5242]
        case .winter: [0xA3A8AB, 0x7C8387, 0x565D62]
        }
        switch phase {
        case .dawn:
            return Palette(skyTop: c(0xE8DCCB), skyBottom: c(0xF4ECE1),
                           mountains: seasonal.map { c($0, 0.75) },
                           celestial: c(0xE7A383, 0.9), celestialGlow: c(0xF1C6A8, 0.45), ink: c(0x3A3631))
        case .day:
            return Palette(skyTop: c(0xDDE5E2), skyBottom: c(0xF4F0E8),
                           mountains: seasonal.map { c($0) },
                           celestial: c(0xFFFFFF, 0.85), celestialGlow: c(0xFFFFFF, 0.5), ink: c(0x2E2B27))
        case .dusk:
            return Palette(skyTop: c(0xD9BBA6), skyBottom: c(0xF2E2D2),
                           mountains: [c(0x9C8E92), c(0x6F6269), c(0x4B4049)],
                           celestial: c(0xC8442F, 0.92), celestialGlow: c(0xE8906F, 0.35), ink: c(0x3A2F2C))
        case .night:
            return Palette(skyTop: c(0x10131A), skyBottom: c(0x23262D),
                           mountains: [c(0x30343C), c(0x22262D), c(0x171A20)],
                           celestial: c(0xEDE8DF, 0.95), celestialGlow: c(0xEDE8DF, 0.18), ink: c(0xB8B2A8))
        }
    }

    /// 日 / 月的位置（相对尺寸），月洞门玻璃也放在这里
    func celestialPosition(in size: CGSize) -> CGPoint {
        let unit: CGPoint = switch phase {
        case .dawn: CGPoint(x: 0.34, y: 0.46)
        case .day: CGPoint(x: 0.62, y: 0.30)
        case .dusk: CGPoint(x: 0.6, y: 0.44)
        case .night: CGPoint(x: 0.62, y: 0.3)
        }
        return CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }

    var celestialRadius: CGFloat { phase == .day ? 18 : 22 }

    // MARK: - 绘制

    /// - t: 动画时间（秒）；减弱动态效果时恒为 0
    /// - tilt: 设备倾斜（-1...1），用于景深错动
    func draw(_ context: GraphicsContext, size: CGSize, t: Double, tilt: CGSize) {
        var context = context
        let p = palette
        let w = size.width, h = size.height
        let waterY = h * 0.84

        // 天空
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [p.skyTop, p.skyBottom]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: waterY)))

        if isNight { drawStars(context, size: size, t: t) }
        drawCelestial(context, size: size, tilt: tilt)
        if geese > 0 { drawGeese(context, size: size, t: t, tilt: tilt) }

        // 三层山：远淡近浓，山脚化入雾中
        let layers: [(base: Double, amp: Double, seed: Double, depth: Double)] = [
            (0.62, 0.42, 1.3, 4), (0.72, 0.32, 4.2, 8), (0.83, 0.22, 7.7, 13),
        ]
        for (i, layer) in layers.enumerated() {
            var ctx = context
            ctx.translateBy(x: tilt.width * layer.depth, y: tilt.height * layer.depth * 0.5)
            let path = ridgePath(size: size, base: layer.base * h, amplitude: layer.amp * h, seed: layer.seed, drift: t * 0.002 * Double(i + 1))
            let top = (layer.base - layer.amp) * h
            ctx.fill(path, with: .linearGradient(Gradient(colors: [p.mountains[i], p.skyBottom]),
                                                 startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: layer.base * h + h * 0.06)))
            if season == .winter && i < 2 && !isNight {
                // 山顶积雪
                ctx.fill(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]),
                                                     startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + layer.amp * h * 0.45)))
            }
            if i == 1 { drawMist(context, size: size, t: t, y: layer.base * h - h * 0.02) }
        }

        drawWater(context, size: size, t: t, waterY: waterY, tilt: tilt)
        if lanterns > 0 { drawLanterns(context, size: size, t: t, waterY: waterY, tilt: tilt) }
        drawWillow(context, size: size, t: t, tilt: tilt)
        drawSeasonalParticles(context, size: size, t: t, tilt: tilt)
    }

    // MARK: 山

    /// 叠加几组正弦波，再做一次幂次让山峰更尖，接近水墨山的轮廓
    static func ridgeHeight(_ x: Double, seed: Double) -> Double {
        let a = sin(x * 2.1 + seed) * 0.5 + sin(x * 4.7 + seed * 1.7) * 0.27
            + sin(x * 9.3 + seed * 2.3) * 0.13 + sin(x * 17.0 + seed * 3.1) * 0.06
            + sin(x * 31.0 + seed * 4.3) * 0.025
        return pow(max(0, (a + 0.985) / 1.97), 2.1)
    }

    private func ridgePath(size: CGSize, base: Double, amplitude: Double, seed: Double, drift: Double) -> Path {
        var path = Path()
        let steps = 90
        // 左右各多画一点，倾斜错动时不露边
        let left = -30.0, right = size.width + 30
        path.move(to: CGPoint(x: left, y: size.height))
        for i in 0...steps {
            let x = left + (right - left) * Double(i) / Double(steps)
            let y = base - amplitude * Self.ridgeHeight(x / size.width * 3.2 + drift, seed: seed)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: right, y: size.height))
        path.closeSubpath()
        return path
    }

    private func drawMist(_ context: GraphicsContext, size: CGSize, t: Double, y: Double) {
        var context = context
        let color = palette.skyBottom
        for i in 0..<3 {
            let width = size.width * (0.7 + Double(i) * 0.2)
            let phase = (t / (70 + Double(i) * 25) + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let x = -width + phase * (size.width + width * 2) - width / 2
            let rect = CGRect(x: x, y: y + Double(i) * 10 - 12, width: width, height: 34)
            context.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [color.opacity(0.75), color.opacity(0)]),
                center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: width / 2))
        }
    }

    // MARK: 日月星

    private func drawCelestial(_ context: GraphicsContext, size: CGSize, tilt: CGSize) {
        var context = context
        let p = palette
        let center = celestialPosition(in: size)
        let c = CGPoint(x: center.x + tilt.width * 2, y: center.y + tilt.height * 1)
        let r = celestialRadius
        let glow = r * 3.4
        context.fill(Path(ellipseIn: CGRect(x: c.x - glow, y: c.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [p.celestialGlow, p.celestialGlow.opacity(0)]),
                                           center: c, startRadius: r * 0.8, endRadius: glow))
        context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(p.celestial))
    }

    private func drawStars(_ context: GraphicsContext, size: CGSize, t: Double) {
        var context = context
        var rng = SeededRandom(seed: 77)
        for _ in 0..<40 {
            let x = rng.next() * size.width
            let y = rng.next() * size.height * 0.5
            let twinkle = 0.35 + 0.35 * sin(t * (0.8 + rng.next() * 1.5) + rng.next() * 6)
            let r = 0.6 + rng.next() * 0.9
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(twinkle)))
        }
    }

    // MARK: 水

    private func drawWater(_ context: GraphicsContext, size: CGSize, t: Double, waterY: Double, tilt: CGSize) {
        let p = palette
        var ctx = context
        ctx.translateBy(x: tilt.width * 13, y: 0)
        let rect = CGRect(x: -30, y: waterY, width: size.width + 60, height: size.height - waterY)
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [p.skyBottom, p.skyTop.opacity(isNight ? 1 : 0.6)]),
                                                    startPoint: CGPoint(x: 0, y: waterY), endPoint: CGPoint(x: 0, y: size.height)))
        // 涟漪：一排排缓慢移动的短线
        var rng = SeededRandom(seed: 12)
        for row in 0..<7 {
            let y = waterY + 6 + Double(row) * (size.height - waterY) / 7.5
            for _ in 0..<5 {
                let length = 14 + rng.next() * 36
                let speed = 4 + rng.next() * 6
                let x = (rng.next() * size.width + t * speed).truncatingRemainder(dividingBy: size.width + 60) - 30
                var line = Path()
                line.move(to: CGPoint(x: x, y: y))
                line.addLine(to: CGPoint(x: x + length, y: y))
                ctx.stroke(line, with: .color(p.ink.opacity(isNight ? 0.18 : 0.1)), lineWidth: 0.8)
            }
        }
        // 日月倒影：一串闪动的短横
        let c = celestialPosition(in: size)
        for i in 0..<6 {
            let y = waterY + 5 + Double(i) * 6
            let width = (celestialRadius * 1.6) * (1 - Double(i) * 0.12) * (0.75 + 0.25 * sin(t * 2 + Double(i)))
            var line = Path()
            line.move(to: CGPoint(x: c.x - width / 2, y: y))
            line.addLine(to: CGPoint(x: c.x + width / 2, y: y))
            ctx.stroke(line, with: .color(p.celestial.opacity(0.35 - Double(i) * 0.05)), lineWidth: 1.4)
        }
    }

    /// 河灯：每一盏是一个送别了的物灵
    private func drawLanterns(_ context: GraphicsContext, size: CGSize, t: Double, waterY: Double, tilt: CGSize) {
        var ctx = context
        ctx.translateBy(x: tilt.width * 13, y: 0)
        var rng = SeededRandom(seed: 404)
        let count = min(lanterns, 8)
        for i in 0..<count {
            let speed = 3 + rng.next() * 4
            let x = (rng.next() * size.width + t * speed).truncatingRemainder(dividingBy: size.width + 40) - 20
            let y = waterY + 12 + Double(i % 3) * 9 + sin(t * 1.3 + Double(i)) * 1.2
            let glow = 16.0
            ctx.fill(Path(ellipseIn: CGRect(x: x - glow, y: y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.95, green: 0.72, blue: 0.43).opacity(0.45), .clear]),
                                           center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glow))
            let body = CGRect(x: x - 3.5, y: y - 3, width: 7, height: 5.5)
            ctx.fill(Path(roundedRect: body, cornerRadius: 1.5), with: .color(Color(uiColor: UIColor(hex: 0xC8442F))))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 6.5, width: 2.4, height: 3.5)),
                     with: .color(Color(red: 1, green: 0.85, blue: 0.55)))
        }
    }

    // MARK: 鸿雁

    /// 鸿雁：每一只是一个传出去的物灵，排成人字缓缓飞过远天
    private func drawGeese(_ context: GraphicsContext, size: CGSize, t: Double, tilt: CGSize) {
        var context = context
        let p = palette
        let count = min(geese, 7)
        let cycle = (t / 48).truncatingRemainder(dividingBy: 1)
        let leadX = -80 + cycle * (size.width + 160) + tilt.width * 3
        let leadY = size.height * 0.2 + sin(t * 0.3) * 4
        for i in 0..<count {
            let rank = Double((i + 1) / 2)
            let side: Double = i == 0 ? 0 : (i.isMultiple(of: 2) ? 1 : -1)
            let x = leadX - rank * 13
            let y = leadY + side * rank * 7
            let flap = sin(t * 5 + Double(i)) * 2.2
            var bird = Path()
            bird.move(to: CGPoint(x: x - 5, y: y - 1 + flap))
            bird.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 2.5, y: y - 2.5 + flap))
            bird.addQuadCurve(to: CGPoint(x: x + 5, y: y - 1 + flap), control: CGPoint(x: x + 2.5, y: y - 2.5 + flap))
            context.stroke(bird, with: .color(p.ink.opacity(0.6)), lineWidth: 1.1)
        }
    }

    // MARK: 柳

    /// 左上角伸出一根柳枝，柳条沿枝垂下，随风轻摆。冬天只剩枝条，春夏有叶，秋天叶子泛黄。
    private func drawWillow(_ context: GraphicsContext, size: CGSize, t: Double, tilt: CGSize) {
        let p = palette
        var ctx = context
        ctx.translateBy(x: tilt.width * 20, y: tilt.height * 6)
        let leafColor: Color? = switch season {
        case .spring: Color(red: 0.55, green: 0.66, blue: 0.45)
        case .summer: Color(red: 0.36, green: 0.52, blue: 0.38)
        case .autumn: Color(red: 0.78, green: 0.62, blue: 0.3)
        case .winter: nil
        }
        let inkOpacity = isNight ? 0.55 : 0.42
        func bezier(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
            CGPoint(x: (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * c.x + u * u * b.x,
                    y: (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * c.y + u * u * b.y)
        }

        // 主枝：从画面左上角外拱进来，微微上扬
        let branchStart = CGPoint(x: -12, y: size.height * 0.02)
        let branchEnd = CGPoint(x: size.width * 0.34, y: size.height * 0.05)
        let branchControl = CGPoint(x: size.width * 0.16, y: -size.height * 0.04)
        var branch = Path()
        branch.move(to: branchStart)
        branch.addQuadCurve(to: branchEnd, control: branchControl)
        ctx.stroke(branch, with: .color(p.ink.opacity(inkOpacity + 0.1)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        // 柳条：从主枝上垂下，越靠近枝梢越短
        var rng = SeededRandom(seed: 31)
        let strands = 15
        for i in 0..<strands {
            let u = 0.08 + 0.9 * Double(i) / Double(strands - 1)
            let origin = bezier(branchStart, branchControl, branchEnd, u)
            let length = size.height * (0.48 - u * 0.26) * (0.8 + rng.next() * 0.4)
            let sway = sin(t * 0.8 + Double(i) * 0.5) * (6 + length * 0.05)
            let end = CGPoint(x: origin.x + 10 + sway, y: origin.y + length)
            let control = CGPoint(x: origin.x - 6 + sway * 0.2, y: origin.y + length * 0.45)

            // 上粗下细：分三段，越往下越细越淡
            for segment in 0..<3 {
                let u0 = Double(segment) / 3, u1 = Double(segment + 1) / 3
                var piece = Path()
                piece.move(to: bezier(origin, control, end, u0))
                for k in 1...6 {
                    piece.addLine(to: bezier(origin, control, end, u0 + (u1 - u0) * Double(k) / 6))
                }
                ctx.stroke(piece, with: .color(p.ink.opacity(inkOpacity * (1 - Double(segment) * 0.22))),
                           style: StrokeStyle(lineWidth: 1.3 - Double(segment) * 0.35, lineCap: .round))
            }

            guard let leafColor else { continue }
            for k in 2..<16 {
                let point = bezier(origin, control, end, Double(k) / 16)
                let side: Double = k.isMultiple(of: 2) ? 1 : -1
                var leafContext = ctx
                leafContext.translateBy(x: point.x + side * 1.6, y: point.y)
                leafContext.rotate(by: .degrees(side * 28))
                leafContext.fill(Path(ellipseIn: CGRect(x: -1.1, y: -3, width: 2.2, height: 6)),
                                 with: .color(leafColor.opacity(isNight ? 0.45 : 0.8)))
            }
        }
    }

    // MARK: 季节

    private func drawSeasonalParticles(_ context: GraphicsContext, size: CGSize, t: Double, tilt: CGSize) {
        var ctx = context
        ctx.translateBy(x: tilt.width * 10, y: tilt.height * 4)
        var rng = SeededRandom(seed: 2026)
        let w = size.width + 40, h = size.height + 20

        switch season {
        case .winter:
            let flake = isNight ? Color.white.opacity(0.85) : Color(red: 0.56, green: 0.61, blue: 0.64).opacity(0.55)
            for _ in 0..<46 {
                let speed = 10 + rng.next() * 18
                let x0 = rng.next() * w, y0 = rng.next() * h
                let y = (y0 + t * speed).truncatingRemainder(dividingBy: h) - 10
                let x = (x0 + sin(t * 0.6 + x0) * 12).truncatingRemainder(dividingBy: w) - 20
                let r = 0.9 + rng.next() * 1.5
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(flake))
            }
        case .spring:
            let petal = Color(red: 0.91, green: 0.66, blue: 0.66).opacity(0.8)
            for _ in 0..<20 {
                let speed = 14 + rng.next() * 14
                let x0 = rng.next() * w, y0 = rng.next() * h, spin = rng.next() * 6
                let y = (y0 + t * speed).truncatingRemainder(dividingBy: h) - 10
                let x = (x0 + t * speed * 0.6).truncatingRemainder(dividingBy: w) - 20
                var c = ctx
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(t * 1.4 + spin))
                c.fill(Path(ellipseIn: CGRect(x: -3, y: -1.6, width: 6, height: 3.2)), with: .color(petal))
            }
        case .autumn:
            let leaf = Color(red: 0.83, green: 0.64, blue: 0.24).opacity(0.85)
            for _ in 0..<15 {
                let speed = 12 + rng.next() * 12
                let x0 = rng.next() * w, y0 = rng.next() * h, spin = rng.next() * 6
                let y = (y0 + t * speed).truncatingRemainder(dividingBy: h) - 10
                let x = (x0 + sin(t * 0.8 + spin) * 18 + t * 4).truncatingRemainder(dividingBy: w) - 20
                var c = ctx
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(sin(t + spin) * 1.2))
                // 银杏叶：一把小扇子
                var fan = Path()
                fan.move(to: .zero)
                fan.addArc(center: .zero, radius: 5, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                fan.closeSubpath()
                c.fill(fan, with: .color(leaf))
            }
        case .summer:
            guard isNight else { return }
            for _ in 0..<18 {
                let x0 = rng.next() * size.width, y0 = size.height * (0.45 + rng.next() * 0.45), phase = rng.next() * 6
                let x = x0 + sin(t * 0.5 + phase) * 14
                let y = y0 + cos(t * 0.4 + phase) * 8
                let blink = max(0, sin(t * 1.6 + phase))
                let glow = 7.0
                ctx.fill(Path(ellipseIn: CGRect(x: x - glow, y: y - glow, width: glow * 2, height: glow * 2)),
                         with: .radialGradient(Gradient(colors: [Color(red: 0.9, green: 0.95, blue: 0.6).opacity(0.6 * blink), .clear]),
                                               center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glow))
            }
        }
    }
}
