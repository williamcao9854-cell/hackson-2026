import SwiftData
import SwiftUI

/// 示例数据：用于 Xcode 预览，以及带 `-demo-data` 启动参数时（自动截图用）。
/// 正常运行时不会插入。
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = try! ModelContainer(for: Spirit.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        for spirit in makeSamples() {
            container.mainContext.insert(spirit)
        }
        return container
    }()

    static var sample: Spirit {
        (try? container.mainContext.fetch(FetchDescriptor<Spirit>(sortBy: [SortDescriptor(\.serial)])).first) ?? makeSamples()[0]
    }

    /// 图鉴为空时插入示例物灵
    static func seedIfEmpty(_ context: ModelContext) {
        guard ((try? context.fetchCount(FetchDescriptor<Spirit>())) ?? 0) == 0 else { return }
        for spirit in makeSamples() { context.insert(spirit) }
        try? context.save()
    }

    static func makeSamples() -> [Spirit] {
        let items: [(String, String, ObjectFamily, Companionship, RGB, String, Bool)] = [
            ("跑鞋", "running shoe", .footwear, .years, RGB(r: 0.25, g: 0.55, b: 0.6), "高三那年，它陪我跑完了每一个清晨。", true),
            ("马克杯", "coffee mug", .vessel, .aboutAYear, RGB(r: 0.85, g: 0.6, b: 0.3), "", false),
            ("玩偶熊", "teddy bear", .toy, .decade, RGB(r: 0.45, g: 0.3, b: 0.18), "小时候每晚都抱着它睡。", true),
            ("随身听", "cassette player", .electronic, .years, RGB(r: 0.1, g: 0.1, b: 0.12), "", false),
        ]
        return items.enumerated().map { index, item in
            let kind = ObjectKind(chinese: item.0, english: item.1, family: item.2)
            let color = ColorNaming.traditionalColor(for: item.4)
            let seed = SpiritSeed(object: kind, displayName: item.0, color: color, palette: [item.4],
                                  companionship: item.3, memory: item.5)
            let profile = TemplateSpiritWriter.write(for: seed)
            let spirit = Spirit(serial: index + 1, profile: profile, objectName: item.0, object: kind,
                                companionship: item.3, memory: item.5, colorName: color.name, palette: [item.4],
                                spiritImageData: nil, stickerImageData: nil, isPlaceholderArt: false)
            if item.6 { spirit.release(note: profile.farewellSuggestion) }
            if index == 1 {
                spirit.receivedAt = .now.addingTimeInterval(-2_000_000)
                spirit.chapters = [
                    RelayChapter(ownerSeal: "小林", receivedAt: .now.addingTimeInterval(-60_000_000),
                                 passedAt: .now.addingTimeInterval(-2_000_000), companionshipRaw: Companionship.years.rawValue,
                                 memory: "考研那年，每天早上都用它泡一杯咖啡。", noteToNext: "别用洗碗机，它会掉色。"),
                    RelayChapter(ownerSeal: "阿明", receivedAt: .now.addingTimeInterval(-2_000_000)),
                ]
            }
            return spirit
        }
    }
}
