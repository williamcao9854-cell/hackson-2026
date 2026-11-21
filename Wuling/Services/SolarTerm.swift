import Foundation

/// 二十四节气与时辰：让首页的山水随着真实的季节和一天中的时间变化。
///
/// 节气按太阳视黄经计算（每 15° 一个节气，0° 为春分），
/// 使用 Meeus《天文算法》的低精度公式，误差在一小时以内，足够判断"今天是哪个节气"。
struct SolarTerm: Equatable, Sendable {
    /// 0 = 春分，1 = 清明 …… 23 = 惊蛰
    let index: Int
    /// 本节气的第几候：0、1、2（每候 5°，约五天）
    let pentadIndex: Int

    static let names = [
        "春分", "清明", "谷雨", "立夏", "小满", "芒种",
        "夏至", "小暑", "大暑", "立秋", "处暑", "白露",
        "秋分", "寒露", "霜降", "立冬", "小雪", "大雪",
        "冬至", "小寒", "大寒", "立春", "雨水", "惊蛰",
    ]

    /// 七十二候（出自《逸周书·时训解》），每个节气三候，顺序与 names 相同
    static let pentads: [[String]] = [
        ["玄鸟至", "雷乃发声", "始电"],                 // 春分
        ["桐始华", "田鼠化为鴽", "虹始见"],             // 清明
        ["萍始生", "鸣鸠拂其羽", "戴胜降于桑"],         // 谷雨
        ["蝼蝈鸣", "蚯蚓出", "王瓜生"],                 // 立夏
        ["苦菜秀", "靡草死", "麦秋至"],                 // 小满
        ["螳螂生", "鵙始鸣", "反舌无声"],               // 芒种
        ["鹿角解", "蜩始鸣", "半夏生"],                 // 夏至
        ["温风至", "蟋蟀居宇", "鹰始挚"],               // 小暑
        ["腐草为萤", "土润溽暑", "大雨时行"],           // 大暑
        ["凉风至", "白露降", "寒蝉鸣"],                 // 立秋
        ["鹰乃祭鸟", "天地始肃", "禾乃登"],             // 处暑
        ["鸿雁来", "玄鸟归", "群鸟养羞"],               // 白露
        ["雷始收声", "蛰虫坯户", "水始涸"],             // 秋分
        ["鸿雁来宾", "雀入大水为蛤", "菊有黄华"],       // 寒露
        ["豺乃祭兽", "草木黄落", "蛰虫咸俯"],           // 霜降
        ["水始冰", "地始冻", "雉入大水为蜃"],           // 立冬
        ["虹藏不见", "天气上升地气下降", "闭塞而成冬"], // 小雪
        ["鹖鴠不鸣", "虎始交", "荔挺出"],               // 大雪
        ["蚯蚓结", "麋角解", "水泉动"],                 // 冬至
        ["雁北乡", "鹊始巢", "雉始雊"],                 // 小寒
        ["鸡始乳", "征鸟厉疾", "水泽腹坚"],             // 大寒
        ["东风解冻", "蛰虫始振", "鱼陟负冰"],           // 立春
        ["獭祭鱼", "候雁北", "草木萌动"],               // 雨水
        ["桃始华", "仓庚鸣", "鹰化为鸠"],               // 惊蛰
    ]

    enum Season: String, Sendable {
        case spring, summer, autumn, winter
    }

    var name: String { Self.names[index] }
    /// 当下这一候
    var pentad: String { Self.pentads[index][pentadIndex] }

    var season: Season {
        switch index {
        case 21, 22, 23, 0, 1, 2: .spring
        case 3...8: .summer
        case 9...14: .autumn
        default: .winter
        }
    }

    init(index: Int, pentadIndex: Int = 0) {
        self.index = ((index % 24) + 24) % 24
        self.pentadIndex = min(2, max(0, pentadIndex))
    }

    init(date: Date) {
        let longitude = Self.solarLongitude(at: date)
        let index = Int(longitude / 15)
        let withinTerm = longitude - Double(index) * 15
        self.init(index: index, pentadIndex: Int(withinTerm / 5))
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
