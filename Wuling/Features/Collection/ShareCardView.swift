import SwiftUI

/// 分享用的物灵卡片（4:5 竖版，适合发朋友圈和小红书）。
struct ShareCardView: View {
    let spirit: Spirit

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                SpiritArtView(data: spirit.spiritImageData, contentMode: .fill)
                    .frame(width: 312, height: 312)
                    .clipped()
                VerticalText(text: spirit.name, font: .wlSpiritName(34))
                    .padding(.top, 18)
                    .padding(.trailing, 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(spirit.epithet)
                    .font(.system(size: 18, weight: .semibold))
                Text(spirit.personality)
                    .font(.system(size: 13, design: .serif))
                    .lineSpacing(4)
                    .foregroundStyle(Color.ink.opacity(0.8))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)

            Spacer(minLength: 12)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("物灵 · 万物有灵")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(WLFormat.serial(spirit.serial))　\(WLFormat.date(spirit.releasedAt ?? spirit.createdAt))")
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(.inkSecondary)
                }
                Spacer()
                let seals = spirit.chapters.map(\.ownerSeal)
                if seals.count > 1 {
                    CollectorSeals(seals: seals, size: 26, limit: 3)
                        .padding(.trailing, 6)
                }
                SealStamp(text: spirit.isReleased ? spirit.departureSeal : "同住", size: 44)
            }
        }
        .foregroundStyle(.ink)
        .padding(24)
        .frame(width: 360, height: 450)
        .background(PaperBackground())
    }
}
