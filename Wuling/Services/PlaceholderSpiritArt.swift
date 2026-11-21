import SwiftUI

/// 离线占位插画：没有配置图像 API、或者网络不好时使用。
///
/// 把贴纸放在一团用物品主色晕染出的"水彩"上，右下角落一枚小朱印。
/// 风格和真实生成的插画保持一致（和纸底色、留白、朱红点缀），所以混在图鉴里也不突兀。
enum PlaceholderSpiritArt {
    @MainActor
    static func render(sticker: UIImage, palette: [RGB], side: CGFloat = 1024) -> Data? {
        // 不直接用照片：先处理成水墨线条 + 淡彩，看起来像一幅画，而不是一张产品照
        let painted = ImageProcessing.inkWash(sticker) ?? sticker
        let view = PlaceholderArtwork(sticker: painted, palette: palette)
            .frame(width: side, height: side)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }
}

private struct PlaceholderArtwork: View {
    var sticker: UIImage
    var palette: [RGB]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let colors = palette.isEmpty ? [RGB(r: 0.78, g: 0.27, b: 0.18)] : palette
            ZStack {
                Color(red: 0xF4 / 255, green: 0xF0 / 255, blue: 0xE8 / 255)

                // 水彩晕染：几团不同大小、不同位置的径向渐变
                ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { index, rgb in
                    let offsets: [CGSize] = [CGSize(width: -0.06, height: 0.04), CGSize(width: 0.12, height: -0.08), CGSize(width: -0.1, height: -0.12)]
                    RadialGradient(
                        colors: [Color(rgb: rgb).opacity(0.28), Color(rgb: rgb).opacity(0.0)],
                        center: .center, startRadius: 0, endRadius: side * (0.42 - Double(index) * 0.08)
                    )
                    .offset(x: offsets[index].width * side, y: offsets[index].height * side)
                    .blur(radius: side * 0.03)
                }

                Image(uiImage: sticker)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side * 0.56, height: side * 0.56)
                    .rotationEffect(.degrees(-4))
                    .shadow(color: .black.opacity(0.12), radius: side * 0.02, y: side * 0.015)

                SealStamp(text: "物灵", size: side * 0.07, rotation: .degrees(-6))
                    .position(x: side * 0.86, y: side * 0.88)
            }
            .frame(width: side, height: side)
        }
    }
}
