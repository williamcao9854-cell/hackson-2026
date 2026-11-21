import SwiftUI

/// 竖排文字，像挂轴上的题字。物灵名字专用。
///
/// `revealed` 控制逐字出现：传入已显示的字数，用于"名字一笔一笔写出来"的动画。
struct VerticalText: View {
    var text: String
    var font: Font = .wlSpiritName()
    var spacing: CGFloat = 2
    var revealed: Int? = nil
    /// 每列最多几个字，超出后向左另起一列（和古籍竖排一样从右往左）
    var maxPerColumn: Int = 5

    var body: some View {
        let characters = Array(text)
        let columns = stride(from: 0, to: max(characters.count, 1), by: maxPerColumn).map { start in
            Array(characters.enumerated())[start..<min(start + maxPerColumn, characters.count)]
        }
        HStack(alignment: .top, spacing: spacing * 3 + 2) {
            ForEach(Array(columns.enumerated().reversed()), id: \.offset) { _, column in
                VStack(spacing: spacing) {
                    ForEach(Array(column), id: \.offset) { index, character in
                        Text(String(character))
                            .font(font)
                            .opacity(isVisible(index) ? 1 : 0)
                            .blur(radius: isVisible(index) ? 0 : 6)
                            .offset(y: isVisible(index) ? 0 : -6)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func isVisible(_ index: Int) -> Bool {
        guard let revealed else { return true }
        return index < revealed
    }
}

#Preview {
    HStack(spacing: 30) {
        VerticalText(text: "青履丸")
        VerticalText(text: "墨芯君", font: .wlSpiritName(24))
    }
    .foregroundStyle(.ink)
    .padding()
    .background(PaperBackground())
}
