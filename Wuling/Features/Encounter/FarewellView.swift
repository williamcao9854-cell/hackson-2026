import SwiftUI

/// ⑥ 送别仪式：道一声谢 → 长按印章 → 原物化作光点散去 → 朱印盖下。
///
/// 在「遇见」流程的最后使用，也可以从图鉴里给"同住"的物灵补办送别。
struct FarewellView: View {
    var sticker: UIImage?
    var spiritImageData: Data?
    var spiritName: String
    var palette: [RGB]
    var suggestion: String
    var onReleased: (String) -> Void
    var onFinish: () -> Void
    /// 从详情页打开时提供，左上角显示关闭按钮（送别开始后隐藏）
    var onCancel: (() -> Void)? = nil

    private enum Phase { case writing, dissolving, sealed }

    @State private var note = ""
    @State private var phase: Phase = .writing
    @State private var dissolveStart = Date.now
    @State private var stampLanded = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("送别").eyebrow()
                Text(phase == .sealed ? "它会一直记得你" : "向\(spiritName)道别")
                    .font(.system(size: 26, weight: .semibold))
                    .contentTransition(.opacity)
            }
            .padding(.top, 64)

            Spacer(minLength: 16)

            stage
                .frame(height: 300)

            Spacer(minLength: 16)

            bottom
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 16)
        }
        .animation(.wlCalm, value: phase)
        .sensoryFeedback(.impact(weight: .heavy), trigger: stampLanded)
        .overlay(alignment: .topLeading) {
            if let onCancel, phase == .writing {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(.ink)
                .padding(.leading, Metrics.gutter)
                .padding(.top, 8)
                .accessibilityLabel("先不送别")
            }
        }
    }

    // MARK: - 舞台：原物 → 光点 → 物灵 + 朱印

    @ViewBuilder
    private var stage: some View {
        ZStack {
            // 物灵插画，送别完成后浮现
            SpiritArtView(data: spiritImageData)
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .opacity(phase == .sealed ? 1 : 0)
                .scaleEffect(phase == .sealed ? 1 : 0.9)
                .overlay(alignment: .bottomTrailing) {
                    SealStamp(text: "已送别", size: 72)
                        .scaleEffect(stampLanded ? 1 : 1.8)
                        .opacity(stampLanded ? 1 : 0)
                        .offset(x: 14, y: 14)
                }

            // 原物贴纸，送别时消散
            if let sticker {
                StickerView(image: sticker, lifted: phase == .writing)
                    .frame(width: 220, height: 220)
                    .opacity(phase == .writing ? 1 : 0)
                    .blur(radius: phase == .writing ? 0 : 16)
                    .scaleEffect(phase == .writing ? 1 : 1.12)
                    .animation(.easeOut(duration: 1.3), value: phase)
            }

            if phase != .writing {
                DissolveParticles(colors: particleColors, startDate: dissolveStart)
                    .frame(width: 320, height: 360)
            }
        }
    }

    private var particleColors: [Color] {
        palette.map(Color.init(rgb:)) + [Color.ink.opacity(0.6), .white]
    }

    // MARK: - 底部：写下谢谢 + 长按印章 / 完成

    @ViewBuilder
    private var bottom: some View {
        switch phase {
        case .writing:
            VStack(spacing: 22) {
                TextField(suggestion, text: $note, axis: .vertical)
                    .font(.wlQuote)
                    .multilineTextAlignment(.center)
                    .lineLimit(1...3)
                    .focused($noteFocused)
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.hairline).frame(height: 1)
                    }
                    .accessibilityLabel("对它说一句谢谢")

                HoldToReleaseButton {
                    release()
                }
            }
            .transition(.opacity)

        case .dissolving:
            Text(finalNote)
                .font(.wlQuote)
                .foregroundStyle(.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(height: 180)
                .transition(.opacity)

        case .sealed:
            VStack(spacing: 18) {
                Text("「\(finalNote)」")
                    .font(.wlQuote)
                    .multilineTextAlignment(.center)
                Text(WLFormat.date(.now))
                    .font(.wlCaption)
                    .monospacedDigit()
                    .foregroundStyle(.inkSecondary)
                Button(action: onFinish) {
                    Text("收入图鉴")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.vermilion)
                .padding(.top, 8)
            }
            .transition(.opacity.combined(with: .offset(y: 10)))
        }
    }

    private var finalNote: String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? suggestion : trimmed
    }

    private func release() {
        noteFocused = false
        onReleased(finalNote)
        dissolveStart = .now
        phase = .dissolving
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            phase = .sealed
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                stampLanded = true
            }
        }
    }
}
