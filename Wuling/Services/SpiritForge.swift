import Foundation

/// 物灵图像生成的统一入口。
///
/// - 配置了 `Secrets.plist`：调用 AMD 图像生成 API（OpenAI 兼容格式）
/// - 没有配置：返回 nil，由调用方使用离线占位插画
enum SpiritForge {
    static let generator: SpiritImageGenerating? = {
        guard let config = ImageGenerationConfig.load() else { return nil }
        return OpenAICompatibleImageGenerator(config: config)
    }()

    static var isImageAPIConfigured: Bool { generator != nil }

    /// 成功返回图片数据；失败时返回给用户看的说明文字。
    static func generateArt(for seed: SpiritSeed) async -> (data: Data?, notice: String?) {
        guard let generator else {
            return (nil, "未连接图像服务，先以水彩剪影代替。")
        }
        do {
            let data = try await generator.generateImage(prompt: SpiritPrompt.make(for: seed))
            return (data, nil)
        } catch {
            return (nil, "图像服务暂时没有回应，先以水彩剪影代替。")
        }
    }
}
