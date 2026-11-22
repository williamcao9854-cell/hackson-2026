import Foundation

/// 节气来信：送别、传出过的物灵，每逢节气、或送别的周年，会托河灯（或鸿雁）捎回一张短笺。
///
/// 不改数据表：谁寄、什么时候寄、写什么，都由物灵已有的信息（送别日期、名字、记忆、物品类别）
/// 加上今天的节气算出来；读过哪几封只记一串编号在 UserDefaults 里。
struct SeasonalLetter: Identifiable, Equatable, Sendable {
    enum Occasion: Equatable, Sendable {
        case solarTerm
        /// 送别第几年
        case anniversary(years: Int)
    }

    /// 送别的物灵托河灯，传出去的物灵托鸿雁
    enum Messenger: Equatable, Sendable {
        case lantern, goose

        var title: String { self == .lantern ? "河灯" : "鸿雁" }
    }

    /// 读过以后记下这个编号，同一封信不会再来
    let id: String
    let occasion: Occasion
    let messenger: Messenger
    let term: SolarTerm
    let spiritName: String
    /// 信封上的一句：你在去年秋天送别的「青履君」，托河灯捎来一张短笺。
    let arrival: String
    /// 信的正文，每段从新的一列写起
    let paragraphs: [String]
    /// 落款日期：丙午年 · 立冬
    let dateline: String

    var fullText: String {
        ([arrival] + paragraphs + ["\(spiritName)", dateline]).joined(separator: "\n")
    }
}

enum LetterPost {
    /// 寄信的物灵（从 Spirit 取出需要的几项，方便在没有 SwiftData 的地方测试）
    struct Sender: Equatable, Sendable {
        var id: String
        var name: String
        var family: ObjectFamily
        var memory: String
        var companionship: Companionship
        var departedAt: Date
        var isRelayed: Bool
    }

    static let readKey = "wuling.letters.read"

    /// 送别后至少过几天，才会收到第一封节气来信
    static let quietDays = 5
    /// 周年那天没打开 App 也不要紧：之后两天内还能收到
    static let anniversaryWindow = 0...2

    // MARK: - 今天有没有信

    /// 今天该收到的那一封（不管读没读过）。周年信优先，其次是节气来信。
    static func letter(on date: Date, from senders: [Sender], calendar: Calendar = .current) -> SeasonalLetter? {
        let term = SolarTerm(date: date)

        let anniversaries = senders.compactMap { sender in
            anniversaryYears(of: sender.departedAt, on: date, calendar: calendar).map { (sender, $0) }
        }
        if let (sender, years) = anniversaries.sorted(by: { $0.0.departedAt < $1.0.departedAt }).first {
            let year = calendar.component(.year, from: date)
            return compose(from: sender, occasion: .anniversary(years: years), term: term, on: date,
                           id: "anniversary-\(sender.id)-\(year)", calendar: calendar)
        }

        guard let quietLimit = calendar.date(byAdding: .day, value: -quietDays, to: date) else { return nil }
        let eligible = senders.filter { $0.departedAt <= quietLimit }.sorted { $0.id < $1.id }
        guard !eligible.isEmpty else { return nil }
        let id = "term-\(termYear(term, on: date, calendar: calendar))-\(term.index)"
        let sender = StableHash.pick(eligible, seed: id)
        return compose(from: sender, occasion: .solarTerm, term: term, on: date, id: id, calendar: calendar)
    }

    /// 演示：不用等节气，现在就来一封。优先用最近送别的物灵；图鉴里一个也没有时，用一位示例物灵。
    static func demo(on date: Date, term: SolarTerm, from senders: [Sender], calendar: Calendar = .current) -> SeasonalLetter {
        let sender = senders.max { $0.departedAt < $1.departedAt } ?? sampleSender(before: date, calendar: calendar)
        return compose(from: sender, occasion: .solarTerm, term: term, on: date,
                       id: "demo-\(Int(date.timeIntervalSince1970))", calendar: calendar)
    }

    static func sampleSender(before date: Date, calendar: Calendar = .current) -> Sender {
        Sender(id: "sample", name: "青履君", family: .footwear, memory: "高三那年，它陪我跑完了每一个清晨。",
               companionship: .years,
               departedAt: calendar.date(byAdding: .day, value: -400, to: date) ?? date,
               isRelayed: false)
    }

    // MARK: - 已读

    static func isRead(_ id: String, in stored: String) -> Bool {
        stored.split(separator: "|").contains { $0 == id }
    }

    /// 记下读过的信，只留最近 40 封
    static func markingRead(_ id: String, in stored: String) -> String {
        var ids = stored.split(separator: "|").map(String.init).filter { $0 != id }
        ids.append(id)
        return ids.suffix(40).joined(separator: "|")
    }

    // MARK: - 写信

    static func compose(from sender: Sender, occasion: SeasonalLetter.Occasion, term: SolarTerm, on date: Date,
                        id: String, calendar: Calendar = .current) -> SeasonalLetter {
        let messenger: SeasonalLetter.Messenger = sender.isRelayed ? .goose : .lantern
        let verb = sender.isRelayed ? "传出" : "送别"

        let arrival: String
        let opening: String
        switch occasion {
        case .solarTerm:
            arrival = "\(when(sender.departedAt, from: date, calendar: calendar))\(verb)的「\(sender.name)」，托\(messenger.title)捎来一张短笺。"
            opening = seasonalLines[term.index]
        case let .anniversary(years):
            // 周年当天没打开 App，晚一两天收到时就不说"今天"
            let sameDay = calendar.dateComponents([.month, .day], from: sender.departedAt)
                == calendar.dateComponents([.month, .day], from: date)
            let ago = "\(chineseCount(years))年前的" + (sameDay ? "今天" : "这几天")
            arrival = "\(ago)，你\(verb)了「\(sender.name)」。它托\(messenger.title)捎来一张短笺。"
            opening = sender.isRelayed
                ? "\(ago)，你把我交给了下一位主人。这\(chineseCount(years))年，我被照顾得很好。"
                : "\(ago)，你在水边送我走。这\(chineseCount(years))年，我漂过很多地方，都很好。"
        }

        let memoryLine = MemoryResonance.echo(for: sender.memory, companionship: sender.companionship)?.letter
        let personal = memoryLine ?? (sender.isRelayed ? "新主人待我很好，你放心。" : familyLines(sender.family))

        return SeasonalLetter(
            id: id, occasion: occasion, messenger: messenger, term: term, spiritName: sender.name,
            arrival: arrival,
            paragraphs: [opening, personal, "一切都好，勿念。"],
            dateline: "\(ganzhiYear(on: date, calendar: calendar))年 · \(term.name)"
        )
    }

    /// 你今天 / 你在今年夏天 / 你在去年秋天 / 你在 2024 年秋天
    static func when(_ departed: Date, from date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(departed, inSameDayAs: date) { return "你今天" }
        let season = SolarTerm(date: departed).season.title + "天"
        let years = calendar.component(.year, from: date) - calendar.component(.year, from: departed)
        switch years {
        case ...0: return "你在今年\(season)"
        case 1: return "你在去年\(season)"
        default: return "你在 \(calendar.component(.year, from: departed)) 年\(season)"
        }
    }

    /// 送别满几年（只在周年当天和之后两天里返回）
    static func anniversaryYears(of departed: Date, on date: Date, calendar: Calendar = .current) -> Int? {
        let today = calendar.startOfDay(for: date)
        let parts = calendar.dateComponents([.year, .month, .day], from: departed)
        let thisYear = calendar.component(.year, from: date)
        for year in [thisYear, thisYear - 1] {
            guard let departedYear = parts.year, year > departedYear,
                  let anniversary = calendar.date(from: DateComponents(year: year, month: parts.month, day: parts.day)),
                  let days = calendar.dateComponents([.day], from: anniversary, to: today).day
            else { continue }
            if anniversaryWindow.contains(days) { return year - departedYear }
        }
        return nil
    }

    /// 冬至横跨元旦：一月里的冬至还算上一年那一次
    static func termYear(_ term: SolarTerm, on date: Date, calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: date)
        return term.index == 18 && calendar.component(.month, from: date) == 1 ? year - 1 : year
    }

    /// 干支纪年，以立春为界（立春前的一、二月还算上一年）
    static func ganzhiYear(on date: Date, calendar: Calendar = .current) -> String {
        var year = calendar.component(.year, from: date)
        let term = SolarTerm(date: date)
        if calendar.component(.month, from: date) <= 2, [18, 19, 20].contains(term.index) { year -= 1 }
        let stems = Array("甲乙丙丁戊己庚辛壬癸"), branches = Array("子丑寅卯辰巳午未申酉戌亥")
        let offset = year - 4
        return String(stems[((offset % 10) + 10) % 10]) + String(branches[((offset % 12) + 12) % 12])
    }

    static func chineseCount(_ n: Int) -> String {
        let digits = ["零", "一", "两", "三", "四", "五", "六", "七", "八", "九", "十"]
        return (0...10).contains(n) ? digits[n] : "\(n)"
    }

    // MARK: - 信里的话

    /// 每个节气一句，取自当季的物候。顺序与 SolarTerm.names 相同（春分起）。
    static let seasonalLines: [String] = [
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

    /// 记忆里没认出什么时，按物品类别问一句近况
    static func familyLines(_ family: ObjectFamily) -> String {
        switch family {
        case .footwear: "你现在穿哪双鞋走路？脚下还稳吗？"
        case .vessel: "你现在用哪只杯子喝水？记得趁热。"
        case .clothing: "天冷天热，都要穿得合身一点。"
        case .paper: "最近还看书吗？读到好句子，替我折个角。"
        case .electronic: "屏幕别看太久，抬头看看窗外。"
        case .toy: "晚上睡得好吗？我不在，你也要睡得安稳。"
        case .tool: "要搭把手的时候，别一个人扛着。"
        case .instrument: "最近还弹吗？弹错了也没关系，我从来没笑过。"
        case .accessory: "重要的日子，你会好好的，不用紧张。"
        case .bag: "别把心事都背着，偶尔放下来歇歇。"
        case .furniture: "回家的时候，在门口停一停，喘口气。"
        case .sport: "最近还动吗？慢一点也好，别受伤。"
        case .other: "不用总想着我，好好过你的日子。"
        }
    }
}

/// 竖排信笺的分列：每段从新的一列写起；标点不放在列首（放不下就挂在上一列末尾，和古籍排版一样）。
enum LetterLayout {
    static let hangingPunctuation: Set<Character> = ["，", "。", "、", "；", "：", "！", "？", "」", "』", "…"]

    static func columns(for paragraphs: [String], perColumn: Int) -> [[Character]] {
        var result: [[Character]] = []
        for paragraph in paragraphs {
            var column: [Character] = []
            for character in paragraph {
                if column.count >= perColumn {
                    if hangingPunctuation.contains(character) {
                        column.append(character)
                        continue
                    }
                    result.append(column)
                    column = []
                }
                column.append(character)
            }
            if !column.isEmpty { result.append(column) }
        }
        return result
    }
}
