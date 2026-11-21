import UIKit

/// 在后台线程解码图片，并提前准备好显示用的位图，避免在主线程上卡顿。
enum ImageDecoding {
    static func decode(_ data: Data?) async -> UIImage? {
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
    }
}
