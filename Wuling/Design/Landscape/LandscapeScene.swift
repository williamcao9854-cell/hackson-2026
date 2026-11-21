import SwiftUI

/// 一幅水墨山水的"配方"：由时辰、节气、深浅色模式，以及用户的图鉴（河灯、鸿雁）决定。
///
/// 画法参考传统山水的层次：远山淡、近山浓，山脚化入雾中留白；
/// 配色取低饱和的青绿与墨色，白天像《千里江山图》褪了色的青绿，夜里是一纸墨色。
///
/// 实现说明：所有计算统一用 Double，只在最后构造 CGPoint / CGRect 时转换。
/// 混用 CGFloat 和 Double 会让编译器在类型推断上耗时过长（"unable to type-check this expression in reasonable time"）。
struct LandscapeScene {
    var phase: DayPhase
    var season: SolarTerm.Season
    /// 已送别的物灵：化作水面上的河灯
    var lanterns: Int
    /// 已传出的物灵：化作远天的鸿雁
    var geese: Int
    /// 是否画日月。作为其他页面的淡背景时不画：日月会透到内容后面，像一块污渍
    var showsCelestial: Bool

    init(date: Date, isDark: Bool, lanterns: Int, geese: Int, showsCelestial: Bool = true) {
        phase = isDark ? .night : DayPhase(date: date)
        season = SolarTerm(date: date).season
        self.lanterns = lanterns
        self.geese = geese
        self.showsCelestial = showsCelestial
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

    private static func color(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(uiColor: UIColor(hex: hex)).opacity(opacity)
    }

    var palette: Palette {
        let c = Self.color
        // 季节给山色一点偏移：春夏偏青绿，秋偏赭，冬偏灰
        let seasonal: [UInt32]
        switch season {
        case .spring: seasonal = [0x8FA9A0, 0x5E8279, 0x3C5F57]
        case .summer: seasonal = [0x86A39A, 0x4F7A70, 0x2F574F]
        case .autumn: seasonal = [0xA8A08C, 0x857A62, 0x5C5242]
        case .winter: seasonal = [0xA3A8AB, 0x7C8387, 0x565D62]
        }
        switch phase {
        case .dawn:
            let mountains: [Color] = seasonal.map { c($0, 0.75) }
            return Palette(skyTop: c(0xE8DCCB, 1), skyBottom: c(0xF4ECE1, 1), mountains: mountains,
                           celestial: c(0xE7A383, 0.9), celestialGlow: c(0xF1C6A8, 0.45), ink: c(0x3A3631, 1))
        case .day:
            let mountains: [Color] = seasonal.map { c($0, 1) }
            return Palette(skyTop: c(0xDDE5E2, 1), skyBottom: c(0xF4F0E8, 1), mountains: mountains,
                           celestial: c(0xFFFFFF, 0.85), celestialGlow: c(0xFFFFFF, 0.5), ink: c(0x2E2B27, 1))
        case .dusk:
            let mountains: [Color] = [c(0x9C8E92, 1), c(0x6F6269, 1), c(0x4B4049, 1)]
            return Palette(skyTop: c(0xD9BBA6, 1), skyBottom: c(0xF2E2D2, 1), mountains: mountains,
                           celestial: c(0xD0664E, 0.72), celestialGlow: c(0xE8A080, 0.3), ink: c(0x3A2F2C, 1))
        case .night:
            let mountains: [Color] = [c(0x30343C, 1), c(0x22262D, 1), c(0x171A20, 1)]
            return Palette(skyTop: c(0x10131A, 1), skyBottom: c(0x23262D, 1), mountains: mountains,
                           celestial: c(0xEDE8DF, 0.95), celestialGlow: c(0xEDE8DF, 0.18), ink: c(0xB8B2A8, 1))
        }
    }

    /// 日 / 月的相对位置
    private var celestialUnit: (x: Double, y: Double) {
        switch phase {
        case .dawn: return (0.34, 0.46)
        case .day: return (0.62, 0.30)
        case .dusk: return (0.60, 0.44)
        case .night: return (0.62, 0.30)
        }
    }

    /// 日 / 月的位置，月洞门玻璃也放在这里
    func celestialPosition(in size: CGSize) -> CGPoint {
        let unit = celestialUnit
        let x: Double = unit.x * Double(size.width)
        let y: Double = unit.y * Double(size.height)
        return CGPoint(x: x, y: y)
    }

    private var radius: Double { phase == .day ? 18 : 22 }

    // MARK: - 小工具（全部是 Double）

    private static func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    private static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> Path {
        Path(ellipseIn: rect(cx - r, cy - r, r * 2, r * 2))
    }

    private static func glow(_ color: Color, _ cx: Double, _ cy: Double, inner: Double, outer: Double) -> GraphicsContext.Shading {
        let gradient = Gradient(colors: [color, color.opacity(0)])
        return .radialGradient(gradient, center: point(cx, cy), startRadius: inner, endRadius: outer)
    }

    private static func vertical(_ top: Color, _ bottom: Color, from y0: Double, to y1: Double) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [top, bottom]), startPoint: point(0, y0), endPoint: point(0, y1))
    }

    /// 让 x 在 [0, period) 里循环
    private static func wrap(_ value: Double, _ period: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: period)
        return r < 0 ? r + period : r
    }

    private static func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        let ax = Double(a.x), ay = Double(a.y)
        let cx = Double(c.x), cy = Double(c.y)
        let bx = Double(b.x), by = Double(b.y)
        let v: Double = 1 - u
        let x: Double = v * v * ax + 2 * v * u * cx + u * u * bx
        let y: Double = v * v * ay + 2 * v * u * cy + u * u * by
        return point(x, y)
    }

    // MARK: - 绘制

    /// - t: 动画时间（秒）；减弱动态效果时恒为 0
    /// - tilt: 设备倾斜（-1...1），用于景深错动
    func draw(_ context: GraphicsContext, size: CGSize, t: Double, tilt: CGSize) {
        var context = context
        let p = palette
        let w = Double(size.width)
        let h = Double(size.height)
        let tx = Double(tilt.width)
        let ty = Double(tilt.height)
        let waterY: Double = h * 0.84

        // 天空
        context.fill(Path(Self.rect(0, 0, w, h)), with: Self.vertical(p.skyTop, p.skyBottom, from: 0, to: waterY))

        if isNight { drawStars(context, w: w, h: h, t: t) }
        if showsCelestial { drawCelestial(context, w: w, h: h, tx: tx, ty: ty) }
        if geese > 0 { drawGeese(context, w: w, h: h, t: t, tx: tx) }

        // 三层山：远淡近浓，山脚化入雾中
        let bases: [Double] = [0.62, 0.72, 0.83]
        let amps: [Double] = [0.42, 0.32, 0.22]
        let seeds: [Double] = [1.3, 4.2, 7.7]
        let depths: [Double] = [4, 8, 13]
        for i in 0..<3 {
            var ctx = context
            ctx.translateBy(x: tx * depths[i], y: ty * depths[i] * 0.5)
            let base: Double = bases[i] * h
            let amplitude: Double = amps[i] * h
            let top: Double = base - amplitude
            let drift: Double = t * 0.002 * Double(i + 1)
            let path = ridgePath(w: w, h: h, base: base, amplitude: amplitude, seed: seeds[i], drift: drift)
            ctx.fill(path, with: Self.vertical(p.mountains[i], p.skyBottom, from: top, to: base + h * 0.06))
            if season == .winter && i < 2 && !isNight {
                // 山顶积雪
                let snowEnd: Double = top + amplitude * 0.45
                ctx.fill(path, with: Self.vertical(Color.white.opacity(0.55), Color.white.opacity(0), from: top, to: snowEnd))
            }
            if i == 1 { drawMist(context, w: w, t: t, y: base - h * 0.02) }
        }

        drawWater(context, w: w, h: h, t: t, waterY: waterY, tx: tx)
        if lanterns > 0 { drawLanterns(context, w: w, t: t, waterY: waterY, tx: tx) }
        drawWillow(context, w: w, h: h, t: t, tx: tx, ty: ty)
        drawSeasonalParticles(context, w: w, h: h, t: t, tx: tx, ty: ty)
    }

    // MARK: 山

    /// 叠加几组正弦波，再做一次幂次让山峰更尖，接近水墨山的轮廓
    static func ridgeHeight(_ x: Double, seed: Double) -> Double {
        let a1: Double = sin(x * 2.1 + seed) * 0.5
        let a2: Double = sin(x * 4.7 + seed * 1.7) * 0.27
        let a3: Double = sin(x * 9.3 + seed * 2.3) * 0.13
        let a4: Double = sin(x * 17.0 + seed * 3.1) * 0.06
        let a5: Double = sin(x * 31.0 + seed * 4.3) * 0.025
        let sum: Double = a1 + a2 + a3 + a4 + a5
        let normalized: Double = max(0, (sum + 0.985) / 1.97)
        return pow(normalized, 2.1)
    }

    private func ridgePath(w: Double, h: Double, base: Double, amplitude: Double, seed: Double, drift: Double) -> Path {
        var path = Path()
        let steps = 48
        // 左右各多画一点，倾斜错动时不露边
        let left: Double = -30
        let right: Double = w + 30
        path.move(to: Self.point(left, h))
        for i in 0...steps {
            let x: Double = left + (right - left) * Double(i) / Double(steps)
            let height: Double = Self.ridgeHeight(x / w * 3.2 + drift, seed: seed)
            path.addLine(to: Self.point(x, base - amplitude * height))
        }
        path.addLine(to: Self.point(right, h))
        path.closeSubpath()
        return path
    }

    private func drawMist(_ context: GraphicsContext, w: Double, t: Double, y: Double) {
        var context = context
        let color = palette.skyBottom
        for i in 0..<3 {
            let k = Double(i)
            let width: Double = w * (0.7 + k * 0.2)
            let period: Double = 70 + k * 25
            let phase: Double = Self.wrap(t / period + k * 0.37, 1)
            let x: Double = -width + phase * (w + width * 2) - width / 2
            let rect = Self.rect(x, y + k * 10 - 12, width, 34)
            let center = Self.point(x + width / 2, y + k * 10 + 5)
            let shading = GraphicsContext.Shading.radialGradient(Gradient(colors: [color.opacity(0.75), color.opacity(0)]),
                                                                 center: center, startRadius: 0, endRadius: width / 2)
            context.fill(Path(ellipseIn: rect), with: shading)
        }
    }

    // MARK: 日月星

    private func drawCelestial(_ context: GraphicsContext, w: Double, h: Double, tx: Double, ty: Double) {
        var context = context
        let p = palette
        let unit = celestialUnit
        let cx: Double = unit.x * w + tx * 2
        let cy: Double = unit.y * h + ty
        let r = radius
        let outer: Double = r * 3.4
        context.fill(Self.circle(cx, cy, outer), with: Self.glow(p.celestialGlow, cx, cy, inner: r * 0.8, outer: outer))
        context.fill(Self.circle(cx, cy, r), with: .color(p.celestial))
    }

    private func drawStars(_ context: GraphicsContext, w: Double, h: Double, t: Double) {
        var context = context
        var rng = SeededRandom(seed: 77)
        for _ in 0..<40 {
            let x: Double = rng.next() * w
            let y: Double = rng.next() * h * 0.5
            let speed: Double = 0.8 + rng.next() * 1.5
            let offset: Double = rng.next() * 6
            let twinkle: Double = 0.35 + 0.35 * sin(t * speed + offset)
            let r: Double = 0.6 + rng.next() * 0.9
            context.fill(Path(ellipseIn: Self.rect(x, y, r, r)), with: .color(Color.white.opacity(twinkle)))
        }
    }

    // MARK: 水

    private func drawWater(_ context: GraphicsContext, w: Double, h: Double, t: Double, waterY: Double, tx: Double) {
        let p = palette
        var ctx = context
        ctx.translateBy(x: tx * 13, y: 0)
        let bottomColor = p.skyTop.opacity(isNight ? 1 : 0.6)
        ctx.fill(Path(Self.rect(-30, waterY, w + 60, h - waterY)), with: Self.vertical(p.skyBottom, bottomColor, from: waterY, to: h))

        // 涟漪：一排排缓慢移动的短线
        var rng = SeededRandom(seed: 12)
        let rippleColor = p.ink.opacity(isNight ? 0.18 : 0.1)
        let rowGap: Double = (h - waterY) / 7.5
        for row in 0..<7 {
            let y: Double = waterY + 6 + Double(row) * rowGap
            for _ in 0..<5 {
                let length: Double = 14 + rng.next() * 36
                let speed: Double = 4 + rng.next() * 6
                let start: Double = rng.next() * w
                let x: Double = Self.wrap(start + t * speed, w + 60) - 30
                var line = Path()
                line.move(to: Self.point(x, y))
                line.addLine(to: Self.point(x + length, y))
                ctx.stroke(line, with: .color(rippleColor), lineWidth: 0.8)
            }
        }

        // 日月倒影：一串闪动的短横
        guard showsCelestial else { return }
        let cx: Double = celestialUnit.x * w
        for i in 0..<6 {
            let k = Double(i)
            let y: Double = waterY + 5 + k * 6
            let shimmer: Double = 0.75 + 0.25 * sin(t * 2 + k)
            let width: Double = radius * 1.6 * (1 - k * 0.12) * shimmer
            var line = Path()
            line.move(to: Self.point(cx - width / 2, y))
            line.addLine(to: Self.point(cx + width / 2, y))
            ctx.stroke(line, with: .color(p.celestial.opacity(0.35 - k * 0.05)), lineWidth: 1.4)
        }
    }

    /// 河灯：每一盏是一个送别了的物灵
    private func drawLanterns(_ context: GraphicsContext, w: Double, t: Double, waterY: Double, tx: Double) {
        var ctx = context
        ctx.translateBy(x: tx * 13, y: 0)
        var rng = SeededRandom(seed: 404)
        let warm = Color(red: 0.95, green: 0.72, blue: 0.43).opacity(0.45)
        let bodyColor = Self.color(0xC8442F)
        let flameColor = Color(red: 1, green: 0.85, blue: 0.55)
        let count = min(lanterns, 8)
        for i in 0..<count {
            let k = Double(i)
            let speed: Double = 3 + rng.next() * 4
            let start: Double = rng.next() * w
            let x: Double = Self.wrap(start + t * speed, w + 40) - 20
            let bob: Double = sin(t * 1.3 + k) * 1.2
            let y: Double = waterY + 12 + Double(i % 3) * 9 + bob
            ctx.fill(Self.circle(x, y, 16), with: Self.glow(warm, x, y, inner: 0, outer: 16))
            ctx.fill(Path(roundedRect: Self.rect(x - 3.5, y - 3, 7, 5.5), cornerRadius: 1.5), with: .color(bodyColor))
            ctx.fill(Path(ellipseIn: Self.rect(x - 1.2, y - 6.5, 2.4, 3.5)), with: .color(flameColor))
        }
    }

    // MARK: 鸿雁

    /// 鸿雁：每一只是一个传出去的物灵，排成人字缓缓飞过远天
    private func drawGeese(_ context: GraphicsContext, w: Double, h: Double, t: Double, tx: Double) {
        var context = context
        let ink = palette.ink.opacity(0.6)
        let count = min(geese, 7)
        let cycle: Double = Self.wrap(t / 48, 1)
        let leadX: Double = -80 + cycle * (w + 160) + tx * 3
        let leadY: Double = h * 0.2 + sin(t * 0.3) * 4
        for i in 0..<count {
            let rank = Double((i + 1) / 2)
            let side: Double = i == 0 ? 0 : (i.isMultiple(of: 2) ? 1 : -1)
            let x: Double = leadX - rank * 13
            let y: Double = leadY + side * rank * 7
            let flap: Double = sin(t * 5 + Double(i)) * 2.2
            var bird = Path()
            bird.move(to: Self.point(x - 5, y - 1 + flap))
            bird.addQuadCurve(to: Self.point(x, y), control: Self.point(x - 2.5, y - 2.5 + flap))
            bird.addQuadCurve(to: Self.point(x + 5, y - 1 + flap), control: Self.point(x + 2.5, y - 2.5 + flap))
            context.stroke(bird, with: .color(ink), lineWidth: 1.1)
        }
    }

    // MARK: 柳

    private var leafColor: Color? {
        switch season {
        case .spring: return Color(red: 0.55, green: 0.66, blue: 0.45)
        case .summer: return Color(red: 0.36, green: 0.52, blue: 0.38)
        case .autumn: return Color(red: 0.78, green: 0.62, blue: 0.3)
        case .winter: return nil
        }
    }

    /// 左上角伸出一根柳枝，柳条沿枝垂下，随风轻摆。冬天只剩枝条，春夏有叶，秋天叶子泛黄。
    private func drawWillow(_ context: GraphicsContext, w: Double, h: Double, t: Double, tx: Double, ty: Double) {
        let p = palette
        var ctx = context
        ctx.translateBy(x: tx * 20, y: ty * 6)
        let leaf = leafColor
        let inkOpacity: Double = isNight ? 0.55 : 0.42

        // 主枝：从画面左上角外拱进来，微微上扬
        let branchStart = Self.point(-12, h * 0.02)
        let branchEnd = Self.point(w * 0.34, h * 0.05)
        let branchControl = Self.point(w * 0.16, -h * 0.04)
        var branch = Path()
        branch.move(to: branchStart)
        branch.addQuadCurve(to: branchEnd, control: branchControl)
        ctx.stroke(branch, with: .color(p.ink.opacity(inkOpacity + 0.1)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        // 柳条：从主枝上垂下，越靠近枝梢越短
        var rng = SeededRandom(seed: 31)
        let strands = 15
        for i in 0..<strands {
            let k = Double(i)
            let u: Double = 0.08 + 0.9 * k / Double(strands - 1)
            let origin = Self.quad(branchStart, branchControl, branchEnd, u)
            let ox = Double(origin.x)
            let oy = Double(origin.y)
            let length: Double = h * (0.48 - u * 0.26) * (0.8 + rng.next() * 0.4)
            let sway: Double = sin(t * 0.8 + k * 0.5) * (6 + length * 0.05)
            let end = Self.point(ox + 10 + sway, oy + length)
            let control = Self.point(ox - 6 + sway * 0.2, oy + length * 0.45)

            // 上粗下细：分三段，越往下越细越淡
            for segment in 0..<3 {
                let s = Double(segment)
                let u0: Double = s / 3
                let u1: Double = (s + 1) / 3
                var piece = Path()
                piece.move(to: Self.quad(origin, control, end, u0))
                for step in 1...6 {
                    let u: Double = u0 + (u1 - u0) * Double(step) / 6
                    piece.addLine(to: Self.quad(origin, control, end, u))
                }
                let opacity: Double = inkOpacity * (1 - s * 0.22)
                let width: Double = 1.3 - s * 0.35
                ctx.stroke(piece, with: .color(p.ink.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            guard let leaf else { continue }
            let leafShade = leaf.opacity(isNight ? 0.45 : 0.8)
            for step in 2..<16 {
                let point = Self.quad(origin, control, end, Double(step) / 16)
                let side: Double = step.isMultiple(of: 2) ? 1 : -1
                var leafContext = ctx
                leafContext.translateBy(x: Double(point.x) + side * 1.6, y: Double(point.y))
                leafContext.rotate(by: .degrees(side * 28))
                leafContext.fill(Path(ellipseIn: Self.rect(-1.1, -3, 2.2, 6)), with: .color(leafShade))
            }
        }
    }

    // MARK: 季节

    private func drawSeasonalParticles(_ context: GraphicsContext, w: Double, h: Double, t: Double, tx: Double, ty: Double) {
        var ctx = context
        ctx.translateBy(x: tx * 10, y: ty * 4)
        var rng = SeededRandom(seed: 2026)
        let spanX: Double = w + 40
        let spanY: Double = h + 20

        switch season {
        case .winter:
            let flake = isNight ? Color.white.opacity(0.85) : Color(red: 0.56, green: 0.61, blue: 0.64).opacity(0.55)
            for _ in 0..<46 {
                let speed: Double = 10 + rng.next() * 18
                let x0: Double = rng.next() * spanX
                let y0: Double = rng.next() * spanY
                let y: Double = Self.wrap(y0 + t * speed, spanY) - 10
                let x: Double = Self.wrap(x0 + sin(t * 0.6 + x0) * 12, spanX) - 20
                let r: Double = 0.9 + rng.next() * 1.5
                ctx.fill(Path(ellipseIn: Self.rect(x, y, r * 2, r * 2)), with: .color(flake))
            }
        case .spring:
            let petal = Color(red: 0.91, green: 0.66, blue: 0.66).opacity(0.8)
            for _ in 0..<20 {
                let speed: Double = 14 + rng.next() * 14
                let x0: Double = rng.next() * spanX
                let y0: Double = rng.next() * spanY
                let spin: Double = rng.next() * 6
                let y: Double = Self.wrap(y0 + t * speed, spanY) - 10
                let x: Double = Self.wrap(x0 + t * speed * 0.6, spanX) - 20
                var c = ctx
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(t * 1.4 + spin))
                c.fill(Path(ellipseIn: Self.rect(-3, -1.6, 6, 3.2)), with: .color(petal))
            }
        case .autumn:
            let leaf = Color(red: 0.83, green: 0.64, blue: 0.24).opacity(0.85)
            for _ in 0..<15 {
                let speed: Double = 12 + rng.next() * 12
                let x0: Double = rng.next() * spanX
                let y0: Double = rng.next() * spanY
                let spin: Double = rng.next() * 6
                let y: Double = Self.wrap(y0 + t * speed, spanY) - 10
                let x: Double = Self.wrap(x0 + sin(t * 0.8 + spin) * 18 + t * 4, spanX) - 20
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
            let firefly = Color(red: 0.9, green: 0.95, blue: 0.6)
            for _ in 0..<18 {
                let x0: Double = rng.next() * w
                let y0: Double = h * (0.45 + rng.next() * 0.45)
                let phase: Double = rng.next() * 6
                let x: Double = x0 + sin(t * 0.5 + phase) * 14
                let y: Double = y0 + cos(t * 0.4 + phase) * 8
                let blink: Double = max(0, sin(t * 1.6 + phase))
                ctx.fill(Self.circle(x, y, 7), with: Self.glow(firefly.opacity(0.6 * blink), x, y, inner: 0, outer: 7))
            }
        }
    }
}
