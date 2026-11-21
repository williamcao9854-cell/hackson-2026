import Foundation

/// 把物灵的原料拼成给图像模型的提示词。
///
/// 隐私：只使用物品类别、颜色、陪伴时长。用户的照片和记忆文字都不会出现在这里。
enum SpiritPrompt {
    /// 所有物灵共用的画风，保证图鉴里的每一张都像出自同一位画师之手。
    /// 背景色与 App 的 paper 色（#F4F0E8）一致，插画会自然融进页面。
    static let style = """
    Style: delicate watercolor washes with fine, confident sumi ink linework, \
    on warm off-white washi paper (hex #F4F0E8) with a subtle paper-fiber texture. \
    Muted, earthy palette with one small touch of vermilion red. \
    Full-body character, centered, with generous empty space all around. \
    Whimsical yet dignified, quiet and warm, like an illustration from a beautifully printed Japanese picture book. \
    No text, no letters, no signature, no border, no frame, no background scenery.
    """

    static func make(for seed: SpiritSeed) -> String {
        let object = seed.object.english
        let colors = colorPhrase(for: seed)
        return """
        A tsukumogami: a gentle spirit from Japanese folklore that has awakened inside a well-loved \(object). \
        The spirit's body is clearly formed from the \(object) itself, so anyone can recognize what it was, \
        with small expressive eyes and tiny limbs that feel natural to its shape. \
        Main colors: \(colors). \
        \(seed.companionship.promptDescription)

        \(style)
        """
    }

    private static func colorPhrase(for seed: SpiritSeed) -> String {
        let names = seed.palette.prefix(3).map { ColorNaming.traditionalColor(for: $0).english }
        var unique: [String] = []
        for name in names where !unique.contains(name) { unique.append(name) }
        if unique.isEmpty { unique = [seed.color.english] }
        return unique.joined(separator: ", ")
    }
}
