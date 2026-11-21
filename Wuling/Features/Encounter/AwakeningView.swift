import SwiftUI

/// ④ 唤醒：等待生成时，用呼吸、涟漪和几句轻声细语把时间填满。
struct AwakeningView: View {
    var sticker: UIImage?

    @State private var lineIndex = 0
    @State private var breathing = false

    private let lines = [
        "它在慢慢醒来",
        "它想起了你们一起的日子",
        "它在给自己挑一个名字",
        "就快好了",
    ]

    var body: some View {
        VStack(spacing: 44) {
            Spacer()

            ZStack {
                Ripples()
                    .frame(width: 320, height: 320)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.vermilion.opacity(0.18), Color.vermilion.opacity(0)],
                            center: .center, startRadius: 10, endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .scaleEffect(breathing ? 1.08 : 0.92)

                if let sticker {
                    StickerView(image: sticker, lifted: true)
                        .frame(width: 190, height: 190)
                        .scaleEffect(breathing ? 1.02 : 0.97)
                        .offset(y: breathing ? -6 : 4)
                }
            }

            VStack(spacing: 10) {
                Text(lines[lineIndex] + "……")
                    .font(.wlQuote)
                    .id(lineIndex)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity.combined(with: .offset(y: -8))
                    ))
                Text("Awakening").eyebrow()
            }
            .frame(height: 60)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.wlCalm) {
                    lineIndex = min(lineIndex + 1, lines.count - 1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("物灵正在醒来，请稍候")
    }
}

/// 向外缓缓扩散的墨线涟漪
private struct Ripples: View {
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = min(size.width, size.height) / 2
                for i in 0..<3 {
                    let p = (t / 4.2 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let radius = maxRadius * (0.35 + 0.65 * p)
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(Color.ink.opacity(0.14 * (1 - p))), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    AwakeningView(sticker: nil)
        .background(PaperBackground())
}
