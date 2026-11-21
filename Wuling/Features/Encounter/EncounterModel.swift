import SwiftData
import SwiftUI

/// 「遇见」流程的状态：取景 → 讲讲它 → 唤醒 → 初见 → 送别 / 留下
@MainActor
@Observable
final class EncounterModel {
    enum Stage: Equatable {
        case capture
        case story
        case awakening
        case reveal
        case farewell
    }

    var stage: Stage = .capture
    var isProcessingPhoto = false

    // 取景结果
    var photo: UIImage?
    var cutout: ImageProcessing.Cutout?
    var object: ObjectKind = .unknown
    var palette: [RGB] = []

    // 讲讲它
    var objectName = ""
    var companionship: Companionship = .years
    var memory = ""

    // 唤醒结果
    var profile: SpiritProfile?
    var spiritImageData: Data?
    var isPlaceholderArt = false
    var notice: String?

    /// 已保存到图鉴的物灵（选择送别或留下之后）
    private(set) var savedSpirit: Spirit?

    var sticker: UIImage? { cutout?.sticker }

    var color: TraditionalColor {
        ColorNaming.traditionalColor(for: palette.first ?? RGB(r: 0.5, g: 0.5, b: 0.5))
    }

    // MARK: - 取景

    /// 处理拍到 / 选中的照片：抠图、识别、取色，全部在设备端完成。
    func usePhoto(_ image: UIImage) async {
        isProcessingPhoto = true
        photo = image

        let processed = await Task.detached(priority: .userInitiated) {
            let normalized = ImageProcessing.normalized(image)
            let cutout = ImageProcessing.liftSubject(from: normalized)
            let source = cutout.foundSubject ? ImageProcessing.onWhite(cutout.subject) : normalized.cgImage
            let kind = source.map(ObjectRecognizer.recognize) ?? .unknown
            let palette = ImageProcessing.dominantColors(of: cutout.foundSubject ? cutout.subject : normalized)
            return (normalized, cutout, kind, palette)
        }.value

        photo = processed.0
        cutout = processed.1
        object = processed.2
        palette = processed.3
        objectName = processed.2.chinese
        isProcessingPhoto = false

        withAnimation(.wlCalm) { stage = .story }
    }

    // MARK: - 唤醒

    private var seed: SpiritSeed {
        let name = objectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return SpiritSeed(
            object: object,
            displayName: name.isEmpty ? object.chinese : name,
            color: color,
            palette: palette,
            companionship: companionship,
            memory: memory
        )
    }

    func awaken() async {
        withAnimation(.wlCalm) { stage = .awakening }
        let seed = self.seed
        let started = Date.now

        async let writtenProfile = OnDeviceSpiritWriter.write(for: seed)
        async let generatedArt = SpiritForge.generateArt(for: seed)
        let (profile, art) = await (writtenProfile, generatedArt)

        var imageData = art.data
        var placeholder = false
        if imageData == nil, let sticker {
            imageData = PlaceholderSpiritArt.render(sticker: sticker, palette: palette)
            placeholder = true
        }

        // 唤醒的氛围至少停留几秒，太快反而没有仪式感
        let minimum = 3.6
        let elapsed = Date.now.timeIntervalSince(started)
        if elapsed < minimum {
            try? await Task.sleep(for: .seconds(minimum - elapsed))
        }

        self.profile = profile
        self.spiritImageData = imageData
        self.isPlaceholderArt = placeholder
        self.notice = art.notice
        withAnimation(.wlCalm) { stage = .reveal }
    }

    // MARK: - 保存

    func beginFarewell() {
        withAnimation(.wlCalm) { stage = .farewell }
    }

    @discardableResult
    func save(in context: ModelContext, releasedWith note: String? = nil) -> Spirit? {
        if let savedSpirit {
            if let note, !savedSpirit.isReleased { savedSpirit.release(note: note) }
            try? context.save()
            return savedSpirit
        }
        guard let profile else { return nil }

        let count = (try? context.fetchCount(FetchDescriptor<Spirit>())) ?? 0
        let spirit = Spirit(
            serial: count + 1,
            profile: profile,
            objectName: seed.displayName,
            object: object,
            companionship: companionship,
            memory: memory.trimmingCharacters(in: .whitespacesAndNewlines),
            colorName: color.name,
            palette: palette,
            spiritImageData: spiritImageData,
            stickerImageData: sticker?.pngData(),
            isPlaceholderArt: isPlaceholderArt
        )
        if let note { spirit.release(note: note) }
        context.insert(spirit)
        try? context.save()
        savedSpirit = spirit
        return spirit
    }
}
