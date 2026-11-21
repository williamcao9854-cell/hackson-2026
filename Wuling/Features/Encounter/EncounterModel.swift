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
    /// 识别给出的候选，用户可以一键改正
    var candidates: [ObjectKind] = []
    /// 识别没把握时为 true：名字留空，请用户告诉我们它是什么
    var needsNaming = false
    /// 端侧大模型看图写下的外观描述（会写进生成提示词）
    var appearance = ""
    /// 是否由端侧大模型认出（界面上显示一个小标记）
    var recognizedByModel = false
    var palette: [RGB] = []

    // 讲讲它
    var objectName = ""
    var companionship: Companionship = .years
    var memory = ""
    var wearMarks: Set<WearMark> = []

    // 唤醒结果
    var profile: SpiritProfile?
    var spiritImageData: Data?
    /// 从插画里抠出的物灵，用来做立牌
    var figureImageData: Data?
    var isPlaceholderArt = false
    var notice: String?

    /// 已保存到图鉴的物灵（选择送别或留下之后）
    private(set) var savedSpirit: Spirit?

    var sticker: UIImage? { cutout?.sticker }

    /// 物灵已经唤醒，但还没有存进图鉴（这时关闭需要确认）
    var hasUnsavedSpirit: Bool { profile != nil && savedSpirit == nil }

    /// 用户改了名字时（比如"外婆的闹钟"），尽量换成对应的物品类别，让生成结果跟着变
    /// 用户手动输入、目录里也没有的物品名，翻译成的英文（由端侧模型提供）
    private var translatedEnglish: [String: String] = [:]

    private var resolvedObject: ObjectKind {
        let name = objectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == object.chinese { return object }
        if let known = ObjectCatalog.kind(matchingChinese: name) { return known }
        // 目录里没有（比如"魔方"）：用户已经否定了识别结果，不再沿用它
        return ObjectKind(chinese: name, english: translatedEnglish[name] ?? "", family: .other)
    }

    func choose(_ kind: ObjectKind) {
        object = kind
        objectName = kind.chinese
        needsNaming = false
    }

    /// 给物灵改名（初见时点名字即可修改）
    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile?.name = trimmed
    }

    func toggle(_ mark: WearMark) {
        if wearMarks.contains(mark) { wearMarks.remove(mark) } else { wearMarks.insert(mark) }
    }

    /// 拍得不满意：回到取景
    func retake() {
        photo = nil
        cutout = nil
        object = .unknown
        candidates = []
        needsNaming = false
        appearance = ""
        recognizedByModel = false
        palette = []
        objectName = ""
        wearMarks = []
        withAnimation(.wlCalm) { stage = .capture }
    }

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
            let subject = cutout.foundSubject ? ImageProcessing.onWhite(cutout.subject) : normalized.cgImage
            let scene = cutout.foundSubject ? normalized.cgImage : nil
            let recognition = subject.map { ObjectRecognizer.recognize(subject: $0, scene: scene) }
            let palette = ImageProcessing.dominantColors(of: cutout.foundSubject ? cutout.subject : normalized)
            return (normalized, cutout, recognition, palette, subject)
        }.value

        // 优先让端侧大模型看图（iOS 27 起）；不支持时用上面分类模型的结果
        let seen: OnDeviceVision.Seen?
        if let subject = processed.4 {
            seen = await OnDeviceVision.identify(subject)
        } else {
            seen = nil
        }

        photo = processed.0
        cutout = processed.1
        palette = processed.3
        let classifierCandidates = processed.2?.candidates ?? []
        if let seen {
            object = seen.kind
            appearance = seen.appearance
            recognizedByModel = true
            needsNaming = false
            candidates = [seen.kind] + classifierCandidates.filter { $0.chinese != seen.kind.chinese }
        } else {
            object = processed.2?.best ?? .unknown
            appearance = ""
            recognizedByModel = false
            needsNaming = !(processed.2?.isConfident ?? false)
            candidates = classifierCandidates
        }
        objectName = needsNaming ? "" : object.chinese
        isProcessingPhoto = false

        withAnimation(.wlCalm) { stage = .story }
    }

    // MARK: - 唤醒

    private var seed: SpiritSeed {
        let name = objectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = resolvedObject
        return SpiritSeed(
            object: kind,
            displayName: name.isEmpty ? kind.chinese : name,
            color: color,
            palette: palette,
            companionship: companionship,
            memory: memory,
            wearMarks: WearMark.allCases.filter { wearMarks.contains($0) },
            // 用户把名字改成别的东西时，模型看到的外观可能已经不对应了，就不用它
            appearance: kind.chinese == object.chinese ? appearance : ""
        )
    }

    func awaken() async {
        withAnimation(.wlCalm) { stage = .awakening }
        let typedName = objectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedObject.english.isEmpty, !typedName.isEmpty,
           let english = await OnDeviceSpiritWriter.englishName(for: typedName) {
            translatedEnglish[typedName] = english
        }
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

        // 从插画里抠出物灵，做成立牌（插画背景是素净的和纸，抠起来很干净）
        let finalArt = imageData
        let figure: Data? = await Task.detached(priority: .userInitiated) {
            finalArt.flatMap(ImageProcessing.figure(fromArt:))
        }.value

        self.profile = profile
        self.spiritImageData = imageData
        self.figureImageData = figure
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

        let seed = self.seed
        let spirit = Spirit(
            serial: Spirit.nextSerial(in: context),
            profile: profile,
            objectName: seed.displayName,
            object: seed.object,
            companionship: companionship,
            memory: memory.trimmingCharacters(in: .whitespacesAndNewlines),
            colorName: color.name,
            palette: palette,
            spiritImageData: spiritImageData,
            stickerImageData: sticker.map { ImageCompression.resized($0, maxDimension: 900) }?.pngData(),
            isPlaceholderArt: isPlaceholderArt
        )
        spirit.figureImageData = figureImageData
        if let note { spirit.release(note: note) }
        context.insert(spirit)
        try? context.save()
        savedSpirit = spirit
        return spirit
    }
}
