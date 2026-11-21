import SwiftUI

/// 一幅水墨山水的"配方"：由时辰、季节、天气、深浅色模式，以及用户的图鉴（河灯、鸿雁）决定。
///
/// 构图取倪瓒的"一河两岸"：远山、近山，一湖水，再往下是物灵站着的岸。
/// 画法参考传统山水的层次：远山淡、近山浓，山脚化入雾中留白；
/// 配色取低饱和的青绿与墨色，白天像《千里江山图》褪了色的青绿，夜里是一纸墨色。
///
/// 实现说明：
/// - 所有计算统一用 Double，只在最后构造 CGPoint / CGRect 时转换。
///   混用 CGFloat 和 Double 会让编译器在类型推断上耗时过长（"unable to type-check this expression in reasonable time"）。
/// - 同色的笔画（涟漪、柳条、柳叶、花瓣、雪、雨）都先拼进同一条 Path，再一次画完：
///   每帧的绘制调用从几百次降到几十次。
struct LandscapeScene {
    let phase: DayPhase
    let season: SolarTerm.Season
    let weather: Weather
    /// 已送别的物灵：化作水面上的河灯
    let lanterns: Int
    /// 已传出的物灵：化作远天的鸿雁
    let geese: Int
    /// 是否画日月。作为其他页面的淡背景时不画：日月会透到内容后面，像一块污渍
    let showsCelestial: Bool
    /// 其他页面的淡背景：画面上部会化入纸色，省掉看不见的柳枝 / 梅枝
    let isAmbient: Bool
    /// 配色在创建时算好一次，不在每帧里重复计算
    let palette: Palette

    /// 水面的位置（占画面高度的比例）
    static let waterLine: Double = 0.70
    /// 点一下留下的涟漪 / 墨晕持续多久（秒）
    static let rippleLife: Double = 2.6

    init(date: Date, isDark: Bool, choice: SceneChoice = .auto, lanterns: Int, geese: Int,
         showsCelestial: Bool = true, isAmbient: Bool = false) {
        let phase: DayPhase = choice.phase ?? (isDark ? .night : DayPhase(date: date))
        let season: SolarTerm.Season = choice.season ?? SolarTerm(date: date).season
        let weather: Weather = choice.weather ?? Weather.natural(for: season)
        self.phase = phase
        self.season = season
        self.weather = weather
        self.lanterns = lanterns
        self.geese = geese
        self.showsCelestial = showsCelestial
        self.isAmbient = isAmbient
        self.palette = Self.makePalette(phase: phase, season: season, weather: weather)
    }

    var isNight: Bool { phase == .night }

    /// 景的"样子"变了才做换景转场（河灯、鸿雁多一盏少一只不算）
    var signature: String { "\(phase.rawValue).\(season.rawValue).\(weather.rawValue)" }

    /// 手指点过的地方：水面上是一圈圈涟漪，山和天上是一点晕开的淡墨
    struct Ripple: Equatable {
        var x: Double
        var y: Double
        /// 和 draw(t:) 同一个时间轴
        var start: Double
    }

    // MARK: - 配色

    struct Palette {
        var skyTop: Color
        var skyBottom: Color
        var mountains: [Color]   // 远 → 近
        var celestial: Color
        var celestialGlow: Color
        var ink: Color           // 柳枝、鸿雁、涟漪、小舟
    }

    private static func color(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(uiColor: UIColor(hex: hex)).opacity(opacity)
    }

    private static func makePalette(phase: DayPhase, season: SolarTerm.Season, weather: Weather) -> Palette {
        let c = color
        // 季节给山色一点偏移：春夏偏青绿，秋偏赭，冬偏灰
        let seasonal: [UInt32]
        switch season {
        case .spring: seasonal = [0x8FA9A0, 0x5E8279, 0x3C5F57]
        case .summer: seasonal = [0x86A39A, 0x4F7A70, 0x2F574F]
        case .autumn: seasonal = [0xA8A08C, 0x857A62, 0x5C5242]
        case .winter: seasonal = [0xA3A8AB, 0x7C8387, 0x565D62]
        }
        var p: Palette
        switch phase {
        case .dawn:
            let mountains: [Color] = seasonal.map { c($0, 0.75) }
            p = Palette(skyTop: c(0xE8DCCB, 1), skyBottom: c(0xF4ECE1, 1), mountains: mountains,
                        celestial: c(0xE7A383, 0.9), celestialGlow: c(0xF1C6A8, 0.45), ink: c(0x3A3631, 1))
        case .day:
            let mountains: [Color] = seasonal.map { c($0, 1) }
            p = Palette(skyTop: c(0xDDE5E2, 1), skyBottom: c(0xF4F0E8, 1), mountains: mountains,
                        celestial: c(0xFFFFFF, 0.85), celestialGlow: c(0xFFFFFF, 0.5), ink: c(0x2E2B27, 1))
        case .dusk:
            let mountains: [Color] = [c(0x9C8E92, 1), c(0x6F6269, 1), c(0x4B4049, 1)]
            p = Palette(skyTop: c(0xD9BBA6, 1), skyBottom: c(0xF2E2D2, 1), mountains: mountains,
                        celestial: c(0xD0664E, 0.72), celestialGlow: c(0xE8A080, 0.3), ink: c(0x3A2F2C, 1))
        case .night:
            let mountains: [Color] = [c(0x30343C, 1), c(0x22262D, 1), c(0x171A20, 1)]
            p = Palette(skyTop: c(0x10131A, 1), skyBottom: c(0x23262D, 1), mountains: mountains,
                        celestial: c(0xEDE8DF, 0.95), celestialGlow: c(0xEDE8DF, 0.18), ink: c(0xB8B2A8, 1))
        }
        if phase == .night && season == .autumn {
            // 秋夜的月亮更暖、更亮
            p.celestial = c(0xF3E3BF, 0.97)
            p.celestialGlow = c(0xF3E3BF, 0.24)
        }

        let night: Bool = phase == .night
        switch weather {
        case .clear:
            break
        case .rain:
            // 雨天：天色压低发灰，远山几乎隐进雨幕
            let veil: Color = night ? c(0x0B0E13, 1) : c(0xB3B9BB, 1)
            p.skyTop = p.skyTop.mix(with: veil, by: 0.55)
            p.skyBottom = p.skyBottom.mix(with: veil, by: 0.28)
            p.mountains = fade(p.mountains, toward: p.skyBottom, by: [0.6, 0.4, 0.18])
        case .mist:
            p.mountains = fade(p.mountains, toward: p.skyBottom, by: [0.55, 0.32, 0.12])
            p.celestial = p.celestial.opacity(0.55)
        case .snow:
            if !night { p.skyTop = p.skyTop.mix(with: c(0xE8EAEA, 1), by: 0.55) }
            p.mountains = fade(p.mountains, toward: p.skyBottom, by: [0.3, 0.16, 0])
            p.celestial = p.celestial.opacity(0.7)
        }
        return p
    }

    private static func fade(_ colors: [Color], toward target: Color, by amounts: [Double]) -> [Color] {
        var result: [Color] = []
        for i in 0..<colors.count {
            let amount: Double = i < amounts.count ? amounts[i] : 0
            result.append(colors[i].mix(with: target, by: amount))
        }
        return result
    }

    /// 日 / 月的相对位置
    private var celestialUnit: (x: Double, y: Double) {
        switch phase {
        case .dawn: return (0.36, 0.33)
        case .day: return (0.62, 0.30)
        case .dusk: return (0.60, 0.44)
        case .night: return (0.62, 0.30)
        }
    }

    private var radius: Double {
        if phase == .day { return 18 }
        if phase == .night && season == .autumn { return 27 }
        return 22
    }

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

    /// 平移 + 旋转（先绕自身原点转，再挪到 (x, y)）
    private static func placed(_ x: Double, _ y: Double, angle: Double, scaleX: Double = 1, scaleY: Double = 1) -> CGAffineTransform {
        CGAffineTransform(translationX: x, y: y).rotated(by: angle).scaledBy(x: scaleX, y: scaleY)
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

    // 反复用到的小形状，只建一次
    private static let leafShape = Path(ellipseIn: CGRect(x: -1.1, y: -3, width: 2.2, height: 6))
    private static let petalShape = Path(ellipseIn: CGRect(x: -3, y: -1.6, width: 6, height: 3.2))
    private static let lotusPetalShape = Path(ellipseIn: CGRect(x: -2.6, y: -10, width: 5.2, height: 10))
    private static let ginkgoShape: Path = {
        var fan = Path()
        fan.move(to: .zero)
        for k in 0...8 {
            let a: Double = (200 + 140 * Double(k) / 8) * Double.pi / 180
            fan.addLine(to: CGPoint(x: cos(a) * 5, y: sin(a) * 5))
        }
        fan.closeSubpath()
        return fan
    }()
    /// 荷叶：一个缺了一角的圆（缺口朝后），画的时候再压扁
    private static let lotusLeafShape: Path = {
        var leaf = Path()
        leaf.move(to: .zero)
        for k in 0...24 {
            let a: Double = (-70 + 320 * Double(k) / 24) * Double.pi / 180
            leaf.addLine(to: CGPoint(x: cos(a), y: sin(a)))
        }
        leaf.closeSubpath()
        return leaf
    }()

    // MARK: - 绘制

    /// - t: 动画时间（秒）；减弱动态效果时恒为 0
    /// - tilt: 设备倾斜（-1...1），用于景深错动
    /// - ripples: 手指点出来的涟漪
    func draw(_ context: GraphicsContext, size: CGSize, t: Double, tilt: CGSize, ripples: [Ripple] = []) {
        let p = palette
        let w = Double(size.width)
        let h = Double(size.height)
        guard w > 1, h > 1 else { return }
        let tx = Double(tilt.width)
        let ty = Double(tilt.height)
        let waterY: Double = h * Self.waterLine

        // 天空
        context.fill(Path(Self.rect(0, 0, w, h)), with: Self.vertical(p.skyTop, p.skyBottom, from: 0, to: waterY))

        if isNight && weather != .rain { drawStars(context, w: w, h: h, t: t) }
        if weather == .rain { drawRainClouds(context, w: w, h: h, t: t) }
        if showsCelestial && weather != .rain { drawCelestial(context, w: w, h: h, tx: tx, ty: ty) }
        if geese > 0 { drawGeese(context, w: w, h: h, t: t, tx: tx) }

        drawMountains(context, w: w, h: h, t: t, tx: tx, ty: ty)
        drawWater(context, w: w, h: h, t: t, waterY: waterY, tx: tx)
        if season == .summer { drawLotus(context, w: w, h: h, t: t, waterY: waterY, tx: tx) }
        drawBoat(context, w: w, h: h, t: t, waterY: waterY, tx: tx)
        if lanterns > 0 { drawLanterns(context, w: w, h: h, t: t, waterY: waterY, tx: tx) }
        if weather == .rain { drawRainRings(context, w: w, h: h, t: t, waterY: waterY, tx: tx) }
        if !ripples.isEmpty { drawRipples(context, ripples: ripples, t: t, waterY: waterY) }
        if !isAmbient {
            if season == .winter {
                drawPlum(context, w: w, h: h, t: t, tx: tx, ty: ty)
            } else {
                drawWillow(context, w: w, h: h, t: t, tx: tx, ty: ty)
            }
        }
        drawAtmosphere(context, w: w, h: h, t: t, tx: tx, ty: ty)
    }

    // MARK: 山

    private static let mountainBases: [Double] = [0.53, 0.61, 0.70]
    private static let mountainAmps: [Double] = [0.36, 0.28, 0.20]
    private static let mountainSeeds: [Double] = [1.3, 4.2, 7.7]
    private static let mountainDepths: [Double] = [4, 8, 13]

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

    /// 三层山：远淡近浓，山脚化入雾中
    private func drawMountains(_ context: GraphicsContext, w: Double, h: Double, t: Double, tx: Double, ty: Double) {
        let p = palette
        let snowy: Bool = season == .winter || weather == .snow
        for i in 0..<3 {
            var ctx = context
            let depth: Double = Self.mountainDepths[i]
            ctx.translateBy(x: tx * depth, y: ty * depth * 0.5)
            let base: Double = Self.mountainBases[i] * h
            let amplitude: Double = Self.mountainAmps[i] * h
            let top: Double = base - amplitude
            let drift: Double = t * 0.002 * Double(i + 1)
            let path = ridgePath(w: w, h: h, base: base, amplitude: amplitude, seed: Self.mountainSeeds[i], drift: drift)
            ctx.fill(path, with: Self.vertical(p.mountains[i], p.skyBottom, from: top, to: base + h * 0.05))
            if snowy && i < 2 {
                // 山顶积雪
                let snowEnd: Double = top + amplitude * 0.45
                let cap: Double = isNight ? 0.2 : 0.55
                ctx.fill(path, with: Self.vertical(Color.white.opacity(cap), Color.white.opacity(0), from: top, to: snowEnd))
            }
            // 雾：平时只在中景山脚一道；起岚的日子，远山腰、近水面各多一道
            if i == 0 && weather == .mist {
                drawMist(context, w: w, h: h, t: t, y: base - h * 0.05, strength: 1, seed: 0.1)
            }
            if i == 1 {
                drawMist(context, w: w, h: h, t: t, y: base - h * 0.02, strength: weather == .mist ? 1 : 0.75, seed: 0)
            }
            if i == 2 && (weather == .mist || weather == .rain) {
                drawMist(context, w: w, h: h, t: t, y: base - h * 0.03, strength: 0.85, seed: 0.6)
            }
        }
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

    /// 山在水里的倒影：同一条山脊上下翻转、压扁
    private func reflectionPath(w: Double, waterY: Double, amplitude: Double, seed: Double, drift: Double) -> Path {
        var path = Path()
        let steps = 48
        let left: Double = -30
        let right: Double = w + 30
        path.move(to: Self.point(left, waterY))
        for i in 0...steps {
            let x: Double = left + (right - left) * Double(i) / Double(steps)
            let height: Double = Self.ridgeHeight(x / w * 3.2 + drift, seed: seed)
            path.addLine(to: Self.point(x, waterY + amplitude * height))
        }
        path.addLine(to: Self.point(right, waterY))
        path.closeSubpath()
        return path
    }

    private func drawMist(_ context: GraphicsContext, w: Double, h: Double, t: Double, y: Double, strength: Double, seed: Double) {
        let color = palette.skyBottom
        let band: Double = max(34, h * 0.065)
        for i in 0..<3 {
            let k = Double(i)
            let width: Double = w * (0.7 + k * 0.2)
            let period: Double = 70 + k * 25
            let phase: Double = Self.wrap(t / period + k * 0.37 + seed, 1)
            let x: Double = -width + phase * (w + width * 2) - width / 2
            let top: Double = y + k * 10 - 12
            let rect = Self.rect(x, top, width, band)
            let center = Self.point(x + width / 2, top + band / 2)
            let gradient = Gradient(colors: [color.opacity(0.75 * strength), color.opacity(0)])
            let shading = GraphicsContext.Shading.radialGradient(gradient, center: center, startRadius: 0, endRadius: width / 2)
            context.fill(Path(ellipseIn: rect), with: shading)
        }
    }

    // MARK: 天

    private func drawCelestial(_ context: GraphicsContext, w: Double, h: Double, tx: Double, ty: Double) {
        let p = palette
        let unit = celestialUnit
        let cx: Double = unit.x * w + tx * 2
        let cy: Double = unit.y * h + ty
        let r = radius
        let outer: Double = r * (weather == .mist ? 4.2 : 3.4)
        context.fill(Self.circle(cx, cy, outer), with: Self.glow(p.celestialGlow, cx, cy, inner: r * 0.8, outer: outer))
        context.fill(Self.circle(cx, cy, r), with: .color(p.celestial))
        if isNight {
            // 月面上几块极淡的阴影
            var maria = Path()
            maria.addEllipse(in: Self.rect(cx - r * 0.45, cy - r * 0.35, r * 0.5, r * 0.4))
            maria.addEllipse(in: Self.rect(cx + r * 0.05, cy + r * 0.05, r * 0.42, r * 0.34))
            maria.addEllipse(in: Self.rect(cx - r * 0.2, cy + r * 0.32, r * 0.26, r * 0.2))
            context.fill(maria, with: .color(Color.black.opacity(0.06)))
        }
    }

    /// 星星分四组，每组一起明灭：画 4 次，而不是 40 次
    private func drawStars(_ context: GraphicsContext, w: Double, h: Double, t: Double) {
        var rng = SeededRandom(seed: 77)
        var groups: [Path] = [Path(), Path(), Path(), Path()]
        for i in 0..<44 {
            let x: Double = rng.next() * w
            let y: Double = rng.next() * h * 0.5
            let r: Double = 0.6 + rng.next() * 0.9
            groups[i % 4].addEllipse(in: Self.rect(x, y, r, r))
        }
        let speeds: [Double] = [0.9, 1.3, 1.8, 2.3]
        let dim: Double = weather == .mist ? 0.5 : 1
        for g in 0..<4 {
            let twinkle: Double = (0.35 + 0.35 * sin(t * speeds[g] + Double(g) * 1.7)) * dim
            context.fill(groups[g], with: .color(Color.white.opacity(twinkle)))
        }
    }

    /// 雨云：几团压低的淡墨，缓缓移过
    private func drawRainClouds(_ context: GraphicsContext, w: Double, h: Double, t: Double) {
        let cloud: Color = isNight ? Color.black.opacity(0.35) : palette.ink.opacity(0.14)
        for i in 0..<4 {
            let k = Double(i)
            let width: Double = w * (0.9 + k * 0.15)
            let x: Double = Self.wrap(k * w * 0.37 + t * (2 + k), w + width) - width * 0.5
            let y: Double = h * (0.06 + k * 0.045)
            var ctx = context
            ctx.translateBy(x: x, y: y)
            ctx.scaleBy(x: 1, y: 0.22)
            let r: Double = width / 2
            ctx.fill(Self.circle(0, 0, r), with: Self.glow(cloud, 0, 0, inner: 0, outer: r))
        }
    }

    /// 鸿雁：每一只是一个传出去的物灵，排成人字缓缓飞过远天
    private func drawGeese(_ context: GraphicsContext, w: Double, h: Double, t: Double, tx: Double) {
        let ink = palette.ink.opacity(0.6)
        let count = min(geese, 7)
        let cycle: Double = Self.wrap(t / 48, 1)
        let leadX: Double = -80 + cycle * (w + 160) + tx * 3
        let leadY: Double = h * 0.2 + sin(t * 0.3) * 4
        var flock = Path()
        for i in 0..<count {
            let rank = Double((i + 1) / 2)
            let side: Double = i == 0 ? 0 : (i.isMultiple(of: 2) ? 1 : -1)
            let x: Double = leadX - rank * 13
            let y: Double = leadY + side * rank * 7
            let flap: Double = sin(t * 5 + Double(i)) * 2.2
            flock.move(to: Self.point(x - 5, y - 1 + flap))
            flock.addQuadCurve(to: Self.point(x, y), control: Self.point(x - 2.5, y - 2.5 + flap))
            flock.addQuadCurve(to: Self.point(x + 5, y - 1 + flap), control: Self.point(x + 2.5, y - 2.5 + flap))
        }
        context.stroke(flock, with: .color(ink), lineWidth: 1.1)
    }

    // MARK: 水

    private func drawWater(_ context: GraphicsContext, w: Double, h: Double, t: Double, waterY: Double, tx: Double) {
        let p = palette
        var ctx = context
        ctx.translateBy(x: tx * 13, y: 0)
        let deep = p.skyTop.opacity(isNight ? 1 : 0.6)
        ctx.fill(Path(Self.rect(-30, waterY, w + 60, h - waterY)), with: Self.vertical(p.skyBottom, deep, from: waterY, to: h))

        // 近山的倒影：越往下越淡
        let amplitude: Double = Self.mountainAmps[2] * h * 0.55
        let drift: Double = t * 0.002 * 3
        let reflection = reflectionPath(w: w, waterY: waterY, amplitude: amplitude, seed: Self.mountainSeeds[2], drift: drift)
        let mirror: Color = p.mountains[2]
        let strength: Double = isNight ? 0.5 : 0.26
        ctx.fill(reflection, with: Self.vertical(mirror.opacity(strength), mirror.opacity(0), from: waterY, to: waterY + amplitude))

        // 涟漪：一排排缓慢移动的短线，近处长、远处短。全部拼进一条 Path，一次画完
        var rng = SeededRandom(seed: 12)
        let rows = 9
        let rowGap: Double = (h - waterY) / Double(rows)
        var lines = Path()
        for row in 0..<rows {
            let y: Double = waterY + 6 + Double(row) * rowGap
            let perspective: Double = 0.6 + Double(row) / Double(rows) * 0.8
            for _ in 0..<5 {
                let length: Double = (14 + rng.next() * 36) * perspective
                let speed: Double = 4 + rng.next() * 6
                let start: Double = rng.next() * w
                let x: Double = Self.wrap(start + t * speed, w + 60) - 30
                lines.move(to: Self.point(x, y))
                lines.addLine(to: Self.point(x + length, y))
            }
        }
        ctx.stroke(lines, with: .color(p.ink.opacity(isNight ? 0.18 : 0.1)), lineWidth: 0.8)

        // 日月倒影：一串闪动的短横
        guard showsCelestial, weather != .rain else { return }
        let cx: Double = celestialUnit.x * w
        let dim: Double = weather == .clear ? 1 : 0.6
        for i in 0..<6 {
            let k = Double(i)
            let y: Double = waterY + 5 + k * 6
            let shimmer: Double = 0.75 + 0.25 * sin(t * 2 + k)
            let width: Double = radius * 1.6 * (1 - k * 0.12) * shimmer
            var line = Path()
            line.move(to: Self.point(cx - width / 2, y))
            line.addLine(to: Self.point(cx + width / 2, y))
            ctx.stroke(line, with: .color(p.celestial.opacity((0.35 - k * 0.05) * dim)), lineWidth: 1.4)
        }
    }

    /// 一叶扁舟，蓑笠翁独钓，慢慢漂过水面；黄昏和夜里船尾挑一盏小灯
    private func drawBoat(_ context: GraphicsContext, w: Double, h: Double, t: Double, waterY: Double, tx: Double) {
        let p = palette
        var ctx = context
        ctx.translateBy(x: tx * 13, y: 0)
        let span: Double = w + 120
        let x: Double = Self.wrap(t * 2.2 + w * 0.58, span) - 60
        let y: Double = waterY + min(30, (h - waterY) * 0.3) + sin(t * 0.8) * 0.9
        let rock: Double = sin(t * 0.8 + 0.6) * 0.035
        let inkColor: Color = p.ink.opacity(isNight ? 0.85 : 0.78)

        // 倒影：船底下一抹淡墨（不随船身摇晃）
        ctx.fill(Path(ellipseIn: Self.rect(x - 22, y + 2.5, 44, 3.2)), with: .color(p.ink.opacity(0.12)))

        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: .radians(rock))

        var boat = Path()
        // 船身：一弯新月
        boat.move(to: Self.point(-24, -4))
        boat.addQuadCurve(to: Self.point(24, -5.5), control: Self.point(0, 6.5))
        boat.addQuadCurve(to: Self.point(-24, -4), control: Self.point(1, 0.5))
        // 蓑衣
        boat.move(to: Self.point(3, -3))
        boat.addLine(to: Self.point(11, -3))
        boat.addLine(to: Self.point(8.6, -11))
        boat.addLine(to: Self.point(5.2, -11))
        boat.closeSubpath()
        // 斗笠
        boat.move(to: Self.point(1.2, -10.6))
        boat.addLine(to: Self.point(12.6, -10.6))
        boat.addLine(to: Self.point(6.9, -15.6))
        boat.closeSubpath()
        ctx.fill(boat, with: .color(inkColor))

        // 钓竿与钓丝
        var rod = Path()
        rod.move(to: Self.point(5, -8))
        rod.addQuadCurve(to: Self.point(-23, -27), control: Self.point(-8, -15))
        ctx.stroke(rod, with: .color(inkColor), lineWidth: 0.9)
        var thread = Path()
        thread.move(to: Self.point(-23, -27))
        thread.addLine(to: Self.point(-26, 3))
        ctx.stroke(thread, with: .color(p.ink.opacity(0.32)), lineWidth: 0.5)

        if phase == .night || phase == .dusk {
            let warm = Color(red: 1, green: 0.78, blue: 0.48)
            ctx.fill(Self.circle(20, -9, 11), with: Self.glow(warm.opacity(0.5), 20, -9, inner: 0, outer: 11))
            ctx.fill(Self.circle(20, -9, 1.6), with: .color(warm))
        }
    }

    /// 夏天的荷：近水几片荷叶，两支荷苞、一朵开了的荷花
    private func drawLotus(_ context: GraphicsContext, w: Double, h: Double, t: Double, waterY: Double, tx: Double) {
        var ctx = context
        ctx.translateBy(x: tx * 15, y: 0)
        let depth: Double = h - waterY
        let leafColor: Color = isNight ? Color(red: 0.2, green: 0.3, blue: 0.25) : Color(red: 0.37, green: 0.52, blue: 0.4)

        let pads: [(x: Double, y: Double, r: Double)] = [
            (0.80, 0.30, 16), (0.90, 0.42, 21), (0.70, 0.38, 11), (0.97, 0.22, 10), (0.07, 0.38, 15), (0.17, 0.27, 9),
        ]
        var leaves = Path()
        var veins = Path()
        for pad in pads {
            let cx: Double = pad.x * w
            let cy: Double = waterY + pad.y * depth
            let r: Double = pad.r
            let squash: Double = 0.34
            leaves.addPath(Self.lotusLeafShape, transform: Self.placed(cx, cy, angle: 0, scaleX: r, scaleY: r * squash))
            for k in 0..<6 {
                let a: Double = (-20 + Double(k) * 44) * Double.pi / 180
                veins.move(to: Self.point(cx, cy))
                veins.addLine(to: Self.point(cx + cos(a) * r * 0.8, cy + sin(a) * r * 0.8 * squash))
            }
        }

        let sway: Double = sin(t * 0.7) * 1.5
        let stems: [(x: Double, y: Double, height: Double, open: Bool)] = [
            (0.84, 0.34, 27, true), (0.75, 0.32, 18, false), (0.12, 0.34, 21, false),
        ]
        var stalks = Path()
        var petals = Path()
        var buds = Path()
        var hearts = Path()
        for stem in stems {
            let bx: Double = stem.x * w
            let by: Double = waterY + stem.y * depth
            let topX: Double = bx + sway
            let topY: Double = by - stem.height
            stalks.move(to: Self.point(bx, by))
            stalks.addQuadCurve(to: Self.point(topX, topY), control: Self.point(bx - 2, by - stem.height * 0.5))
            if stem.open {
                for degrees in [-64.0, -32.0, 0.0, 32.0, 64.0] {
                    petals.addPath(Self.lotusPetalShape, transform: Self.placed(topX, topY, angle: degrees * Double.pi / 180))
                }
                hearts.addEllipse(in: Self.rect(topX - 2.2, topY - 4, 4.4, 2.6))
            } else {
                buds.move(to: Self.point(topX, topY - 9))
                buds.addQuadCurve(to: Self.point(topX, topY + 1), control: Self.point(topX + 5.5, topY - 3))
                buds.addQuadCurve(to: Self.point(topX, topY - 9), control: Self.point(topX - 5.5, topY - 3))
            }
        }
        let pink: Color = isNight ? Color(red: 0.72, green: 0.5, blue: 0.56) : Color(red: 0.92, green: 0.63, blue: 0.69)
        ctx.fill(leaves, with: .color(leafColor.opacity(0.88)))
        ctx.stroke(veins, with: .color(Color.black.opacity(0.12)), lineWidth: 0.5)
        ctx.stroke(stalks, with: .color(leafColor.opacity(0.9)), lineWidth: 1)
        ctx.fill(petals, with: .color(pink.opacity(0.88)))
        ctx.fill(buds, with: .color(pink))
        ctx.fill(hearts, with: .color(Color(red: 0.95, green: 0.82, blue: 0.45)))
    }

    /// 河灯：每一盏是一个送别了的物灵
    private func drawLanterns(_ context: GraphicsContext, w: Double, h: Double, t: Double, waterY: Double, tx: Double) {
        var ctx = context
        ctx.translateBy(x: tx * 13, y: 0)
        var rng = SeededRandom(seed: 404)
        let warm = Color(red: 0.95, green: 0.72, blue: 0.43)
        let count = min(lanterns, 8)
        var bodies = Path()
        var flames = Path()
        var trails = Path()
        for i in 0..<count {
            let k = Double(i)
            let speed: Double = 3 + rng.next() * 4
            let start: Double = rng.next() * w
            let x: Double = Self.wrap(start + t * speed, w + 40) - 20
            let bob: Double = sin(t * 1.3 + k) * 1.2
            let y: Double = waterY + 10 + Double(i % 3) * 8 + bob
            ctx.fill(Self.circle(x, y, 16), with: Self.glow(warm.opacity(0.45), x, y, inner: 0, outer: 16))
            bodies.addPath(Path(roundedRect: Self.rect(x - 3.5, y - 3, 7, 5.5), cornerRadius: 1.5))
            flames.addEllipse(in: Self.rect(x - 1.2, y - 6.5, 2.4, 3.5))
            // 灯影：水里一道暖色
            trails.move(to: Self.point(x, y + 4))
            trails.addLine(to: Self.point(x, y + 13))
        }
        ctx.stroke(trails, with: .color(warm.opacity(0.3)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        ctx.fill(bodies, with: .color(Self.color(0xC8442F)))
        ctx.fill(flames, with: .color(Color(red: 1, green: 0.85, blue: 0.55)))
    }

    /// 雨落在水面：一圈圈小涟漪此起彼伏
    private func drawRainRings(_ context: GraphicsContext, w: Double, h: Double, t: Double, waterY: Double, tx: Double) {
        var ctx = context
        ctx.translateBy(x: tx * 13, y: 0)
        let ink = palette.ink
        let depth: Double = h - waterY
        var rng = SeededRandom(seed: 61)
        for i in 0..<16 {
            let period: Double = 1.6 + rng.next() * 1.2
            let local: Double = t + rng.next() * period
            let cycle = Int(local / period)
            let age: Double = (local - Double(cycle) * period) / period
            // 每一轮换个地方落
            var spot = SeededRandom(seed: UInt64(truncatingIfNeeded: i &* 977 &+ cycle &* 7919))
            let x: Double = spot.next() * w
            let y: Double = waterY + 4 + spot.next() * (depth - 8)
            let near: Double = 0.6 + (y - waterY) / depth
            let r: Double = (2 + age * 12) * near
            let opacity: Double = (1 - age) * 0.35
            ctx.stroke(Path(ellipseIn: Self.rect(x - r, y - r * 0.3, r * 2, r * 0.6)), with: .color(ink.opacity(opacity)), lineWidth: 0.7)
        }
    }

    /// 手指点过的地方：水面荡开三圈涟漪；山和天上晕开一点淡墨
    private func drawRipples(_ context: GraphicsContext, ripples: [Ripple], t: Double, waterY: Double) {
        let ink = palette.ink
        for ripple in ripples {
            let age: Double = t - ripple.start
            guard age >= 0, age < Self.rippleLife else { continue }
            let u: Double = age / Self.rippleLife
            if ripple.y >= waterY - 4 {
                for k in 0..<3 {
                    let delay: Double = Double(k) * 0.18
                    let v: Double = (u - delay) / (1 - delay)
                    guard v > 0 else { continue }
                    let r: Double = 6 + v * 46
                    let opacity: Double = (1 - v) * 0.45
                    let ring = Path(ellipseIn: Self.rect(ripple.x - r, ripple.y - r * 0.32, r * 2, r * 0.64))
                    context.stroke(ring, with: .color(ink.opacity(opacity)), lineWidth: 1)
                }
            } else {
                let r: Double = 8 + u.squareRoot() * 40
                let opacity: Double = (1 - u) * 0.22
                context.fill(Self.circle(ripple.x, ripple.y, r), with: Self.glow(ink.opacity(opacity), ripple.x, ripple.y, inner: 0, outer: r))
                context.stroke(Self.circle(ripple.x, ripple.y, r * 0.92), with: .color(ink.opacity(opacity * 0.6)), lineWidth: 0.6)
            }
        }
    }

    // MARK: 柳 / 梅

    private var leafColor: Color? {
        switch season {
        case .spring: return Color(red: 0.55, green: 0.66, blue: 0.45)
        case .summer: return Color(red: 0.36, green: 0.52, blue: 0.38)
        case .autumn: return Color(red: 0.78, green: 0.62, blue: 0.3)
        case .winter: return nil
        }
    }

    /// 左上角伸出一根柳枝，柳条沿枝垂下，随风轻摆。春夏有叶，秋天叶子泛黄。
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

        // 柳条：从主枝上垂下，越靠近枝梢越短。上中下三段分别拼成一条 Path，越往下越细越淡
        var rng = SeededRandom(seed: 31)
        let strands = 15
        var segments: [Path] = [Path(), Path(), Path()]
        var leaves = Path()
        let leafAngle: Double = 28 * Double.pi / 180
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

            for segment in 0..<3 {
                let s = Double(segment)
                let u0: Double = s / 3
                let u1: Double = (s + 1) / 3
                segments[segment].move(to: Self.quad(origin, control, end, u0))
                for step in 1...6 {
                    let uu: Double = u0 + (u1 - u0) * Double(step) / 6
                    segments[segment].addLine(to: Self.quad(origin, control, end, uu))
                }
            }

            guard leaf != nil else { continue }
            for step in 2..<16 {
                let point = Self.quad(origin, control, end, Double(step) / 16)
                let side: Double = step.isMultiple(of: 2) ? 1 : -1
                let px: Double = Double(point.x) + side * 1.6
                let py: Double = Double(point.y)
                leaves.addPath(Self.leafShape, transform: Self.placed(px, py, angle: side * leafAngle))
            }
        }
        for segment in 0..<3 {
            let s = Double(segment)
            let opacity: Double = inkOpacity * (1 - s * 0.22)
            let width: Double = 1.3 - s * 0.35
            ctx.stroke(segments[segment], with: .color(p.ink.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        if let leaf {
            ctx.fill(leaves, with: .color(leaf.opacity(isNight ? 0.45 : 0.8)))
        }
    }

    /// 冬天：左上角一枝梅。老干折着伸进来，几根新枝向上挑，开着红梅；下雪时枝上积一层白
    private func drawPlum(_ context: GraphicsContext, w: Double, h: Double, t: Double, tx: Double, ty: Double) {
        let p = palette
        var ctx = context
        ctx.translateBy(x: tx * 20, y: ty * 6)
        ctx.rotate(by: .degrees(sin(t * 0.5) * 0.5))
        let branchInk: Color = p.ink.opacity(isNight ? 0.72 : 0.66)

        let limbs: [[(x: Double, y: Double)]] = [
            [(-0.04, 0.095), (0.07, 0.07), (0.15, 0.085), (0.24, 0.055), (0.33, 0.075), (0.42, 0.05)],
            [(0.07, 0.07), (0.10, 0.03), (0.13, 0.005)],
            [(0.15, 0.085), (0.18, 0.045), (0.215, 0.025)],
            [(0.24, 0.055), (0.27, 0.015)],
            [(0.33, 0.075), (0.37, 0.09), (0.45, 0.085)],
        ]
        let widths: [Double] = [3.4, 1.6, 1.5, 1.2, 1.4]
        for index in 0..<limbs.count {
            let limb = limbs[index]
            for k in 0..<(limb.count - 1) {
                var piece = Path()
                piece.move(to: Self.point(limb[k].x * w, limb[k].y * h))
                piece.addLine(to: Self.point(limb[k + 1].x * w, limb[k + 1].y * h))
                let taper: Double = 1 - Double(k) / Double(limb.count) * 0.6
                ctx.stroke(piece, with: .color(branchInk), style: StrokeStyle(lineWidth: widths[index] * taper, lineCap: .round))
            }
        }

        if weather == .snow {
            var snowLine = Path()
            let main = limbs[0]
            snowLine.move(to: Self.point(main[0].x * w, main[0].y * h - 1.6))
            for k in 1..<main.count {
                snowLine.addLine(to: Self.point(main[k].x * w, main[k].y * h - 1.6))
            }
            ctx.stroke(snowLine, with: .color(Color.white.opacity(isNight ? 0.5 : 0.85)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }

        // 梅花：五瓣，花心一点黄
        let blossoms: [(x: Double, y: Double, r: Double)] = [
            (0.10, 0.03, 3.8), (0.13, 0.006, 3.0), (0.18, 0.045, 3.6), (0.215, 0.025, 3.0), (0.27, 0.016, 3.4),
            (0.31, 0.068, 3.8), (0.37, 0.09, 3.2), (0.45, 0.085, 2.8), (0.05, 0.075, 3.0), (0.22, 0.065, 2.6), (0.40, 0.06, 2.8),
        ]
        var petals = Path()
        var hearts = Path()
        for b in blossoms {
            let cx: Double = b.x * w
            let cy: Double = b.y * h
            let r: Double = b.r
            for k in 0..<5 {
                let a: Double = Double(k) * 2 * Double.pi / 5 - Double.pi / 2
                let px: Double = cx + cos(a) * r * 0.55
                let py: Double = cy + sin(a) * r * 0.55
                petals.addEllipse(in: Self.rect(px - r * 0.5, py - r * 0.5, r, r))
            }
            hearts.addEllipse(in: Self.rect(cx - r * 0.22, cy - r * 0.22, r * 0.44, r * 0.44))
        }
        var buds = Path()
        let budSpots: [(x: Double, y: Double)] = [(0.135, -0.002), (0.275, 0.005), (0.455, 0.08), (0.02, 0.085)]
        for bud in budSpots {
            buds.addEllipse(in: Self.rect(bud.x * w - 1.6, bud.y * h - 1.6, 3.2, 3.2))
        }
        let bloom: Color = isNight ? Color(red: 0.78, green: 0.36, blue: 0.42) : Color(red: 0.80, green: 0.27, blue: 0.33)
        ctx.fill(petals, with: .color(bloom.opacity(0.9)))
        ctx.fill(hearts, with: .color(Color(red: 0.96, green: 0.84, blue: 0.55)))
        ctx.fill(buds, with: .color(Color(red: 0.58, green: 0.17, blue: 0.22)))
    }

    // MARK: 天气与季节

    private func drawAtmosphere(_ context: GraphicsContext, w: Double, h: Double, t: Double, tx: Double, ty: Double) {
        var ctx = context
        ctx.translateBy(x: tx * 10, y: ty * 4)
        switch weather {
        case .rain:
            drawRain(ctx, w: w, h: h, t: t)
        case .snow:
            drawSnow(ctx, w: w, h: h, t: t)
        case .clear, .mist:
            switch season {
            case .spring:
                drawPetals(ctx, w: w, h: h, t: t, color: Color(red: 0.91, green: 0.66, blue: 0.66).opacity(0.8), count: 20, seed: 2026)
            case .summer:
                if isNight { drawFireflies(ctx, w: w, h: h, t: t) }
            case .autumn:
                drawGinkgo(ctx, w: w, h: h, t: t)
            case .winter:
                drawPetals(ctx, w: w, h: h, t: t, color: Color(red: 0.8, green: 0.3, blue: 0.36).opacity(0.7), count: 9, seed: 1225)
            }
        }
    }

    /// 斜风细雨：一笔笔短而淡的墨线
    private func drawRain(_ context: GraphicsContext, w: Double, h: Double, t: Double) {
        var rng = SeededRandom(seed: 88)
        let spanX: Double = w + 80
        let spanY: Double = h + 40
        var streaks = Path()
        for _ in 0..<70 {
            let speed: Double = 180 + rng.next() * 80
            let x0: Double = rng.next() * spanX
            let y0: Double = rng.next() * spanY
            let length: Double = 10 + rng.next() * 12
            let y: Double = Self.wrap(y0 + t * speed, spanY) - 20
            let x: Double = Self.wrap(x0 - y * 0.22, spanX) - 40
            streaks.move(to: Self.point(x, y))
            streaks.addLine(to: Self.point(x - length * 0.22, y + length))
        }
        context.stroke(streaks, with: .color(palette.ink.opacity(isNight ? 0.3 : 0.2)), lineWidth: 0.7)
    }

    private func drawSnow(_ context: GraphicsContext, w: Double, h: Double, t: Double) {
        var rng = SeededRandom(seed: 2026)
        let spanX: Double = w + 40
        let spanY: Double = h + 20
        let flake: Color = isNight ? Color.white.opacity(0.85) : Color(red: 0.56, green: 0.61, blue: 0.64).opacity(0.55)
        var flakes = Path()
        for _ in 0..<46 {
            let speed: Double = 10 + rng.next() * 18
            let x0: Double = rng.next() * spanX
            let y0: Double = rng.next() * spanY
            let y: Double = Self.wrap(y0 + t * speed, spanY) - 10
            let x: Double = Self.wrap(x0 + sin(t * 0.6 + x0) * 12, spanX) - 20
            let r: Double = 0.9 + rng.next() * 1.5
            flakes.addEllipse(in: Self.rect(x, y, r * 2, r * 2))
        }
        context.fill(flakes, with: .color(flake))
    }

    /// 飘落的花瓣：一边转一边翻（横向压扁模拟翻面）
    private func drawPetals(_ context: GraphicsContext, w: Double, h: Double, t: Double, color: Color, count: Int, seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let spanX: Double = w + 40
        let spanY: Double = h + 20
        var petals = Path()
        for _ in 0..<count {
            let speed: Double = 14 + rng.next() * 14
            let x0: Double = rng.next() * spanX
            let y0: Double = rng.next() * spanY
            let spin: Double = rng.next() * 6
            let y: Double = Self.wrap(y0 + t * speed, spanY) - 10
            let x: Double = Self.wrap(x0 + t * speed * 0.6, spanX) - 20
            let flip: Double = 0.35 + 0.65 * abs(cos(t * 1.7 + spin))
            petals.addPath(Self.petalShape, transform: Self.placed(x, y, angle: t * 1.4 + spin, scaleX: flip))
        }
        context.fill(petals, with: .color(color))
    }

    /// 银杏叶：一把把小扇子，左右摆着落下
    private func drawGinkgo(_ context: GraphicsContext, w: Double, h: Double, t: Double) {
        var rng = SeededRandom(seed: 2026)
        let spanX: Double = w + 40
        let spanY: Double = h + 20
        var fans = Path()
        for _ in 0..<15 {
            let speed: Double = 12 + rng.next() * 12
            let x0: Double = rng.next() * spanX
            let y0: Double = rng.next() * spanY
            let spin: Double = rng.next() * 6
            let y: Double = Self.wrap(y0 + t * speed, spanY) - 10
            let x: Double = Self.wrap(x0 + sin(t * 0.8 + spin) * 18 + t * 4, spanX) - 20
            fans.addPath(Self.ginkgoShape, transform: Self.placed(x, y, angle: sin(t + spin) * 1.2))
        }
        context.fill(fans, with: .color(Color(red: 0.83, green: 0.64, blue: 0.24).opacity(0.85)))
    }

    private func drawFireflies(_ context: GraphicsContext, w: Double, h: Double, t: Double) {
        var rng = SeededRandom(seed: 2026)
        let firefly = Color(red: 0.9, green: 0.95, blue: 0.6)
        for _ in 0..<16 {
            let x0: Double = rng.next() * w
            let y0: Double = h * (0.45 + rng.next() * 0.45)
            let phase: Double = rng.next() * 6
            let x: Double = x0 + sin(t * 0.5 + phase) * 14
            let y: Double = y0 + cos(t * 0.4 + phase) * 8
            let blink: Double = max(0, sin(t * 1.6 + phase))
            guard blink > 0.02 else { continue }
            context.fill(Self.circle(x, y, 7), with: Self.glow(firefly.opacity(0.6 * blink), x, y, inner: 0, outer: 7))
        }
    }
}
