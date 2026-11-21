import Foundation

/// 这件物品陪伴了主人多久。决定物灵的"年纪"、磨损感与性格。
enum Companionship: String, Codable, CaseIterable, Identifiable, Sendable {
    case days
    case months
    case aboutAYear
    case years
    case decade

    var id: String { rawValue }

    /// 选项上显示的文字
    var title: String {
        switch self {
        case .days: "几天"
        case .months: "几个月"
        case .aboutAYear: "一年左右"
        case .years: "好几年"
        case .decade: "十年以上"
        }
    }

    /// 用在句子里："陪我走过了___"
    var phrase: String {
        switch self {
        case .days: "这几天"
        case .months: "这几个月"
        case .aboutAYear: "这一年"
        case .years: "这么多年"
        case .decade: "十多年"
        }
    }

    /// 物灵的灵龄称呼
    var spiritAge: String {
        switch self {
        case .days: "初生"
        case .months: "幼灵"
        case .aboutAYear: "一岁"
        case .years: "老友"
        case .decade: "古灵"
        }
    }

    /// 0（全新）… 1（饱经岁月）
    var wear: Double {
        switch self {
        case .days: 0.0
        case .months: 0.25
        case .aboutAYear: 0.45
        case .years: 0.7
        case .decade: 1.0
        }
    }

    /// 给图像模型的英文描述
    var promptDescription: String {
        switch self {
        case .days:
            "It has only just arrived in its owner's life: crisp and new, curious wide eyes, a newborn spirit full of wonder."
        case .months:
            "It has been used for a few months: lightly worn, familiar and settled, a young spirit with a shy, friendly expression."
        case .aboutAYear:
            "It has been with its owner for about a year, through all four seasons: gently worn, softened edges, a calm and loyal expression."
        case .years:
            "It has been cherished for many years: softly faded color, small scuffs and creases worn proudly like badges of honor, a warm and wise expression."
        case .decade:
            "It has been cherished for more than a decade: deeply weathered, mended and faded, an ancient, serene spirit with kind, knowing eyes."
        }
    }
}
