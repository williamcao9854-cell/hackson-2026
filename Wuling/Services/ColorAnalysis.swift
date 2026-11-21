import Foundation

/// 0…1 的 RGB 颜色，纯数值，方便在任何线程里计算。
struct RGB: Hashable, Codable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    var hex: String {
        func c(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >> 8) & 0xFF) / 255
        b = Double(value & 0xFF) / 255
    }

    /// 色相（0…360）、饱和度、亮度（HSL）
    var hsl: (h: Double, s: Double, l: Double) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        guard maxV != minV else { return (0, 0, l) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if maxV == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h *= 60
        return (h, s, l)
    }

    func distanceSquared(to other: RGB) -> Double {
        let dr = r - other.r, dg = g - other.g, db = b - other.b
        return dr * dr + dg * dg + db * db
    }
}

/// 中国传统色名。物灵名字的第一个字就来自这里，例如 青履丸 的"青"。
struct TraditionalColor: Hashable, Sendable {
    /// 单字，用在名字里
    var character: String
    /// 完整色名，用在描述里
    var name: String
    /// 给图像模型的英文描述
    var english: String
}

enum ColorNaming {
    static func traditionalColor(for color: RGB) -> TraditionalColor {
        let (h, s, l) = color.hsl
        if l < 0.16 { return TraditionalColor(character: "墨", name: "墨色", english: "ink black") }
        if s < 0.14 {
            if l > 0.8 { return TraditionalColor(character: "白", name: "月白", english: "moon white") }
            if l > 0.45 { return TraditionalColor(character: "银", name: "银灰", english: "silver grey") }
            return TraditionalColor(character: "灰", name: "黛灰", english: "charcoal grey")
        }
        switch h {
        case 15..<45 where l < 0.42:
            return TraditionalColor(character: "栗", name: "栗色", english: "chestnut brown")
        case 15..<40:
            return TraditionalColor(character: "柿", name: "柿色", english: "persimmon orange")
        case 40..<68:
            return TraditionalColor(character: "黄", name: "缃色", english: "ochre yellow")
        case 68..<165:
            return TraditionalColor(character: "翠", name: "翠色", english: "jade green")
        case 165..<200:
            return TraditionalColor(character: "青", name: "天青", english: "celadon blue-green")
        case 200..<255:
            return TraditionalColor(character: "靛", name: "靛蓝", english: "indigo blue")
        case 255..<295:
            return TraditionalColor(character: "紫", name: "藤紫", english: "wisteria purple")
        case 295..<345:
            return TraditionalColor(character: "桃", name: "桃红", english: "peach blossom pink")
        default:
            return TraditionalColor(character: "朱", name: "朱红", english: "vermilion red")
        }
    }
}

/// 一个极简的 k-means，用来从抠出的物品里找出 2～3 个主色。
enum KMeans {
    static func dominantColors(in pixels: [RGB], k: Int = 3, iterations: Int = 10) -> [RGB] {
        guard !pixels.isEmpty else { return [] }
        let k = min(k, pixels.count)
        // 确定性初始化：均匀取样，保证同一张图每次结果一样
        var centroids = (0..<k).map { pixels[($0 * pixels.count) / k] }
        var assignment = [Int](repeating: 0, count: pixels.count)

        for _ in 0..<iterations {
            for (i, p) in pixels.enumerated() {
                var best = 0
                var bestDistance = Double.greatestFiniteMagnitude
                for (j, c) in centroids.enumerated() {
                    let d = p.distanceSquared(to: c)
                    if d < bestDistance { bestDistance = d; best = j }
                }
                assignment[i] = best
            }
            var sums = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: k)
            var counts = [Int](repeating: 0, count: k)
            for (i, p) in pixels.enumerated() {
                let j = assignment[i]
                sums[j].r += p.r; sums[j].g += p.g; sums[j].b += p.b
                counts[j] += 1
            }
            for j in 0..<k where counts[j] > 0 {
                let n = Double(counts[j])
                centroids[j] = RGB(r: sums[j].r / n, g: sums[j].g / n, b: sums[j].b / n)
            }
        }

        var counts = [Int](repeating: 0, count: k)
        for j in assignment { counts[j] += 1 }
        return zip(centroids, counts)
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
