import Foundation
import SwiftData

/// 一个物灵。
///
/// 两种状态：
/// - 同住：物品还留在身边（`releasedAt == nil`）
/// - 已送别：物品已经放手，物灵与记忆留在图鉴里
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
    }
}
