import SwiftUI

/// 鉴藏印：历任主人的名章，交替使用白文、朱文，微微错落。
struct CollectorSeals: View {
    var seals: [String]
    var size: CGFloat = 30
    /// 最多显示几枚，超出的显示 "+N"
    var limit: Int = 4

    var body: some View {
        HStack(spacing: -size * 0.18) {
            ForEach(Array(seals.prefix(limit).enumerated()), id: \.offset) { index, seal in
                SealStamp(
                    text: seal,
                    size: size,
                    rotation: .degrees([-7, 5, -3, 8][index % 4]),
                    style: index.isMultiple(of: 2) ? .yin : .yang
                )
                .offset(y: index.isMultiple(of: 2) ? 0 : -size * 0.12)
            }
            if seals.count > limit {
                Text("+\(seals.count - limit)")
                    .font(.wlCaption)
                    .foregroundStyle(.vermilion)
                    .padding(.leading, size * 0.3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("历任主人：" + seals.joined(separator: "、"))
    }
}

/// 流转：像一幅竖着展开的长卷，记下每一位主人和它的日子。
struct RelayTimeline: View {
    var chapters: [RelayChapter]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 0) {
                        SealStamp(text: chapter.ownerSeal, size: 40, rotation: .degrees(index.isMultiple(of: 2) ? -5 : 4),
                                  style: index.isMultiple(of: 2) ? .yin : .yang)
                        if index < chapters.count - 1 {
                            Rectangle()
                                .fill(Color.hairline)
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                    .frame(width: 44)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("第 \(index + 1) 位主人")
                            .font(.wlHeadline)
                        Text(dateRange(chapter))
                            .font(.wlCaption)
                            .monospacedDigit()
                            .foregroundStyle(.inkSecondary)
                        if !chapter.memory.isEmpty {
                            Text(chapter.memory)
                                .font(.wlBody)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !chapter.noteToNext.isEmpty {
                            Text("写给下一位：「\(chapter.noteToNext)」")
                                .font(.system(size: 14, design: .serif))
                                .foregroundStyle(.ink.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, index < chapters.count - 1 ? 24 : 0)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func dateRange(_ chapter: RelayChapter) -> String {
        let start = WLFormat.date(chapter.receivedAt)
        let end = chapter.passedAt.map(WLFormat.date) ?? "至今"
        return "\(start) — \(end)"
    }
}

#Preview {
    VStack(spacing: 40) {
        CollectorSeals(seals: ["小林", "阿明", "周周", "老陈", "七七"])
        RelayTimeline(chapters: [
            RelayChapter(ownerSeal: "小林", receivedAt: .now.addingTimeInterval(-90_000_000), passedAt: .now.addingTimeInterval(-3_000_000),
                         memory: "高三那年，每天晚自习后弹半小时。", noteToNext: "它怕潮，下雨天别带它出门。"),
            RelayChapter(ownerSeal: "阿明", receivedAt: .now.addingTimeInterval(-3_000_000)),
        ])
    }
    .padding()
    .background(PaperBackground())
}
