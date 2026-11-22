import Foundation

/// 岁月留在物品身上的痕迹。由用户勾选，会写进生成提示词，让物灵更像原物。
/// 这几项只是"类型"，不涉及隐私，所以可以发给图像 API。
enum WearMark: String, CaseIterable, Codable, Identifiable, Sendable {
    case faded, chipped, scratched, cracked, stickers, mended, polished, stained

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faded: "褪色"
        case .chipped: "掉漆"
        case .scratched: "划痕"
        case .cracked: "裂纹"
        case .stickers: "贴满贴纸"
        case .mended: "缝补过"
        case .polished: "磨得发亮"
        case .stained: "旧污渍"
        }
    }

    var promptPhrase: String {
        switch self {
        case .faded: "faded, sun-bleached colors"
        case .chipped: "chipped paint at the edges"
        case .scratched: "fine scratches all over"
        case .cracked: "a small, carefully kept crack"
        case .stickers: "covered with little stickers"
        case .mended: "lovingly mended and patched"
        case .polished: "worn smooth and shiny from years of touch"
        case .stained: "a few old, faint stains"
        }
    }
}

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
    /// 用户勾选的岁月痕迹
    var wearMarks: [WearMark] = []
    /// 端侧大模型看到的外观描述（英文，不含照片本身）
    var appearance: String = ""
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

/// 不依赖任何模型的起名器。Foundation Models 不可用时使用（国行、旧机型）。
/// 送别语在两种情况下都由这里给出。
enum TemplateSpiritWriter {
    /// 名字结尾的字：亲昵、带一点古意
    private static let endings = ["君", "子", "生", "郎", "儿"]

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
        let echo = MemoryResonance.echo(for: seed.memory, companionship: seed.companionship)
        let objectLine = familyLine(seed.object.family.personalityLines, echo: echo, key: key)

        return SpiritProfile(
            name: seed.color.character + middle + ending,
            epithet: "\(seed.displayName)之灵",
            personality: objectLine + (echo?.line ?? companionshipLine(seed.companionship)),
            farewellSuggestion: echo?.farewell ?? defaultFarewell(seed.companionship)
        )
    }

    /// 物品自己的那句台词：记忆那句已经说过的画面（比如"下雨"）就换一句，免得说两遍；
    /// 记忆里还有别的画面（比如"清晨"）时，优先挑说到它的那句。
    private static func familyLine(_ lines: [String], echo: MemoryResonance.Echo?, key: String) -> String {
        let covered = echo?.covered ?? []
        let resonant = echo?.resonant ?? []
        let fresh = lines.filter { line in !covered.contains(where: line.contains) }
        let pool = fresh.isEmpty ? lines : fresh
        let matching = pool.filter { line in resonant.contains(where: line.contains) }
        return StableHash.pick(matching.isEmpty ? pool : matching, seed: key, salt: "line")
    }

    /// 送别输入框里的提示语。图鉴里给"同住"的物灵补办送别时也用它。
    static func farewellSuggestion(memory: String, companionship: Companionship) -> String {
        MemoryResonance.echo(for: memory, companionship: companionship)?.farewell ?? defaultFarewell(companionship)
    }

    private static func defaultFarewell(_ c: Companionship) -> String {
        "谢谢你，陪我\(c.phrase)。"
    }
}

/// 端侧的「记忆回应」：不联网、不用大模型，从用户写下的记忆里认出常见的生活意象，
/// 回一句贴合的性格描述和送别语。没认出来时，轻轻呼应记忆里的一个短语，不照抄整句。
///
/// 语气：安静、克制，不煽情、不说教。
enum MemoryResonance {
    struct Echo: Equatable {
        /// 接在物品台词后面的一句
        var line: String
        /// 送别输入框里的提示语
        var farewell: String
        /// 这句已经说到的画面，物品台词里出现这些词时换一句
        var covered: [String] = []
        /// 记忆里还有、但这句没说到的画面，物品台词说到它时优先用
        var resonant: [String] = []
        /// 节气来信里，物灵问候你的一句（第一人称）
        var letter: String? = nil
    }

    static func echo(for memory: String, companionship: Companionship) -> Echo? {
        let text = memory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMeaningful(text) else { return nil }

        let found = motifs.filter { $0.matches(text) }
        let imagery = { (motif: Motif) in motif.keywords.filter(text.contains) + motif.related }

        if var echo = personEcho(text, companionship: companionship) {
            echo.resonant = found.flatMap(imagery)
            return echo
        }
        if let motif = found.first {
            return Echo(line: StableHash.pick(motif.lines, seed: text, salt: "line"),
                        farewell: StableHash.pick(motif.farewells, seed: text, salt: "farewell"),
                        covered: imagery(motif),
                        resonant: found.dropFirst().flatMap(imagery),
                        letter: motif.letter)
        }

        // 没有认出的意象：轻轻呼应一个短语
        let farewell = "谢谢你，陪我\(companionship.phrase)，也替我记着那些事。"
        if let phrase = keyPhrase(in: text) {
            let lines = [
                "你写下的「\(phrase)」，它一直悄悄记着。",
                "说起「\(phrase)」，它好像比你记得还清楚。",
                "「\(phrase)」这一段，它替你好好收着。",
            ]
            return Echo(line: StableHash.pick(lines, seed: text, salt: "phrase"), farewell: farewell,
                        letter: "「\(phrase)」，我也还记得。")
        }
        return Echo(line: "你写给它的话，它都悄悄收着。", farewell: farewell)
    }

    /// "无""没有""不知道"这类话不算记忆
    private static func isMeaningful(_ text: String) -> Bool {
        let core = text.filter { !$0.isPunctuation && !$0.isWhitespace && !$0.isSymbol }
        let empty: Set<String> = ["无", "没有", "没", "暂无", "不知道", "忘了", "不记得", "略", "空", "none", "null", "na", "no"]
        return !core.isEmpty && !empty.contains(core.lowercased())
    }

    // MARK: - 意象

    private struct Motif {
        var keywords: [String]
        var lines: [String]
        var farewells: [String]
        /// 物品台词里描写同一画面的词（"熬过的那些夜"和"熬夜时的那杯咖啡"算一回事）
        var related: [String] = []
        /// 节气来信里问候的一句
        var letter: String

        func matches(_ text: String) -> Bool { keywords.contains(where: text.contains) }
    }

    /// 先认"那段日子"（考试、小时候、搬家……），再认画面（夜、清晨、雨……）。只用第一个认出的。
    private static let motifs: [Motif] = [
        Motif(keywords: ["高考", "中考", "考研", "考公", "考试", "考场", "期末", "备考", "复习", "刷题", "自习",
                         "答辩", "论文", "毕业", "高三", "初三", "黑客松", "比赛", "竞赛", "面试", "录取", "上岸", "冲刺"],
              lines: ["那段一心往前冲的日子，它都看在眼里。",
                      "它见过你最紧绷的时候，也见过你终于松一口气。",
                      "它不懂分数，只记得你一直没有放弃。"],
              farewells: ["谢谢你，陪我熬过那段最难的日子。",
                          "谢谢你，那些埋头赶路的日子，有你在。"],
              letter: "那段最难的日子过去了，你做得很好。"),
        Motif(keywords: ["生病", "住院", "医院", "手术", "难过", "低谷", "失恋", "分手", "伤心", "不开心", "崩溃", "哭"],
              lines: ["它见过你不太好的时候，什么也没说，只是一直在。",
                      "难熬的那些日子，它帮不上什么忙，就安安静静地陪着。"],
              farewells: ["谢谢你，在我不太好的时候一直都在。",
                          "谢谢你，陪我走过那段不太好的日子。"],
              letter: "再有不太好的时候，记得你不是一个人。"),
        Motif(keywords: ["粘好", "修好", "补好", "缝好", "修过", "补过", "粘过", "缝过", "坏过", "摔坏", "弄坏", "修修补补"],
              lines: ["它坏过，也被你修好过，所以格外知道自己被珍惜。",
                      "它身上那几处修补，记着你有多舍不得它。"],
              farewells: ["谢谢你，修修补补，还一直陪着我。"],
              letter: "我身上的修补都还在，一点也不难看。"),
        Motif(keywords: ["小时候", "童年", "小学", "幼儿园", "儿时", "年幼", "长大"],
              lines: ["它从你小时候就在，见过你还没长大的样子。",
                      "它身上有一点旧时光的味道，是你小时候的那种。"],
              farewells: ["谢谢你，替我收着小时候的那些日子。",
                          "谢谢你，陪我一点点长大。"],
              letter: "你长大了，我都知道。"),
        Motif(keywords: ["老家", "故乡", "家乡", "回家", "想家", "离家", "过年", "春节"],
              lines: ["它身上带着一点老家的气味，你走多远都认得。",
                      "它知道回家的路，也知道你有多想回去。"],
              farewells: ["谢谢你，让我走多远都记得回家的路。"],
              related: ["回家"],
              letter: "有空的话，回老家看看吧。"),
        Motif(keywords: ["宿舍", "寝室", "搬家", "租房", "出租屋", "新家", "住校", "室友", "上大学", "北漂", "沪漂"],
              lines: ["它跟你搬过几次家，每次都被你最先拆出来。",
                      "住过的地方换了又换，有它在，就有一点像家。"],
              farewells: ["谢谢你，陪我把好几个地方住成了家。",
                          "谢谢你，陪我在陌生的地方安顿下来。"],
              related: ["回家", "原地"],
              letter: "现在住的地方，住得惯吗？"),
        Motif(keywords: ["工作", "工资", "上班", "下班", "实习", "入职", "通勤", "地铁", "公司", "加班"],
              lines: ["它陪你早出晚归，见过你认真做事的样子。",
                      "它知道上班的路有多长，也见过你回家时松下来的样子。"],
              farewells: ["谢谢你，陪我走过那些早出晚归的日子。",
                          "谢谢你，陪我一点点站稳脚跟。"],
              related: ["回家"],
              letter: "工作别太拼，下班路上看看天。"),
        Motif(keywords: ["深夜", "熬夜", "凌晨", "半夜", "通宵", "失眠", "夜里", "晚上", "夜班", "睡不着", "每晚", "夜晚", "星星"],
              lines: ["很多个深夜它都醒着，安安静静地陪你等天亮。",
                      "它记得你熬过的那些夜，也记得窗外一点点变亮。"],
              farewells: ["谢谢你，陪我度过那么多个夜晚。",
                          "谢谢你，那些睡不着的夜里，有你在。"],
              related: ["深夜", "熬夜", "夜晚"],
              letter: "现在还熬夜吗？早点睡。"),
        Motif(keywords: ["清晨", "早晨", "早上", "晨跑", "日出", "天亮", "早起", "朝阳"],
              lines: ["它最熟悉天刚亮的样子，那是你们一起出门的时候。",
                      "它喜欢清晨，喜欢和你出门时那一点点凉。"],
              farewells: ["谢谢你，陪我迎过那么多个清晨。"],
              related: ["清晨", "出门"],
              letter: "清晨还出门吗？天凉，慢慢走。"),
        Motif(keywords: ["下雨", "雨天", "淋雨", "雨里", "雨中", "暴雨", "梅雨", "大雨", "小雨", "雨夜", "雨后", "躲雨", "避雨", "雨季"],
              lines: ["下雨的日子它记得最清楚：你没让它一个人淋着。",
                      "它听过很多场雨，最记得和你一起躲雨的那一回。"],
              farewells: ["谢谢你，陪我走过那些下雨的日子。"],
              related: ["下雨"],
              letter: "下雨记得带伞，别再淋着了。"),
        Motif(keywords: ["海边", "大海", "看海", "沙滩", "海风", "海浪", "海岛", "赶海"],
              lines: ["它还记得海风的味道，和你看海时安静的样子。"],
              farewells: ["谢谢你，陪我去看过海。"],
              letter: "什么时候再去看海，替我也看一眼。"),
        Motif(keywords: ["旅行", "旅游", "出差", "远行", "路上", "火车", "高铁", "飞机", "机场", "爬山", "登山", "徒步",
                         "露营", "远方", "出国", "自驾", "骑行"],
              lines: ["它跟你去过很远的地方，身上还留着那里的风。",
                      "它见过你在路上的样子，比在家时更轻快一点。"],
              farewells: ["谢谢你，陪我走了那么远的路。"],
              related: ["每一条路", "出门", "风"],
              letter: "走远路的时候，记得报个平安。"),
        Motif(keywords: ["跑步", "马拉松", "半马", "全马", "夜跑", "球场", "训练", "健身", "打球", "篮球", "足球", "羽毛球", "游泳"],
              lines: ["它见过你咬着牙坚持的样子，一次也没笑话过你。"],
              farewells: ["谢谢你，陪我一次次坚持下来。"],
              letter: "还在坚持吗？慢一点也没关系。"),
        Motif(keywords: ["夏天", "暑假", "盛夏", "蝉", "西瓜", "夏夜"],
              lines: ["它还记得那个夏天：蝉声很长，日子也很长。"],
              farewells: ["谢谢你，陪我过了那个夏天。"],
              letter: "那个夏天，我还常常想起。"),
        Motif(keywords: ["冬天", "下雪", "雪天", "寒假", "大雪", "寒冬", "雪地"],
              lines: ["它见过你呵着手的冬天，也陪你等过春天。"],
              farewells: ["谢谢你，陪我过了那么多个冬天。"],
              letter: "那些冬天，谢谢你一直把我带在身边。"),
        Motif(keywords: ["第一次", "第一个", "第一双", "第一台", "第一把", "第一份", "第一件", "第一部", "第一辆", "第一本"],
              lines: ["它是你的「第一」，见过你还有点笨拙的样子。"],
              farewells: ["谢谢你，陪我开了个好头。"],
              letter: "后来，你又有了好多个「第一次」吧。"),
    ]

    // MARK: - 人与心意

    /// 从记忆里认出的人，按写法换成称呼
    private static let people: [(word: String, call: String)] = [
        ("外婆", "外婆"), ("外公", "外公"), ("奶奶", "奶奶"), ("爷爷", "爷爷"), ("姥姥", "姥姥"), ("姥爷", "姥爷"),
        ("妈妈", "妈妈"), ("爸爸", "爸爸"), ("母亲", "母亲"), ("父亲", "父亲"), ("老妈", "妈妈"), ("老爸", "爸爸"),
        ("我妈", "妈妈"), ("我爸", "爸爸"), ("姐姐", "姐姐"), ("哥哥", "哥哥"), ("妹妹", "妹妹"), ("弟弟", "弟弟"),
        ("女儿", "女儿"), ("儿子", "儿子"), ("老婆", "爱人"), ("老公", "爱人"), ("爱人", "爱人"), ("女朋友", "她"),
        ("男朋友", "他"), ("恋人", "那个人"), ("闺蜜", "闺蜜"), ("好友", "好友"), ("朋友", "朋友"), ("同桌", "同桌"),
        ("同学", "同学"), ("室友", "室友"), ("老师", "老师"), ("师父", "师父"), ("家人", "家人"),
    ]

    private static let giftWords = ["送我", "送给", "送的", "相送", "赠", "礼物", "给我", "买给", "留给", "织的", "做的", "缝的", "传给", "生日", "纪念"]

    private static func personEcho(_ text: String, companionship: Companionship) -> Echo? {
        let isGift = giftWords.contains(where: text.contains)
        let person = firstPerson(in: text)

        if let person {
            let longTime = companionship != .days && companionship != .months
            if isGift {
                return Echo(line: StableHash.pick(["它身上还留着\(person)的心意，被你一直好好收着。",
                                                   "它是\(person)给你的，所以格外懂得被人惦记的滋味。"],
                                                  seed: text, salt: "person"),
                            farewell: longTime ? "谢谢你，替\(person)陪了我\(companionship.phrase)。" : "谢谢你，让我一直记得\(person)的心意。",
                            letter: "\(person)的那份心意，我一直带着。")
            }
            return Echo(line: StableHash.pick(["它总让你想起\(person)，想起被人惦记着的感觉。",
                                               "一看见它，你就会想起\(person)，这件事它一直知道。"],
                                              seed: text, salt: "person"),
                        farewell: "谢谢你，让我常常想起\(person)。",
                        letter: "想起\(person)的时候，也顺便想想我。")
        }
        if isGift {
            return Echo(line: StableHash.pick(["它是一份心意，你一直好好收着。",
                                               "它带着别人的一份心意来到你身边，就再没离开。"],
                                              seed: text, salt: "gift"),
                        farewell: "谢谢你，把那份心意一直留在我身边。",
                        letter: "那份心意，我一直带着。")
        }
        return nil
    }

    /// 最先出现的那个人；同一位置取最长的写法（"女朋友"优先于"朋友"）。"小朋友"不算。
    private static func firstPerson(in text: String) -> String? {
        var best: (offset: Int, length: Int, call: String)?
        for entry in people {
            var searchStart = text.startIndex
            while let range = text.range(of: entry.word, range: searchStart..<text.endIndex) {
                searchStart = range.upperBound
                if entry.word == "朋友", range.lowerBound > text.startIndex, text[text.index(before: range.lowerBound)] == "小" {
                    continue
                }
                let offset = text.distance(from: text.startIndex, to: range.lowerBound)
                let length = entry.word.count
                if best == nil || offset < best!.offset || (offset == best!.offset && length > best!.length) {
                    best = (offset, length, entry.call)
                }
                break
            }
        }
        return best?.call
    }

    // MARK: - 没认出意象时：挑一个短语

    /// 例如"大一那年在图书馆捡到它" → 大一那年；"和它一起看了好多场电影" → 一起看了好多场电影
    static func keyPhrase(in text: String) -> String? {
        let separators = Set("，,。．.！!？?；;：:、…\n\r\t 　~～—-（）()「」『』“”\"'《》【】[]")
        let clauses = text.split(whereSeparator: { separators.contains($0) })
            .map { tidy(String($0)) }
            .filter { $0.count >= 2 }
        guard !clauses.isEmpty else { return nil }

        // 1. 带"那年、那天……"的时间短语，最能唤起回忆
        let anchors = ["那年", "那天", "那次", "那晚", "那段日子", "那段时间", "那个夏天", "那个冬天", "那个春天", "那个秋天"]
        for clause in clauses {
            for anchor in anchors {
                guard let range = clause.range(of: anchor) else { continue }
                let before = clause[clause.startIndex..<range.lowerBound].suffix(4)
                let phrase = String(before) + anchor
                if phrase.count >= 3 { return phrase }
            }
        }

        // 2. 否则取最像"画面"的一小句：带"一起、每天、每次"的优先，长度适中
        let warmWords = ["一起", "每天", "每次", "总是", "一直", "陪"]
        // 太短的（"很重要""舍不得"）只是感受，不是画面，交给通用的那句
        let candidates = clauses.filter { (4...12).contains($0.count) }
        let scored = candidates.enumerated().max { a, b in
            score(a.element, warmWords) - a.offset < score(b.element, warmWords) - b.offset
        }
        return scored?.element
    }

    private static func score(_ clause: String, _ warmWords: [String]) -> Int {
        var value = 0
        if warmWords.contains(where: clause.contains) { value += 4 }
        value -= abs(clause.count - 7) / 2
        return value
    }

    /// 去掉句首的"我、它、其实、后来……"和句尾的语气词
    private static func tidy(_ clause: String) -> String {
        var s = clause.trimmingCharacters(in: .whitespaces)
        let leading = ["和它", "跟它", "把它", "用它", "带着它", "我们", "咱们", "其实", "当时", "后来", "然后", "因为", "所以", "但是", "可是", "不过", "而且", "就是", "我", "它", "就", "还"]
        var changed = true
        while changed {
            changed = false
            for word in leading where s.hasPrefix(word) && s.count > word.count + 1 {
                s.removeFirst(word.count)
                changed = true
            }
        }
        let trailing: Set<Character> = ["了", "的", "啊", "呀", "呢", "吧", "哦", "嘛", "啦", "哈"]
        while let last = s.last, trailing.contains(last), s.count > 2 {
            s.removeLast()
        }
        return s
    }
}
