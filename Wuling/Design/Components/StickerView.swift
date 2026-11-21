import SwiftUI

/// 抠出来的物品贴纸。
///
/// `lifted` 为 true 时，贴纸被"拎起来"：放大、投影加深，背后泛起一圈由物品自身颜色形成的光晕，
/// 同时一道流光从左上扫到右下。动效语言来自照片 App 的主体抠图。
struct StickerView: View {
    var image: UIImage
    var lifted: Bool = true

    @State private var shine: CGFloat = -1.2

    var body: some View {
        let sticker = Image(uiImage: image).resizable().scaledToFit()

        sticker
            .background {
                // 用贴纸自身模糊后的颜色当光晕
                sticker
                    .blur(radius: 28)
                    .opacity(lifted ? 0.55 : 0)
                    .scaleEffect(1.08)
            }
            .overlay {
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.75), location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: width * 0.35, height: geo.size.height * 2)
                    .rotationEffect(.degrees(22))
                    .position(x: width / 2 + shine * width, y: geo.size.height / 2)
                }
                .mask { sticker }
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(lifted ? 0.16 : 0.06), radius: lifted ? 22 : 6, y: lifted ? 16 : 3)
            .scaleEffect(lifted ? 1.03 : 0.97)
            .animation(.wlLift, value: lifted)
            .onAppear { if lifted { sweep() } }
            .onChange(of: lifted) { _, isLifted in if isLifted { sweep() } }
            .accessibilityHidden(true)
    }

    private func sweep() {
        shine = -1.2
        withAnimation(.easeInOut(duration: 1.2).delay(0.2)) {
            shine = 1.2
        }
    }
}

/// 物灵插画。没有图片时显示一个安静的占位。
struct SpiritArtView: View {
    var data: Data?
    var contentMode: ContentMode = .fit

    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            ZStack {
                Circle()
                    .fill(Color.ink.opacity(0.06))
                    .padding(28)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.inkSecondary)
            }
        }
    }
}
