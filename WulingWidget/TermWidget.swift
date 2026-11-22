import SwiftUI
import WidgetKit

/// 锁屏上的节气：今天是哪个节气、哪一候，离下一个节气还有几天。
struct TermEntry: TimelineEntry {
    let date: Date

    var term: Almanac.Term { Almanac.term(at: date) }
    var next: (days: Int, term: Almanac.Term) { Almanac.daysUntilNextTerm(from: date) }
    var lunar: String { Almanac.ganzhiYear(date) + Almanac.lunarDate(date) }
}

struct TermProvider: TimelineProvider {
    func placeholder(in context: Context) -> TermEntry { TermEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (TermEntry) -> Void) {
        completion(TermEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TermEntry>) -> Void) {
        let now = Date.now
        let entries = ([now] + Almanac.boundaries(after: now)).map(TermEntry.init(date:))
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TermWidgetView: View {
    var entry: TermEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        let term = entry.term
        switch family {
        case .accessoryCircular:
            // 一圈走完就是下一个节气
            Gauge(value: term.progress) {
                Text("节气")
            } currentValueLabel: {
                Text(term.name)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()

        case .accessoryRectangular:
            let next = entry.next
            VStack(alignment: .leading, spacing: 1) {
                Text("\(term.name) · \(term.pentad)")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(next.days == 0 ? "今天交\(next.term.name)" : "距\(next.term.name)还有 \(next.days) 天")
                    .font(.system(size: 12, design: .serif))
                Text(entry.lunar)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            // accessoryInline
            Text("\(term.name) · \(term.pentad)")
        }
    }
}

struct TermWidget: Widget {
    let kind = "WulingTerm"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TermProvider()) { entry in
            TermWidgetView(entry: entry)
        }
        .configurationDisplayName("节气")
        .description("今天是哪个节气、哪一候，离下一个节气还有几天。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview("节气 · 锁屏", as: .accessoryRectangular) {
    TermWidget()
} timeline: {
    TermEntry(date: .now)
}
