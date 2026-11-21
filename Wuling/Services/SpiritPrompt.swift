import Foundation

/// 把物灵的原料拼成给图像模型的提示词。
///
/// 隐私：只使用物品类别、用户给它起的称呼、颜色、陪伴时长、岁月痕迹。
/// 用户的照片和记忆文字都不会出现在这里。
enum SpiritPrompt {
    /// 所有物灵共用的画风，保证图鉴里的每一张都像出自同一位画师之手。
    /// 背景色与 App 的 paper 色（#F4F0E8）一致，插画会自然融进页面。
    static let style = """
    Style: delicate watercolor washes with fine, confident ink-brush linework, \
    on warm off-white rice paper (hex #F4F0E8) with a subtle paper-fiber texture. \
    Muted, earthy palette with one small touch of vermilion red. \
    Full-body character, centered, with generous empty space all around. \
    Whimsical yet dignified, quiet and warm, like an illustration from a beautifully printed East Asian picture book. \
    No text, no letters, no signature, no border, no frame, no background scenery.
    """

    static func make(for seed: SpiritSeed) -> String {
        let object = seed.object.english
        var lines: [String] = []
        lines.append("""
        A gentle object spirit from East Asian folklore, the kind said to awaken inside things that have been cherished for a long time. \
        This one has awakened inside a well-loved \(object)\(nickname(for: seed)). \
        The spirit's body is clearly formed from the \(object) itself, so anyone can recognize what it was, \
        with small expressive eyes and tiny limbs that feel natural to its shape.
        """)
        lines.append("Main colors: \(colorPhrase(for: seed)).")
        if !seed.wearMarks.isEmpty {
            lines.append("Visible marks of its long life, drawn with affection: \(seed.wearMarks.map(\.promptPhrase).joined(separator: ", ")).")
        }
        lines.append(seed.companionship.promptDescription)
        return lines.joined(separator: " ") + "\n\n" + style
    }

    /// 用户改过名字时（比如"外婆的闹钟"），把这个称呼也告诉模型
    private static func nickname(for seed: SpiritSeed) -> String {
        let name = seed.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != seed.object.chinese else { return "" }
        return " (its owner lovingly calls it \u{201C}\(name)\u{201D})"
    }

    private static func colorPhrase(for seed: SpiritSeed) -> String {
        let names = seed.palette.prefix(3).map { ColorNaming.traditionalColor(for: $0).english }
        var unique: [String] = []
        for name in names where !unique.contains(name) { unique.append(name) }
        if unique.isEmpty { unique = [seed.color.english] }
        return unique.joined(separator: ", ")
    }
}
