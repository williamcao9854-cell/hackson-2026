import ARKit

/// 设备能力判断。
enum DeviceSupport {
    /// 是否带 LiDAR（iPhone 12 Pro 及之后的 Pro 机型、部分 iPad Pro）。
    ///
    /// 「AR 摆在桌上」和「LiDAR 精细扫描」只在这些机型上开放：
    /// 没有 LiDAR 时 Object Capture 不可用，AR 放置也容易漂、找不到桌面，演示时体验不好。
    static let hasLiDAR: Bool = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
}
