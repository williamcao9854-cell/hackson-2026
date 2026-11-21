import Foundation
import SwiftData

/// 一个物灵。
///
/// 三种状态：
/// - 同住：物品还留在身边（`releasedAt == nil`）
/// - 已送别：物品已经放手，物灵与记忆留在图鉴里
/// - 已传出：物品送给了下一位主人，物灵和故事也一起传了过去（「传灵」）
@Model
final class Spirit {
    var id: UUID = UUID()
    /// 图鉴编号，从 1 开始
    var serial: Int = 0

    var name: String = ""
    var epithet: String = ""
    var personality: String = ""

    /// 物品名（用户可能改过），例如"第一双跑鞋"
    var objectName: String = ""
    var objectEnglish: String = ""
    var familyRaw: String = ObjectFamily.other.rawValue
    var companionshipRaw: String = Companionship.years.rawValue

    /// 用户写下的关于它的记忆，只保存在本机
    var memory: String = ""
    /// 传统色名，例如"天青"
    var colorName: String = ""
    /// 主色，用于卡片点缀和粒子
    var paletteHex: [String] = []

    var createdAt: Date = Date.now
    var releasedAt: Date?
    var farewellNote: String = ""

    // MARK: 传灵

    /// 物灵的"血脉"编号，传到谁手里都不变
    var lineageID: UUID = UUID()
    /// 历任主人的章节（JSON 编码的 [RelayChapter]）
    var chaptersData: Data = Data()
    /// "" 同住 / "released" 送别 / "relayed" 传出
    var departureRaw: String = ""
    /// 从别人那里接过来的日子；自己唤醒的为 nil
    var receivedAt: Date?

    @Attribute(.externalStorage) var spiritImageData: Data?
    @Attribute(.externalStorage) var stickerImageData: Data?
    /// 插画是否为离线占位（没有连上图像 API 时）
    var isPlaceholderArt: Bool = false

    init(
        serial: Int,
        profile: SpiritProfile,
        objectName: String,
        object: ObjectKind,
        companionship: Companionship,
        memory: String,
        colorName: String,
        palette: [RGB],
        spiritImageData: Data?,
        stickerImageData: Data?,
        isPlaceholderArt: Bool
    ) {
        self.serial = serial
        self.name = profile.name
        self.epithet = profile.epithet
        self.personality = profile.personality
        self.objectName = objectName
        self.objectEnglish = object.english
        self.familyRaw = object.family.rawValue
        self.companionshipRaw = companionship.rawValue
        self.memory = memory
        self.colorName = colorName
        self.paletteHex = palette.map(\.hex)
        self.spiritImageData = spiritImageData
        self.stickerImageData = stickerImageData
        self.isPlaceholderArt = isPlaceholderArt
    }

    var isReleased: Bool { releasedAt != nil }
    var isRelayed: Bool { departureRaw == "relayed" }
    /// 我开始拥有它的日子
    var myStart: Date { receivedAt ?? createdAt }
    /// 离开时盖的印
    var departureSeal: String { isRelayed ? "已传出" : "已送别" }

    var chapters: [RelayChapter] {
        get {
            guard !chaptersData.isEmpty else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try? decoder.decode([RelayChapter].self, from: chaptersData)) ?? []
        }
        set {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            chaptersData = (try? encoder.encode(newValue)) ?? Data()
        }
    }

    var companionship: Companionship {
        Companionship(rawValue: companionshipRaw) ?? .years
    }

    var family: ObjectFamily {
        ObjectFamily(rawValue: familyRaw) ?? .other
    }

    var palette: [RGB] {
        paletteHex.compactMap(RGB.init(hex:))
    }

    func release(note: String, at date: Date = .now) {
        farewellNote = note
        releasedAt = date
        departureRaw = "released"
    }

    /// 传给下一位主人
    func relay(chapters: [RelayChapter], noteToNext: String, at date: Date = .now) {
        self.chapters = chapters
        farewellNote = noteToNext
        releasedAt = date
        departureRaw = "relayed"
    }

    /// 打包成可以隔空投送的胶囊
    func makeCapsule(chapters: [RelayChapter]) -> SpiritCapsule {
        SpiritCapsule(
            lineageID: lineageID,
            name: name,
            epithet: epithet,
            personality: personality,
            objectName: objectName,
            objectEnglish: objectEnglish,
            familyRaw: familyRaw,
            colorName: colorName,
            paletteHex: paletteHex,
            isPlaceholderArt: isPlaceholderArt,
            awakenedAt: chapters.first?.receivedAt ?? createdAt,
            chapters: chapters,
            spiritImage: spiritImageData,
            stickerImage: stickerImageData
        )
    }

    /// 从收到的胶囊创建（我是新主人）
    convenience init(capsule: SpiritCapsule, serial: Int, chapters: [RelayChapter], receivedAt: Date = .now) {
        self.init(
            serial: serial,
            profile: SpiritProfile(name: capsule.name, epithet: capsule.epithet,
                                   personality: capsule.personality, farewellSuggestion: ""),
            objectName: capsule.objectName,
            object: ObjectKind(chinese: capsule.objectName, english: capsule.objectEnglish,
                               family: ObjectFamily(rawValue: capsule.familyRaw) ?? .other),
            companionship: .days,
            memory: "",
            colorName: capsule.colorName,
            palette: capsule.paletteHex.compactMap(RGB.init(hex:)),
            spiritImageData: capsule.spiritImage,
            stickerImageData: capsule.stickerImage,
            isPlaceholderArt: capsule.isPlaceholderArt
        )
        self.lineageID = capsule.lineageID
        self.chapters = chapters
        self.receivedAt = receivedAt
        self.createdAt = receivedAt
    }
}
