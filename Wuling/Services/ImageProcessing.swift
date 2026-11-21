import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// 设备端图像处理：统一方向与尺寸、抠出主体、做成贴纸、提取主色。
/// 全部在本机完成，照片不会离开手机。
enum ImageProcessing {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// 把照片转成"朝上"的方向，并把长边缩到 `maxDimension` 以内。
    static func normalized(_ image: UIImage, maxDimension: CGFloat = 1600) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// 抠图结果
    struct Cutout {
        /// 透明背景的主体（裁到主体边缘）
        var subject: UIImage
        /// 加了白边的贴纸
        var sticker: UIImage
        /// 是否真的抠到了主体（false 表示没找到，用整张照片做了一张圆角贴纸）
        var foundSubject: Bool
    }

    /// 用 Vision 抠出前景主体（和照片 App 长按抠图是同一种能力）。
    static func liftSubject(from image: UIImage) -> Cutout {
        guard let cgImage = image.cgImage else {
            return Cutout(subject: image, sticker: image, foundSubject: false)
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
            if let observation = request.results?.first {
                let buffer = try observation.generateMaskedImage(
                    ofInstances: observation.allInstances,
                    from: handler,
                    croppedToInstancesExtent: true
                )
                let subjectCI = CIImage(cvPixelBuffer: buffer)
                if let subjectCG = context.createCGImage(subjectCI, from: subjectCI.extent) {
                    let subject = UIImage(cgImage: subjectCG)
                    let sticker = makeSticker(from: subjectCI) ?? subject
                    return Cutout(subject: subject, sticker: sticker, foundSubject: true)
                }
            }
        } catch {
            // 模拟器或旧设备上可能不支持，退回整图贴纸
        }
        let fallback = roundedPhotoSticker(from: image)
        return Cutout(subject: image, sticker: fallback, foundSubject: false)
    }

    /// 从生成的物灵插画里抠出物灵本身（带白边），做成立牌。
    /// 插画的背景是素净的和纸，Vision 抠图非常干净。长边限制在 900px。
    static func figure(fromArt data: Data) -> Data? {
        guard let art = UIImage(data: data) else { return nil }
        let cutout = liftSubject(from: normalized(art, maxDimension: 1200))
        guard cutout.foundSubject else { return nil }
        let size = cutout.sticker.size
        let scale = min(1, 900 / max(size.width, size.height))
        guard scale < 1 else { return cutout.sticker.pngData() }
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            cutout.sticker.draw(in: CGRect(origin: .zero, size: target))
        }.pngData()
    }

    /// 给透明主体加一圈白边，像一张真正的贴纸。
    private static func makeSticker(from subject: CIImage) -> UIImage? {
        let extent = subject.extent
        let border = max(6, min(extent.width, extent.height) * 0.025)
        let padding = border * 2

        let moved = subject.transformed(by: CGAffineTransform(translationX: -extent.minX + padding, y: -extent.minY + padding))
        let canvas = CGRect(x: 0, y: 0, width: extent.width + padding * 2, height: extent.height + padding * 2)
        let padded = moved.composited(over: CIImage(color: .clear).cropped(to: canvas))

        // 膨胀 alpha 通道，得到比主体大一圈的轮廓
        let dilate = CIFilter.morphologyMaximum()
        dilate.inputImage = padded
        dilate.radius = Float(border)
        guard let dilated = dilate.outputImage?.cropped(to: canvas) else { return nil }

        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = CIImage(color: .white).cropped(to: canvas)
        blend.backgroundImage = CIImage(color: .clear).cropped(to: canvas)
        blend.maskImage = dilated
        guard let silhouette = blend.outputImage else { return nil }

        let sticker = padded.composited(over: silhouette)
        guard let cg = context.createCGImage(sticker, from: canvas) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 没抠到主体时：整张照片做成白边圆角"照片贴纸"。
    private static func roundedPhotoSticker(from image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let border = side * 0.04
        let total = CGSize(width: side + border * 2, height: side + border * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: total, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: total), cornerRadius: total.width * 0.12).fill()
            let inner = CGRect(x: border, y: border, width: side, height: side)
            UIBezierPath(roundedRect: inner, cornerRadius: side * 0.1).addClip()
            image.draw(in: CGRect(x: border - crop.minX, y: border - crop.minY, width: image.size.width, height: image.size.height))
        }
    }

    /// 主体居中铺在正方形白底上，方便分类模型识别。
    /// - 透明区域会被模型当成黑色，所以要铺白底
    /// - 吉他、雨伞、钢笔这类长条物体，如果不补成正方形，送进模型时头尾会被裁掉
    static func onWhite(_ image: UIImage) -> CGImage? {
        let side = max(image.size.width, image.size.height) * 1.12
        let canvas = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: canvas))
            image.draw(at: CGPoint(x: (side - image.size.width) / 2, y: (side - image.size.height) / 2))
        }
        return rendered.cgImage
    }

    /// 从主体里取出 2～3 个主色（只统计不透明的像素）。
    static func dominantColors(of image: UIImage, count: Int = 3) -> [RGB] {
        guard let cgImage = image.cgImage else { return [] }
        let side = 40
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }

        var samples: [RGB] = []
        samples.reserveCapacity(side * side)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[i + 3]) / 255
            guard alpha > 0.6 else { continue }
            samples.append(RGB(r: Double(pixels[i]) / 255 / alpha,
                               g: Double(pixels[i + 1]) / 255 / alpha,
                               b: Double(pixels[i + 2]) / 255 / alpha))
        }
        return KMeans.dominantColors(in: samples, k: count)
    }
}
