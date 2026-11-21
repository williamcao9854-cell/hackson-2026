import SwiftUI

/// 图鉴里的一张物灵卡片：像一幅装裱好的小画。
///
/// 插画四周留一圈纸边（"卡纸"），外加一道细框；名字和编号写在画下方，像展签。
/// 已送别 / 已传出的物灵，在画角盖一枚小印。
struct SpiritCardView: View {
    let spirit: Spirit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 画心 + 卡纸
            Color.paper
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    SpiritArtView(data: spirit.spiritImageData, contentMode: .fill)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.ink.opacity(0.12), lineWidth: 0.75)
                }
                .overlay(alignment: .bottomTrailing) {
                    if spirit.isReleased {
                        SealStamp(text: spirit.isRelayed ? "传出" : "送别", size: 26, rotation: .degrees(-8))
                            .padding(6)
                    }
                }
                .padding(8)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 8)

            // 展签
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(spirit.name)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)

            Text(caption)
                .font(.wlCaption)
                .monospacedDigit()
                .foregroundStyle(.inkSecondary)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.top, -6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spirit.name)，\(spirit.objectName)，\(spirit.isReleased ? spirit.departureSeal : "同住")")
    }

    private var accent: Color {
        spirit.palette.first.map(Color.init(rgb:)) ?? Color.inkSecondary
    }

    /// 例如："跑鞋 · No. 003" 或 "马克杯 · No. 002 · 第 2 代"
    private var caption: String {
        var parts = [spirit.objectName, WLFormat.serial(spirit.serial)]
        if spirit.chapters.count > 1 { parts.append("第 \(spirit.chapters.count) 代") }
        return parts.joined(separator: " · ")
    }
}
