import Foundation

/// 唤醒物灵需要的全部原料。
struct SpiritSeed: Sendable {
    var object: ObjectKind
    /// 用户可能改过的中文名，例如把"跑鞋"改成"第一双跑鞋"
    var displayName: String
    var color: TraditionalColor
    var palette: [RGB]
    var companionship: Companionship
    /// 用户写下的记忆。只在设备端使用，不会发给图像 API。
    var memory: String
}

/// 物灵的"身份证"。
struct SpiritProfile: Codable, Hashable, Sendable {
    /// 名字，例如 青履丸
    var name: String
    /// 称号，例如 跑鞋之灵
    var epithet: String
    /// 一两句性格描述
    var personality: String
    /// 送别时输入框里的提示语
    var farewellSuggestion: String
}

/// 稳定哈希（FNV-1a）。Swift 自带的 hashValue 每次启动都不一样，这里需要"同一件东西每次都得到同一个名字"。
enum StableHash {
    static func value(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    static func pick<T>(_ options: [T], seed: String, salt: String = "") -> T {
        precondition(!options.isEmpty)
        let index = Int(value(seed + "#" + salt) % UInt64(options.count))
        return options[index]
    }
}

/// 不依赖任何模型的起名器。Foundation Models 不可用时使用。
enum TemplateSpiritWriter {
    private static let endings = ["丸", "子", "君", "郎", "姬"]

    private static func companionshipLine(_ c: Companionship) -> String {
        switch c {
        case .days: "它才刚认识你，对这个世界充满好奇。"
        case .months: "它已经记住了你的习惯，总是安静地待在老地方。"
        case .aboutAYear: "春夏秋冬它都在，见过你最平常的样子。"
        case .years: "它身上的每一道痕迹，都是和你一起留下的。"
        case .decade: "十多年过去，它比你想象的更了解你。"
        }
    }

    static func write(for seed: SpiritSeed) -> SpiritProfile {
        let key = seed.object.english + "|" + seed.color.character + "|" + seed.companionship.rawValue
        let middle = StableHash.pick(seed.object.family.nameCharacters, seed: key, salt: "middle")
        let ending = StableHash.pick(endings, seed: key, salt: "ending")
        let familyLine = StableHash.pick(seed.object.family.personalityLines, seed: key, salt: "line")

        return SpiritProfile(
            name: seed.color.character + middle + ending,
            epithet: "\(seed.displayName)之灵",
            personality: familyLine + companionshipLine(seed.companionship),
            farewellSuggestion: "谢谢你，陪我\(seed.companionship.phrase)。"
        )
    }
}
