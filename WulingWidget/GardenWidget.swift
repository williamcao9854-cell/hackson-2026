import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 放灯（可交互：按钮在小组件进程里执行，不需要打开 App）

/// 小组件自己的河灯数。存在扩展自己的 UserDefaults 里：
/// 免费开发者账户没有 App Groups，和 App 不共享，正好用来演示"点一下，水上多一盏灯"。
enum LanternStore {
    private static let key = "wuling.widget.lanterns"
    /// 最多再放几盏，满了就让它们漂走，重新开始
    static let limit = 6

    static var released: Int { UserDefaults.standard.integer(forKey: key) }

    static func releaseOne() {
        let next = released >= limit ? 0 : released + 1
        UserDefaults.standard.set(next, forKey: key)
    }
}

struct ReleaseLanternIntent: AppIntent {
    static let title: LocalizedStringResource = "放一盏河灯"
    static let description: IntentDescription? = IntentDescription("在小组件的水面上放一盏河灯。")

    func perform() async throws -> some IntentResult {
        LanternStore.releaseOne()
        return .result()
    }
}

// MARK: - 时间线

struct GardenEntry: TimelineEntry {
    let date: Date
    /// 水上一共几盏灯（青履君那一盏 + 放的）
    let lanterns: Int

    var term: Almanac.Term { Almanac.term(at: date) }
    var phase: Almanac.Phase { Almanac.phase(at: date) }
    var lunar: String { Almanac.lunarDate(date) }
}

struct GardenProvider: TimelineProvider {
    func placeholder(in context: Context) -> GardenEntry {
        GardenEntry(date: .now, lanterns: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (GardenEntry) -> Void) {
        // 小组件库里的预览多放几盏灯，好看一些
        completion(GardenEntry(date: .now, lanterns: context.isPreview ? 3 : LanternStore.released + 1))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GardenEntry>) -> Void) {
        let now = Date.now
        let lanterns = LanternStore.released + 1
        // 时辰交替、午夜、节气交接时换画面；48 小时后再要一次
        let entries = ([now] + Almanac.boundaries(after: now)).map { GardenEntry(date: $0, lanterns: lanterns) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - 画面

struct GardenWidgetView: View {
    var entry: GardenEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    /// 深色模式下整幅景入夜（和 App 首页一样）
    private var phase: Almanac.Phase { colorScheme == .dark ? .night : entry.phase }
    private var palette: WidgetPalette { WidgetPalette(phase: phase, season: entry.term.season) }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            default: small
            }
        }
        .containerBackground(for: .widget) {
            InkLandscape(phase: phase, season: entry.term.season, lanterns: entry.lanterns,
                         celestial: family == .systemMedium ? UnitPoint(x: 0.22, y: 0.24) : UnitPoint(x: 0.3, y: 0.24))
        }
    }

    /// 小：右上竖排节气，左下物候与农历
    private var small: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Spacer(minLength: 0)
                Text(entry.term.pentad)
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entry.lunar)
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                VerticalLabel(text: entry.term.name, font: .system(size: 26, weight: .semibold, design: .serif), spacing: -2)
                    .widgetAccentable()
                SealMark(text: "物灵", size: 18)
            }
        }
        .foregroundStyle(palette.ink)
    }

    /// 中：左边山水和节气，右边一张青履君托河灯捎来的短笺，可以放灯
    private var medium: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                VerticalLabel(text: entry.term.name, font: .system(size: 26, weight: .semibold, design: .serif), spacing: -2)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(entry.term.pentad)
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(palette.ink)
            .frame(maxHeight: .infinity, alignment: .top)

            Spacer(minLength: 0)

            letter
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.62 }
        }
    }

    private var letter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("一封来信")
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .foregroundStyle(WidgetPalette.vermilion)
                Spacer(minLength: 4)
                Text(entry.lunar)
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(palette.secondary)
            }
            Text(entry.term.letterLine)
                .font(.system(size: 13, design: .serif))
                .lineSpacing(2)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .foregroundStyle(palette.ink)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                SealMark(text: "青履", size: 18)
                Text(Almanac.sampleSpirit)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
                Button(intent: ReleaseLanternIntent()) {
                    Label("放灯", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(WidgetPalette.vermilion))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.paper))
    }
}

struct GardenWidget: Widget {
    let kind = "WulingGarden"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GardenProvider()) { entry in
            GardenWidgetView(entry: entry)
        }
        .configurationDisplayName("园林")
        .description("此刻的节气与物候；送别过的物灵托河灯捎来短笺。中号可以点「放灯」，在水上放一盏河灯。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("园林 · 小", as: .systemSmall) {
    GardenWidget()
} timeline: {
    GardenEntry(date: .now, lanterns: 2)
}

#Preview("园林 · 中", as: .systemMedium) {
    GardenWidget()
} timeline: {
    GardenEntry(date: .now, lanterns: 3)
}
