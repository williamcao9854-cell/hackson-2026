import SwiftUI

/// 节气来信：送别过的物灵托河灯（传出去的托鸿雁）捎回一张短笺。
/// 竖排写在八行笺上，一列一列从右往左显现，最后是物灵的名字、名章和干支日期。
struct LetterView: View {
    let letter: SeasonalLetter

    @Environment(\.dismiss) private var dismiss
    @State private var arrived = false
    @State private var revealedColumns = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                LetterPaper(letter: letter, revealedColumns: revealedColumns)
                    .frame(maxWidth: 460)
                    .padding(.horizontal, Metrics.gutter)
                    .opacity(arrived ? 1 : 0)
                    .scaleEffect(arrived ? 1 : 0.96)
                    .offset(y: arrived ? 0 : 24)

                Button {
                    dismiss()
                } label: {
                    Text("收好")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.vermilion)
                .frame(maxWidth: 460)
                .padding(.horizontal, Metrics.gutter)
                .opacity(arrived ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AmbientBackdrop(intensity: 0.35))
        .foregroundStyle(.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await unfold() }
        // 字一列列显现时，指尖跟着轻轻一下，像毛笔一笔笔落在纸上
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.35), trigger: revealedColumns)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Group {
                if letter.messenger == .lantern {
                    LanternGlyph()
                        .frame(width: 44, height: 44)
                } else {
                    GooseFlight(leftToRight: false, duration: 3.2)
                        .frame(height: 64)
                }
            }
            .frame(height: 64)

            Text("\(letter.term.name) · \(letter.term.pentad)").eyebrow()
            Text("一封来信")
                .font(.system(size: 24, weight: .semibold))
            Text(letter.arrival)
                .font(.system(size: 14))
                .foregroundStyle(.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 36)
        }
    }

    /// 河灯靠岸（水声）→ 信笺展开 → 字一列一列显现
    private func unfold() async {
        RitualSound.prepare([.lantern, .paper])
        AmbientMusic.duck(for: 3.5)
        try? await Task.sleep(for: .milliseconds(200))
        RitualSound.play(.lantern)
        withAnimation(.wlLift) { arrived = true }
        try? await Task.sleep(for: .milliseconds(380))
        RitualSound.play(.paper)
        try? await Task.sleep(for: .milliseconds(70))
        let total = LetterPaper.writtenColumns(for: letter)
        for column in 1...max(total, 1) {
            withAnimation(.easeOut(duration: 0.55)) { revealedColumns = column }
            try? await Task.sleep(for: .milliseconds(210))
        }
    }
}

/// 八行笺：朱丝栏，竖排，从右往左。正文之后一列落款（名字 + 名章），再一列干支日期。
struct LetterPaper: View {
    let letter: SeasonalLetter
    /// 已经显现的列数（从右数），用于逐列显现的动画
    var revealedColumns: Int = .max

    static let perColumn = 12
    /// 八行笺：至少八列，写不满的留空
    static let minColumns = 8

    @State private var width: CGFloat = 0

    /// 正文 + 落款 + 日期一共占几列
    static func writtenColumns(for letter: SeasonalLetter) -> Int {
        LetterLayout.columns(for: letter.paragraphs, perColumn: perColumn).count + 2
    }

    var body: some View {
        let bodyColumns = LetterLayout.columns(for: letter.paragraphs, perColumn: Self.perColumn)
        let count = max(Self.minColumns, bodyColumns.count + 2)
        let margin: CGFloat = 18
        let inner = max(220, (width > 0 ? width : 340) - margin * 2)
        let columnWidth = inner / CGFloat(count)
        let fontSize = min(21, columnWidth / 1.7)
        let cell = fontSize * 1.32
        // 多留一格：挂在列尾的标点
        let height = cell * CGFloat(Self.perColumn + 1)
        let rule = Color.vermilion.opacity(0.42)

        HStack(spacing: 0) {
            // 第 0 列在最右边
            ForEach(Array((0..<count).reversed()), id: \.self) { index in
                column(index, bodyColumns: bodyColumns, fontSize: fontSize, cell: cell, columnWidth: columnWidth)
                    .frame(width: columnWidth, height: height, alignment: .top)
                    .opacity(index < revealedColumns ? 1 : 0)
                    .blur(radius: index < revealedColumns ? 0 : 5)
                    .overlay(alignment: .leading) {
                        if index != count - 1 {
                            Rectangle().fill(rule).frame(width: 0.6)
                        }
                    }
            }
        }
        .padding(.vertical, cell * 0.35)
        .overlay {
            Rectangle().strokeBorder(rule, lineWidth: 1.2)
        }
        .padding(margin)
        .frame(maxWidth: .infinity)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 22, y: 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(letter.paragraphs.joined() + " " + letter.spiritName + "，" + letter.dateline)
    }

    @ViewBuilder
    private func column(_ index: Int, bodyColumns: [[Character]], fontSize: CGFloat, cell: CGFloat, columnWidth: CGFloat) -> some View {
        if index < bodyColumns.count {
            VStack(spacing: 0) {
                ForEach(Array(bodyColumns[index].enumerated()), id: \.offset) { _, character in
                    Self.cellView(character, fontSize: fontSize, cell: cell)
                }
            }
        } else if index == bodyColumns.count {
            // 落款：名字靠下，下面钤一方名章
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(Array(letter.spiritName.prefix(8).enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(.system(size: fontSize * 1.04, weight: .semibold, design: .serif))
                        .frame(height: cell)
                }
                SealStamp(text: String(letter.spiritName.prefix(4)), size: columnWidth * 0.78, rotation: .degrees(-4))
                    .padding(.top, cell * 0.2)
            }
            .padding(.bottom, cell * 0.3)
        } else if index == bodyColumns.count + 1 {
            // 日期：比正文小一号，也靠下
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(Array(letter.dateline.filter { $0 != " " }.enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(.system(size: fontSize * 0.78, design: .serif))
                        .frame(height: cell * 0.86)
                }
            }
            .foregroundStyle(.inkSecondary)
            .padding(.bottom, cell * 0.3)
        } else {
            Color.clear
        }
    }

    /// 竖排的一格。逗号、句号、顿号放在格子的右上角；引号换成竖排写法。
    private static func cellView(_ character: Character, fontSize: CGFloat, cell: CGFloat) -> some View {
        let isCornerMark = cornerMarks.contains(character)
        return Text(String(vertical(character)))
            .font(.system(size: isCornerMark ? fontSize * 0.8 : fontSize, design: .serif))
            .frame(maxWidth: .infinity)
            .frame(height: cell, alignment: isCornerMark ? .top : .center)
            .offset(x: isCornerMark ? fontSize * 0.32 : 0, y: isCornerMark ? -cell * 0.08 : 0)
    }

    private static let cornerMarks: Set<Character> = ["，", "。", "、"]

    private static func vertical(_ character: Character) -> Character {
        switch character {
        case "「": "﹁"
        case "」": "﹂"
        case "『": "﹃"
        case "』": "﹄"
        case "…": "︙"
        case "—": "︱"
        default: character
        }
    }
}

/// 首页园林上的「一封来信」：有没读的来信时才出现，安安静静地亮着一盏小灯。
struct LetterBadge: View {
    var messenger: SeasonalLetter.Messenger
    var textColor: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if messenger == .lantern {
                    LanternGlyph()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "bird")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("一封来信")
                    .font(.system(size: 13, weight: .medium, design: .serif))
                Circle()
                    .fill(Color.vermilion)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(textColor)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: Capsule())
    }
}

#Preview {
    Color.paper
        .sheet(isPresented: .constant(true)) {
            LetterView(letter: LetterPost.demo(on: .now, term: SolarTerm(date: .now), from: []))
        }
}
