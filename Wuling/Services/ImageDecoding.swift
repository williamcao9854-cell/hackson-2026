import ImageIO
import UIKit

/// 在后台线程按目标尺寸下采样解码图片，并做内存缓存，避免主线程反复解压大图导致卡顿 / 死机。
enum ImageDecoding {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 48
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    static func cacheKey(for data: Data, maxDimension: CGFloat) -> NSString {
        var hash: UInt64 = 0xcbf29ce484222325
        let head = data.prefix(64)
        let tail = data.suffix(64)
        for b in head { hash = (hash ^ UInt64(b)) &* 0x100000001b3 }
        for b in tail { hash = (hash ^ UInt64(b)) &* 0x100000001b3 }
        return "\(data.count)-\(hash)-\(Int(maxDimension.rounded()))" as NSString
    }

    /// 命中内存缓存直接返回（O(1)，无主线程解码）
    static func cached(_ data: Data?, maxDimension: CGFloat = 1024) -> UIImage? {
        guard let data else { return nil }
        return cache.object(forKey: cacheKey(for: data, maxDimension: maxDimension))
    }

    /// 后台按最大边长下采样解码并缓存
    static func decode(_ data: Data?, maxDimension: CGFloat = 1024) async -> UIImage? {
        guard let data else { return nil }
        let key = cacheKey(for: data, maxDimension: maxDimension)
        if let hit = cache.object(forKey: key) { return hit }
        return await Task.detached(priority: .userInitiated) {
            guard let image = downsample(data, maxDimension: maxDimension) else { return nil }
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            cache.setObject(image, forKey: key, cost: cost)
            return image
        }.value
    }

    /// 同步解码（仅用于 ImageRenderer 离屏渲染分享图等必须同步拿到图的场景）
    static func decodeSync(_ data: Data?, maxDimension: CGFloat = 800) -> UIImage? {
        guard let data else { return nil }
        let key = cacheKey(for: data, maxDimension: maxDimension)
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = downsample(data, maxDimension: maxDimension) else { return nil }
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// 用 ImageIO 直接下采样解码，不先分配整张全尺寸位图
    private static func downsample(_ data: Data, maxDimension: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return UIImage(data: data)?.preparingForDisplay()
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, Int(maxDimension.rounded())),
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: cg)
        }
        return UIImage(data: data)?.preparingForDisplay()
    }
}
