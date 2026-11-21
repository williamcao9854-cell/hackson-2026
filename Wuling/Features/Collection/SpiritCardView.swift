import SwiftUI

/// 图鉴里的一张物灵卡片。
struct SpiritCardView: View {
    let spirit: Spirit

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.card
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    SpiritArtView(data: spirit.spiritImageData, contentMode: .fill)
                }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    VerticalText(text: spirit.name, font: .wlSpiritName(19), spacing: 0)
                        .foregroundStyle(Color.ink)
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                }
                .overlay(alignment: .bottomLeading) {
                    if spirit.isReleased {
                        SealStamp(text: "送别", size: 28, rotation: .degrees(-10))
                            .padding(10)
                    }
                }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(spirit.objectName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(WLFormat.serial(spirit.serial))
                        .font(.wlCaption)
                        .monospacedDigit()
                        .foregroundStyle(.inkSecondary)
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(spirit.palette.first.map(Color.init(rgb:)) ?? Color.inkSecondary)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 10, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spirit.name)，\(spirit.objectName)，\(spirit.isReleased ? "已送别" : "同住")")
    }
}
