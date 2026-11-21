import Foundation

/// 「传灵」：物品换了主人，物灵和它的故事也跟着走。
///
/// 每一位主人是一"章"。就像古画上的鉴藏印，每经过一位主人，物灵卡片上就多一枚他的名章。

/// 一位主人与这件物品的一段日子
struct RelayChapter: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    /// 名章上的字，例如"小林"（长度不限）
    var ownerSeal: String
    var receivedAt: Date
    var passedAt: Date?
    var companionshipRaw: String?
    /// 这位主人愿意一起传下去的记忆
    var memory: String = ""
    /// 写给下一位主人的话，例如"它怕潮，下雨天别带它出门"
    var noteToNext: String = ""

    var companionship: Companionship? {
        companionshipRaw.flatMap(Companionship.init(rawValue:))
    }
}

/// 隔空投送时传出去的"物灵胶囊"：一个 `.wuling` 文件。
/// 不需要服务器，两部手机之间直接传。
struct SpiritCapsule: Codable, Sendable {
    static let fileExtension = "wuling"
    static let typeIdentifier = "com.hackson2026.wuling.spirit"
    static let currentVersion = 1

    var version: Int = SpiritCapsule.currentVersion
    /// 物灵的"血脉"编号：不管传到谁手里都不变，传回来时能认出它
    var lineageID: UUID
    var name: String
    var epithet: String
    var personality: String
    var objectName: String
    var objectEnglish: String
    var familyRaw: String
    var colorName: String
    var paletteHex: [String]
    var isPlaceholderArt: Bool
    /// 物灵第一次被唤醒的日子
    var awakenedAt: Date
    var chapters: [RelayChapter]
    var spiritImage: Data?
    var stickerImage: Data?

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SpiritCapsule {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let capsule = try decoder.decode(SpiritCapsule.self, from: data)
        guard capsule.version <= currentVersion else { throw RelayError.newerVersion }
        return capsule
    }

    /// 文件名，例如 "青履丸.wuling"
    var suggestedFileName: String {
        let safe = name.replacingOccurrences(of: "/", with: "")
        return (safe.isEmpty ? "物灵" : safe) + "." + Self.fileExtension
    }
}

enum RelayError: LocalizedError {
    case newerVersion
    case unreadable

    var errorDescription: String? {
        switch self {
        case .newerVersion: "这个物灵来自更新版本的物灵 App，请先更新。"
        case .unreadable: "无法读取这个物灵。"
        }
    }
}

/// 传灵的纯逻辑：整理章节、生成传出的胶囊、接收时加上新主人的一章。
enum RelayLogic {
    /// 名章文字：去掉首尾空白，长度不限
    static func normalizedSeal(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 传出：补全"我"这一章（离开的日期、写给下一位的话、愿意分享的记忆）
    static func chaptersForSending(
        existing: [RelayChapter],
        mySeal: String,
        myStart: Date,
        companionship: Companionship?,
        memory: String,
        noteToNext: String,
        now: Date = .now
    ) -> [RelayChapter] {
        var chapters = existing
        let mine = RelayChapter(
            ownerSeal: normalizedSeal(mySeal),
            receivedAt: myStart,
            passedAt: now,
            companionshipRaw: companionship?.rawValue,
            memory: memory.trimmingCharacters(in: .whitespacesAndNewlines),
            noteToNext: noteToNext.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let last = chapters.last, last.passedAt == nil {
            // 我是从别人那里接过来的：最后一章就是我的，补全它
            var updated = mine
            updated.id = last.id
            updated.receivedAt = last.receivedAt
            chapters[chapters.count - 1] = updated
        } else {
            // 我是第一位主人
            chapters.append(mine)
        }
        return chapters
    }

    /// 接收：在胶囊的章节后面，加上新主人（我）的一章
    static func chaptersForReceiving(_ capsule: SpiritCapsule, mySeal: String, now: Date = .now) -> [RelayChapter] {
        var chapters = capsule.chapters
        // 如果最后一章还没写离开日期（比如对方没走正常流程），帮它补上
        if var last = chapters.last, last.passedAt == nil {
            last.passedAt = now
            chapters[chapters.count - 1] = last
        }
        chapters.append(RelayChapter(ownerSeal: normalizedSeal(mySeal), receivedAt: now))
        return chapters
    }

    /// 这是第几代主人（从 1 开始）
    static func generation(of chapters: [RelayChapter]) -> Int {
        max(1, chapters.count)
    }

    /// 上一位主人写给我的话
    static func latestNote(in chapters: [RelayChapter]) -> RelayChapter? {
        chapters.last(where: { $0.passedAt != nil && !$0.noteToNext.isEmpty })
    }
}
