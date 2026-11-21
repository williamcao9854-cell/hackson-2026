import Foundation

/// 二十四节气与时辰：让首页的山水随着真实的季节和一天中的时间变化。
///
/// 节气按太阳视黄经计算（每 15° 一个节气，0° 为春分），
/// 使用 Meeus《天文算法》的低精度公式，误差在一小时以内，足够判断"今天是哪个节气"。
struct SolarTerm: Equatable, Sendable {
    /// 0 = 春分，1 = 清明 …… 23 = 惊蛰
    let index: Int

    static let names = [
        "春分", "清明", "谷雨", "立夏", "小满", "芒种",
        "夏至", "小暑", "大暑", "立秋", "处暑", "白露",
        "秋分", "寒露", "霜降", "立冬", "小雪", "大雪",
        "冬至", "小寒", "大寒", "立春", "雨水", "惊蛰",
    ]

    /// 每个节气的第一候（七十二候，出自《逸周书·时训解》）
    static let firstPentads = [
        "玄鸟至", "桐始华", "萍始生", "蝼蝈鸣", "苦菜秀", "螳螂生",
        "鹿角解", "温风至", "腐草为萤", "凉风至", "鹰乃祭鸟", "鸿雁来",
        "雷始收声", "鸿雁来宾", "豺乃祭兽", "水始冰", "虹藏不见", "鹖鴠不鸣",
        "蚯蚓结", "雁北乡", "鸡始乳", "东风解冻", "獭祭鱼", "桃始华",
    ]

    enum Season: String, Sendable {
        case spring, summer, autumn, winter
    }

    var name: String { Self.names[index] }
    var pentad: String { Self.firstPentads[index] }

    var season: Season {
        switch index {
        case 21, 22, 23, 0, 1, 2: .spring
        case 3...8: .summer
        case 9...14: .autumn
        default: .winter
        }
    }

    init(index: Int) {
        self.index = ((index % 24) + 24) % 24
    }

    init(date: Date) {
        self.init(index: Int(Self.solarLongitude(at: date) / 15))
    }

    /// 太阳视黄经（度，0..<360）
    static func solarLongitude(at date: Date) -> Double {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545.0) / 36_525
        func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }

        let meanLongitude = 280.46646 + 36_000.76983 * t + 0.0003032 * t * t
        let meanAnomaly = 357.52911 + 35_999.05029 * t - 0.0001537 * t * t
        let center = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(rad(meanAnomaly))
            + (0.019993 - 0.000101 * t) * sin(rad(2 * meanAnomaly))
            + 0.000289 * sin(rad(3 * meanAnomaly))
        let omega = 125.04 - 1_934.136 * t
        let apparent = meanLongitude + center - 0.00569 - 0.00478 * sin(rad(omega))
        let normalized = apparent.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
}

/// 一天中的时辰，决定天色
enum DayPhase: Sendable {
    case dawn, day, dusk, night

    init(date: Date, calendar: Calendar = .current) {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<7: self = .dawn
        case 7..<17: self = .day
        case 17..<19: self = .dusk
        default: self = .night
        }
    }
}
