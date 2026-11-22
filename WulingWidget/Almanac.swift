import Foundation

/// 小组件自己的"黄历"：节气、物候、时辰、农历日期、节气来信。
///
/// 小组件是单独的扩展进程，免费开发者账户用不了 App Groups，读不到 App 的数据，
/// 所以这里的一切都只靠"今天的日期"算出来：节气按太阳视黄经（和 App 里的 SolarTerm 同一套 Meeus 公式），
/// 来信的文字和 App 的 LetterPost.seasonalLines 相同，写信的是 App 里的示例物灵「青履君」。
enum Almanac {
    /// 0 = 春分 …… 23 = 惊蛰（与 App 的 SolarTerm.names 顺序相同）
    static let names = [
        "春分", "清明", "谷雨", "立夏", "小满", "芒种",
        "夏至", "小暑", "大暑", "立秋", "处暑", "白露",
        "秋分", "寒露", "霜降", "立冬", "小雪", "大雪",
        "冬至", "小寒", "大寒", "立春", "雨水", "惊蛰",
    ]

    /// 七十二候
    static let pentads: [[String]] = [
        ["玄鸟至", "雷乃发声", "始电"], ["桐始华", "田鼠化为鴽", "虹始见"], ["萍始生", "鸣鸠拂其羽", "戴胜降于桑"],
        ["蝼蝈鸣", "蚯蚓出", "王瓜生"], ["苦菜秀", "靡草死", "麦秋至"], ["螳螂生", "鵙始鸣", "反舌无声"],
        ["鹿角解", "蜩始鸣", "半夏生"], ["温风至", "蟋蟀居宇", "鹰始挚"], ["腐草为萤", "土润溽暑", "大雨时行"],
        ["凉风至", "白露降", "寒蝉鸣"], ["鹰乃祭鸟", "天地始肃", "禾乃登"], ["鸿雁来", "玄鸟归", "群鸟养羞"],
        ["雷始收声", "蛰虫坯户", "水始涸"], ["鸿雁来宾", "雀入大水为蛤", "菊有黄华"], ["豺乃祭兽", "草木黄落", "蛰虫咸俯"],
        ["水始冰", "地始冻", "雉入大水为蜃"], ["虹藏不见", "天气上升地气下降", "闭塞而成冬"], ["鹖鴠不鸣", "虎始交", "荔挺出"],
        ["蚯蚓结", "麋角解", "水泉动"], ["雁北乡", "鹊始巢", "雉始雊"], ["鸡始乳", "征鸟厉疾", "水泽腹坚"],
        ["东风解冻", "蛰虫始振", "鱼陟负冰"], ["獭祭鱼", "候雁北", "草木萌动"], ["桃始华", "仓庚鸣", "鹰化为鸠"],
    ]

    /// 节气来信的第一句（与 App 的 LetterPost.seasonalLines 相同）
    static let letterLines = [
        "春分了，燕子回来了。昼夜一样长，日子不紧不慢。",
        "清明了，桐花开了。河上起了薄雾，我在雾里很好。",
        "谷雨了，水面生了新萍。雨落在上面，一点声音也没有。",
        "立夏了，夜里开始有虫鸣。白天长了，日子也亮堂起来。",
        "小满了，麦子快熟，还没全熟。小满就好，不必太满。",
        "芒种了，田里正忙。你也在忙吧，忙完记得歇一歇。",
        "夏至了，一年里白天最长的一天。愿你今天有一段闲。",
        "小暑了，风是暖的。树荫底下，最适合打个盹。",
        "大暑了，萤火虫出来了。我借了几只，替你照一照夜路。",
        "立秋了，第一阵凉风吹过水面。早晚添件衣裳。",
        "处暑了，暑气要走了。稻子熟了，日子也慢慢沉下来。",
        "白露了，草尖上挂了露水。鸿雁往南飞，我抬头看了很久。",
        "秋分了，雷声收起来了。这里很安静，愿你那边也安静些。",
        "寒露了，菊花快开了。早晚凉，出门别忘了外套。",
        "霜降了，叶子一片片落下来。落下来也很好，像我一样。",
        "立冬了，水面开始结薄冰。我这里不冷，别担心。",
        "小雪了，彩虹藏起来了，要等明年。好东西都值得等。",
        "大雪了，鸟儿都不叫了。这么安静的日子，适合想起一些旧事。",
        "冬至了，一年里夜最长的一天。过了今天，白天会一点点长回来。",
        "小寒了，大雁开始往北飞。冷是冷，春天已经在路上了。",
        "大寒了，一年里最冷的时候。熬过这几天，就是春天。",
        "立春了，东风吹化了河上的冰。水又开始流了。",
        "雨水了，雨落得细细的。草快冒出来了。",
        "惊蛰了，一声春雷，桃花开了。万物都醒了，愿你也有新的开始。",
    ]

    /// 示例物灵（和 App 里 LetterPost.sampleSender 一样）
    static let sampleSpirit = "青履君"

    enum Season { case spring, summer, autumn, winter }

    enum Phase: String { case dawn, day, dusk, night }

    struct Term: Equatable {
        let index: Int
        /// 这一候：0、1、2
        let pentadIndex: Int
        /// 本节气走了多少（0…1）
        let progress: Double

        var name: String { Almanac.names[index] }
        var pentad: String { Almanac.pentads[index][pentadIndex] }
        var letterLine: String { Almanac.letterLines[index] }

        var season: Season {
            switch index {
            case 21, 22, 23, 0, 1, 2: .spring
            case 3...8: .summer
            case 9...14: .autumn
            default: .winter
            }
        }
    }

    static func term(at date: Date) -> Term {
        let longitude = solarLongitude(at: date)
        let index = min(23, Int(longitude / 15))
        let within = longitude - Double(index) * 15
        return Term(index: index, pentadIndex: min(2, Int(within / 5)), progress: within / 15)
    }

    static func phase(at date: Date, calendar: Calendar = .current) -> Phase {
        switch calendar.component(.hour, from: date) {
        case 5..<7: .dawn
        case 7..<17: .day
        case 17..<19: .dusk
        default: .night
        }
    }

    /// 下一个节气从什么时候开始（先按 6 小时一步往前找，再二分到一分钟以内）
    static func nextTermStart(after date: Date) -> (date: Date, term: Term) {
        let current = term(at: date).index
        var low = date
        var high = date
        repeat {
            low = high
            high = high.addingTimeInterval(6 * 3600)
        } while term(at: high).index == current
        while high.timeIntervalSince(low) > 60 {
            let mid = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            if term(at: mid).index == current { low = mid } else { high = mid }
        }
        return (high, term(at: high))
    }

    /// 离下一个节气还有几天（按日历日算，今天开始就是 0）
    static func daysUntilNextTerm(from date: Date, calendar: Calendar = .current) -> (days: Int, term: Term) {
        let next = nextTermStart(after: date)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: next.date)).day ?? 0
        return (max(0, days), next.term)
    }

    // MARK: - 农历

    private static let lunarMonths = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
    private static let lunarDays = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
    ]
    private static let stems = Array("甲乙丙丁戊己庚辛壬癸")
    private static let branches = Array("子丑寅卯辰巳午未申酉戌亥")

    /// 例如 "十月初四"、"闰六月十五"
    static func lunarDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = timeZone
        let parts = chinese.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day,
              (1...12).contains(month), (1...30).contains(day) else { return "" }
        let leap = parts.isLeapMonth == true ? "闰" : ""
        return "\(leap)\(lunarMonths[month - 1])月\(lunarDays[day - 1])"
    }

    /// 农历年的干支，例如 "丙午年"
    static func ganzhiYear(_ date: Date, timeZone: TimeZone = .current) -> String {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = timeZone
        guard let year = chinese.dateComponents([.year], from: date).year, year > 0 else { return "" }
        let cycle = (year - 1) % 60
        return "\(stems[cycle % 10])\(branches[cycle % 12])年"
    }

    // MARK: - 时间线

    /// 接下来 hours 小时里，画面该变的时刻：时辰交替（5、7、17、19 点）、午夜（农历和倒计时变）、节气交接
    static func boundaries(after date: Date, hours: Int = 48, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        let end = date.addingTimeInterval(Double(hours) * 3600)
        var day = calendar.startOfDay(for: date)
        while day < end {
            for hour in [0, 5, 7, 17, 19] {
                if let moment = calendar.date(byAdding: .hour, value: hour, to: day), moment > date, moment <= end {
                    result.append(moment)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let termStart = nextTermStart(after: date).date
        if termStart <= end { result.append(termStart) }
        return Array(Set(result)).sorted()
    }

    // MARK: - 太阳视黄经（度，0..<360）

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
