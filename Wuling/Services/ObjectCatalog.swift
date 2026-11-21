import Foundation

/// 物品大类：决定物灵名字里的"字"以及性格的基调。
enum ObjectFamily: String, Codable, CaseIterable, Sendable {
    case footwear, vessel, clothing, paper, electronic, toy, tool, instrument, accessory, bag, furniture, sport, other

    /// 物灵名字中间的那个字，例如 履 → 青履丸
    var nameCharacters: [String] {
        switch self {
        case .footwear: ["履", "屐"]
        case .vessel: ["盏", "瓯"]
        case .clothing: ["衣", "裳"]
        case .paper: ["卷", "笺"]
        case .electronic: ["芯", "机"]
        case .toy: ["偶", "宝"]
        case .tool: ["匠", "具"]
        case .instrument: ["弦", "音"]
        case .accessory: ["佩", "环"]
        case .bag: ["囊", "袋"]
        case .furniture: ["几", "榻"]
        case .sport: ["跃", "驰"]
        case .other: ["灵", "物"]
        }
    }

    /// 和这一类物品有关的一句性格描述
    var personalityLines: [String] {
        switch self {
        case .footwear: ["它记得你走过的每一条路，尤其是下雨的那几天。", "它最怀念和你一起赶路的清晨。"]
        case .vessel: ["它装过你的清晨，也装过你熬夜时的那杯咖啡。", "它最喜欢被你双手捧着的时候。"]
        case .clothing: ["它记得你的体温，和穿着它的那些日子。", "它替你挡过风，也陪你出过很多次门。"]
        case .paper: ["你翻过的每一页，它都悄悄记在了心里。", "它的折角，是你停下来想事情的地方。"]
        case .electronic: ["它替你保管过无数个瞬间，屏幕亮起时，总是你。", "它听过你最多的消息提示音，也见过你最晚的深夜。"]
        case .toy: ["它听过你所有的秘密，从来没有说出去。", "它陪你睡过很多个夜晚，比谁都懂你的梦。"]
        case .tool: ["它不爱说话，只在你需要的时候出现。", "它手上的磨痕，都是替你干活留下的。"]
        case .instrument: ["它还记得你第一次弹错的那个音。", "它把你的心情，一个音一个音地唱了出来。"]
        case .accessory: ["它一直贴着你，见过你紧张时的手心。", "它小小的，却陪你出席过好多重要的时刻。"]
        case .bag: ["它替你背过很多东西，包括那些说不出口的心事。", "它的口袋里，还藏着你忘掉的小纸条。"]
        case .furniture: ["它稳稳地待在原地，等你每一次回家。", "它见过你最放松、最不设防的样子。"]
        case .sport: ["它陪你流过很多汗，也陪你赢过、输过。", "它最喜欢你奔跑时的样子。"]
        case .other: ["它一直在你身边，只是你从没听见它说话。", "它不起眼，却是你生活里很重要的一部分。"]
        }
    }
}

/// 识别出的物品：中文名、英文名（给图像模型用）、大类。
struct ObjectKind: Hashable, Codable, Sendable {
    var chinese: String
    var english: String
    var family: ObjectFamily

    static let unknown = ObjectKind(chinese: "旧物", english: "cherished everyday object", family: .other)
}

/// ImageNet 标签（MobileNetV2 的输出）→ 中文物品名。
/// 只收录了日常生活中常见、会让人"舍不得扔"的物品。
enum ObjectCatalog {
    /// key：ImageNet 标签中逗号分隔的任意一个同义词（小写）
    private static let table: [String: ObjectKind] = {
        let entries: [(String, String, String, ObjectFamily)] = [
            // 鞋
            ("running shoe", "跑鞋", "running shoe", .footwear),
            ("sandal", "凉鞋", "sandal", .footwear),
            ("loafer", "便鞋", "loafer shoe", .footwear),
            ("cowboy boot", "靴子", "leather boot", .footwear),
            ("clog", "木屐", "wooden clog", .footwear),
            ("sock", "袜子", "sock", .footwear),
            // 器皿
            ("coffee mug", "马克杯", "coffee mug", .vessel),
            ("cup", "杯子", "cup", .vessel),
            ("water bottle", "水杯", "water bottle", .vessel),
            ("beer glass", "玻璃杯", "drinking glass", .vessel),
            ("teapot", "茶壶", "teapot", .vessel),
            ("coffeepot", "咖啡壶", "coffee pot", .vessel),
            ("espresso maker", "摩卡壶", "espresso maker", .vessel),
            ("water jug", "水壶", "water jug", .vessel),
            ("vase", "花瓶", "vase", .vessel),
            ("pot", "花盆", "flower pot", .vessel),
            ("mixing bowl", "碗", "bowl", .vessel),
            ("soup bowl", "汤碗", "soup bowl", .vessel),
            ("plate", "盘子", "plate", .vessel),
            ("wine bottle", "酒瓶", "wine bottle", .vessel),
            ("pop bottle", "汽水瓶", "soda bottle", .vessel),
            ("pill bottle", "小药瓶", "small bottle", .vessel),
            ("perfume", "香水瓶", "perfume bottle", .vessel),
            ("lotion", "乳液瓶", "lotion bottle", .vessel),
            ("frying pan", "平底锅", "frying pan", .vessel),
            ("wok", "炒锅", "wok", .vessel),
            ("piggy bank", "存钱罐", "piggy bank", .vessel),
            // 衣物
            ("jersey", "T 恤", "t-shirt", .clothing),
            ("sweatshirt", "卫衣", "sweatshirt", .clothing),
            ("cardigan", "开衫", "cardigan", .clothing),
            ("jean", "牛仔裤", "denim jeans", .clothing),
            ("miniskirt", "裙子", "skirt", .clothing),
            ("suit", "西装", "suit jacket", .clothing),
            ("kimono", "和服", "kimono", .clothing),
            ("trench coat", "风衣", "trench coat", .clothing),
            ("fur coat", "大衣", "winter coat", .clothing),
            ("abaya", "长袍", "long robe", .clothing),
            ("academic gown", "学士服", "graduation gown", .clothing),
            ("apron", "围裙", "apron", .clothing),
            ("pajama", "睡衣", "pajamas", .clothing),
            ("mitten", "手套", "mitten", .clothing),
            ("stole", "围巾", "scarf", .clothing),
            ("bath towel", "浴巾", "towel", .clothing),
            ("quilt", "被子", "quilt", .clothing),
            ("pillow", "枕头", "pillow", .clothing),
            ("sleeping bag", "睡袋", "sleeping bag", .clothing),
            // 帽子与配饰
            ("cowboy hat", "帽子", "hat", .accessory),
            ("sombrero", "草帽", "straw hat", .accessory),
            ("mortarboard", "学士帽", "graduation cap", .accessory),
            ("bow tie", "领结", "bow tie", .accessory),
            ("windsor tie", "领带", "necktie", .accessory),
            ("sunglasses", "墨镜", "sunglasses", .accessory),
            ("sunglass", "眼镜", "glasses", .accessory),
            ("digital watch", "手表", "wristwatch", .accessory),
            ("necklace", "项链", "necklace", .accessory),
            ("hair slide", "发夹", "hair clip", .accessory),
            ("lipstick", "口红", "lipstick", .accessory),
            ("umbrella", "雨伞", "umbrella", .accessory),
            ("mask", "面具", "mask", .accessory),
            ("wig", "假发", "wig", .accessory),
            ("crash helmet", "头盔", "helmet", .accessory),
            ("lighter", "打火机", "lighter", .accessory),
            ("thimble", "顶针", "thimble", .accessory),
            // 包
            ("backpack", "背包", "backpack", .bag),
            ("purse", "手提包", "handbag", .bag),
            ("wallet", "钱包", "wallet", .bag),
            ("mailbag", "邮差包", "messenger bag", .bag),
            ("plastic bag", "购物袋", "shopping bag", .bag),
            ("pencil box", "笔袋", "pencil case", .bag),
            // 纸与文具
            ("book jacket", "书", "book", .paper),
            ("comic book", "漫画书", "comic book", .paper),
            ("binder", "文件夹", "ring binder", .paper),
            ("envelope", "信封", "envelope", .paper),
            ("menu", "旧菜单", "paper menu", .paper),
            ("crossword puzzle", "旧报纸", "newspaper", .paper),
            ("jigsaw puzzle", "拼图", "jigsaw puzzle", .paper),
            ("fountain pen", "钢笔", "fountain pen", .tool),
            ("ballpoint", "圆珠笔", "ballpoint pen", .tool),
            ("rubber eraser", "橡皮", "eraser", .tool),
            ("pencil sharpener", "卷笔刀", "pencil sharpener", .tool),
            ("rule", "尺子", "ruler", .tool),
            // 电子产品
            ("cellular telephone", "手机", "old mobile phone", .electronic),
            ("ipod", "音乐播放器", "portable music player", .electronic),
            ("laptop", "笔记本电脑", "laptop computer", .electronic),
            ("notebook", "笔记本电脑", "laptop computer", .electronic),
            ("hand-held computer", "平板电脑", "tablet computer", .electronic),
            ("computer keyboard", "键盘", "computer keyboard", .electronic),
            ("mouse", "鼠标", "computer mouse", .electronic),
            ("monitor", "显示器", "computer monitor", .electronic),
            ("television", "电视机", "television", .electronic),
            ("remote control", "遥控器", "remote control", .electronic),
            ("joystick", "游戏手柄", "game controller", .electronic),
            ("polaroid camera", "拍立得", "instant camera", .electronic),
            ("reflex camera", "相机", "film camera", .electronic),
            ("radio", "收音机", "radio", .electronic),
            ("cassette player", "随身听", "cassette player", .electronic),
            ("cd player", "CD 机", "cd player", .electronic),
            ("loudspeaker", "音箱", "speaker", .electronic),
            ("modem", "路由器", "wifi router", .electronic),
            ("electric fan", "电风扇", "electric fan", .electronic),
            ("hand blower", "吹风机", "hair dryer", .electronic),
            ("iron", "熨斗", "clothes iron", .electronic),
            ("toaster", "烤面包机", "toaster", .electronic),
            ("microwave", "微波炉", "microwave oven", .electronic),
            ("table lamp", "台灯", "desk lamp", .electronic),
            ("lampshade", "灯罩", "lamp", .electronic),
            ("analog clock", "钟", "clock", .electronic),
            ("wall clock", "挂钟", "wall clock", .electronic),
            ("stopwatch", "秒表", "stopwatch", .electronic),
            ("sewing machine", "缝纫机", "sewing machine", .tool),
            // 乐器
            ("acoustic guitar", "吉他", "acoustic guitar", .instrument),
            ("electric guitar", "电吉他", "electric guitar", .instrument),
            ("violin", "小提琴", "violin", .instrument),
            ("grand piano", "钢琴", "piano", .instrument),
            ("upright", "钢琴", "upright piano", .instrument),
            ("harmonica", "口琴", "harmonica", .instrument),
            ("drum", "鼓", "drum", .instrument),
            ("flute", "笛子", "flute", .instrument),
            // 玩具
            ("teddy", "玩偶熊", "teddy bear", .toy),
            ("balloon", "气球", "balloon", .toy),
            ("pinwheel", "风车", "pinwheel", .toy),
            ("hourglass", "沙漏", "hourglass", .toy),
            ("candle", "蜡烛", "candle", .toy),
            // 工具
            ("hammer", "锤子", "hammer", .tool),
            ("screwdriver", "螺丝刀", "screwdriver", .tool),
            ("spatula", "锅铲", "spatula", .tool),
            ("wooden spoon", "木勺", "wooden spoon", .tool),
            ("ladle", "汤勺", "ladle", .tool),
            ("broom", "扫帚", "broom", .tool),
            ("letter opener", "裁纸刀", "letter opener", .tool),
            ("padlock", "锁", "padlock", .tool),
            // 家具
            ("rocking chair", "摇椅", "rocking chair", .furniture),
            ("folding chair", "椅子", "chair", .furniture),
            ("desk", "书桌", "desk", .furniture),
            ("studio couch", "沙发", "sofa", .furniture),
            ("cradle", "摇篮", "cradle", .furniture),
            // 运动
            ("soccer ball", "足球", "soccer ball", .sport),
            ("basketball", "篮球", "basketball", .sport),
            ("tennis ball", "网球", "tennis ball", .sport),
            ("volleyball", "排球", "volleyball", .sport),
            ("baseball", "棒球", "baseball", .sport),
            ("racket", "球拍", "racket", .sport),
            ("ping-pong ball", "乒乓球", "ping pong ball", .sport),
            ("mountain bike", "自行车", "bicycle", .sport),
            ("tricycle", "三轮车", "tricycle", .sport),
            ("dumbbell", "哑铃", "dumbbell", .sport),
            // ImageNet 里没有、但日常最常见的物品。
            // key 尽量写成 Vision 内置分类器可能给出的标签；以 "~" 开头的只用于中文反查。
            ("headphones", "耳机", "headphones", .electronic),
            ("earphones", "耳机", "earphones", .electronic),
            ("~earbuds", "无线耳机", "wireless earbuds in a charging case", .electronic),
            ("thermos", "保温杯", "insulated thermos bottle", .vessel),
            ("~power bank", "充电宝", "portable power bank", .electronic),
            ("~charger", "充电器", "phone charger", .electronic),
            ("key", "钥匙", "old key", .tool),
            ("keys", "钥匙", "bunch of keys", .tool),
            ("~keychain", "钥匙扣", "keychain charm", .accessory),
            ("figurine", "手办", "small collectible figurine", .toy),
            ("~blind box", "盲盒", "small blind box toy figure", .toy),
            ("stuffed animal", "毛绒玩具", "stuffed animal plush", .toy),
            ("plush", "毛绒玩具", "plush toy", .toy),
            ("~doll", "娃娃", "doll", .toy),
            ("bracelet", "手链", "bracelet", .accessory),
            ("ring", "戒指", "ring", .accessory),
            ("~hair tie", "发圈", "hair tie", .accessory),
            ("~tote bag", "帆布包", "canvas tote bag", .bag),
            ("~school bag", "书包", "school bag", .bag),
            ("sneaker", "球鞋", "sneaker", .footwear),
            ("~slippers", "拖鞋", "slippers", .footwear),
            ("~paper notebook", "笔记本", "paper notebook", .paper),
            ("~journal", "手账", "journal notebook", .paper),
            ("~postcard", "明信片", "postcard", .paper),
            ("~photo", "照片", "old photograph", .paper),
            ("picture frame", "相框", "picture frame", .furniture),
            ("~calendar", "台历", "desk calendar", .paper),
            ("~cushion", "靠垫", "cushion", .furniture),
            ("~blanket", "毯子", "blanket", .clothing),
            ("~hoodie", "卫衣", "hoodie", .clothing),
            ("~jacket", "外套", "jacket", .clothing),
            ("~ukulele", "尤克里里", "ukulele", .instrument),
            ("~skateboard", "滑板", "skateboard", .sport),
            ("~badminton racket", "羽毛球拍", "badminton racket", .sport),
            ("~game console", "游戏机", "handheld game console", .electronic),
            ("~tablet", "平板电脑", "tablet computer", .electronic),
            ("~smartwatch", "智能手表", "smartwatch", .electronic),
            ("~glasses", "眼镜", "eyeglasses", .accessory),
            ("~alarm clock", "闹钟", "alarm clock", .electronic),
            // Vision 内置分类器常见的日常标签（下划线已替换为空格）
            ("notebook computer", "笔记本电脑", "laptop computer", .electronic),
            ("mug", "马克杯", "coffee mug", .vessel),
            ("bottle", "瓶子", "bottle", .vessel),
            ("bowl", "碗", "bowl", .vessel),
            ("shoes", "鞋", "shoe", .footwear),
            ("boot", "靴子", "boot", .footwear),
            ("boots", "靴子", "boots", .footwear),
            ("high heels", "高跟鞋", "high heel shoe", .footwear),
            ("guitar", "吉他", "acoustic guitar", .instrument),
            ("piano", "钢琴", "piano", .instrument),
            ("camera", "相机", "camera", .electronic),
            ("cellphone", "手机", "mobile phone", .electronic),
            ("smartphone", "手机", "smartphone", .electronic),
            ("computer", "电脑", "computer", .electronic),
            ("keyboard", "键盘", "keyboard", .electronic),
            ("headset", "耳机", "headset", .electronic),
            ("speaker", "音箱", "speaker", .electronic),
            ("game controller", "游戏手柄", "game controller", .electronic),
            ("clock", "钟", "clock", .electronic),
            ("watch", "手表", "wristwatch", .accessory),
            ("wristwatch", "手表", "wristwatch", .accessory),
            ("lamp", "台灯", "lamp", .electronic),
            ("teddy bear", "玩偶熊", "teddy bear", .toy),
            ("toy", "玩具", "toy", .toy),
            ("stuffed toy", "毛绒玩具", "stuffed toy", .toy),
            ("ball", "球", "ball", .sport),
            ("book", "书", "book", .paper),
            ("notebook", "笔记本", "paper notebook", .paper),
            ("pen", "笔", "pen", .tool),
            ("pencil", "铅笔", "pencil", .tool),
            ("scissors", "剪刀", "scissors", .tool),
            ("hat", "帽子", "hat", .accessory),
            ("cap", "棒球帽", "baseball cap", .accessory),
            ("eyeglasses", "眼镜", "eyeglasses", .accessory),
            ("handbag", "手提包", "handbag", .bag),
            ("bag", "包", "bag", .bag),
            ("jewelry", "首饰", "jewelry", .accessory),
            ("earrings", "耳环", "earrings", .accessory),
            ("scarf", "围巾", "scarf", .clothing),
            ("glove", "手套", "glove", .clothing),
            ("shirt", "衬衫", "shirt", .clothing),
            ("tshirt", "T 恤", "t-shirt", .clothing),
            ("jacket", "外套", "jacket", .clothing),
            ("coat", "大衣", "coat", .clothing),
            ("dress", "裙子", "dress", .clothing),
            ("jeans", "牛仔裤", "denim jeans", .clothing),
            ("sweater", "毛衣", "sweater", .clothing),
            ("hoodie", "卫衣", "hoodie", .clothing),
            ("blanket", "毯子", "blanket", .clothing),
            ("towel", "毛巾", "towel", .clothing),
            ("chair", "椅子", "chair", .furniture),
            ("sofa", "沙发", "sofa", .furniture),
            ("couch", "沙发", "sofa", .furniture),
            ("table", "桌子", "table", .furniture),
            ("bicycle", "自行车", "bicycle", .sport),
            ("skateboard", "滑板", "skateboard", .sport),
            ("frame", "相框", "picture frame", .furniture),
            ("mirror", "镜子", "hand mirror", .accessory),
            ("toothbrush", "牙刷", "toothbrush", .tool),
            ("comb", "梳子", "comb", .tool),
            ("cosmetics", "化妆品", "cosmetics", .accessory),
            ("spoon", "勺子", "spoon", .tool),
            ("chopsticks", "筷子", "chopsticks", .tool),
            ("wine bottle", "酒瓶", "wine bottle", .vessel),
        ]
        var map: [String: ObjectKind] = [:]
        for (key, chinese, english, family) in entries {
            map[key] = ObjectKind(chinese: chinese, english: english, family: family)
        }
        return map
    }()

    /// 所有物品（去重），用于中文反查
    private static let allKinds: [ObjectKind] = {
        var seen = Set<String>()
        return table.values
            .filter { seen.insert($0.chinese + "|" + $0.english).inserted }
            .sorted { $0.chinese.count > $1.chinese.count }
    }()

    /// 用户手动输入的名字里包含哪个物品？取最长的匹配。
    /// 例如"外婆的闹钟" → 闹钟；"第一双跑鞋" → 跑鞋；"旧吉他" → 吉他
    static func kind(matchingChinese text: String) -> ObjectKind? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return allKinds.first { trimmed.contains($0.chinese) }
    }

    /// 给用户选的候选（最多 `limit` 个，中文名不重复）
    static func rankedKinds(from labels: [(identifier: String, confidence: Float)], limit: Int = 3) -> [ObjectKind] {
        var result: [ObjectKind] = []
        for candidate in labels where candidate.confidence >= 0.02 {
            guard let kind = kind(forLabel: candidate.identifier),
                  !result.contains(where: { $0.chinese == kind.chinese }) else { continue }
            result.append(kind)
            if result.count == limit { break }
        }
        return result
    }

    /// 用一个标签查找物品。ImageNet 标签形如 "notebook, notebook computer"。
    /// 多个同义词都能匹配时取最长（最具体）的那个，避免 "notebook" 把笔记本电脑认成纸质笔记本。
    static func kind(forLabel label: String) -> ObjectKind? {
        let synonyms = label
            .lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return synonyms
            .filter { table[$0] != nil }
            .max { $0.count < $1.count }
            .flatMap { table[$0] }
    }

    /// 一组识别结果（来自某个模型、某张图），以及它的可信权重
    struct LabelSource {
        var labels: [(identifier: String, confidence: Float)]
        var weight: Double
    }

    /// 合并多个模型、多张图的识别结果：同一物品的加权置信度相加，几个来源都认同的物品排在前面。
    static func scoredKinds(from sources: [LabelSource], minConfidence: Float = 0.02) -> [(kind: ObjectKind, score: Double)] {
        var scores: [String: (kind: ObjectKind, score: Double)] = [:]
        for source in sources {
            var counted = Set<String>()
            for label in source.labels where label.confidence >= minConfidence {
                guard let kind = kind(forLabel: label.identifier), counted.insert(kind.chinese).inserted else { continue }
                let previous = scores[kind.chinese]?.score ?? 0
                scores[kind.chinese] = (kind, previous + Double(label.confidence) * source.weight)
            }
        }
        return scores.values.sorted { $0.score > $1.score }
    }

    /// 从按置信度排好序的候选标签里，挑出第一个能识别的物品。
    /// 都不认识时，保留模型给出的英文名，中文名用"旧物"，让用户自己改。
    static func bestMatch(from labels: [(identifier: String, confidence: Float)]) -> ObjectKind {
        for candidate in labels where candidate.confidence >= 0.03 {
            if let kind = kind(forLabel: candidate.identifier) { return kind }
        }
        if let top = labels.first, top.confidence >= 0.15,
           let name = top.identifier.split(separator: ",").first {
            return ObjectKind(chinese: ObjectKind.unknown.chinese,
                              english: name.trimmingCharacters(in: .whitespaces),
                              family: .other)
        }
        return .unknown
    }
}
