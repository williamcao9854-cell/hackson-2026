import CoreML
import Vision

/// 设备端物品识别。
///
/// - **Core ML 模型 FastViT-MA36**（Apple 官方提供，ImageNet 准确率约 84%），打包在 App 里
/// - **Vision 内置分类器**：类别更多，能补上耳机、钥匙、毛绒玩具这类 ImageNet 没有的东西
///
/// 抠出来的主体和整张照片各识别一次，两个模型的结果加权合并：几个来源都认同的物品排在最前。
/// 没有把握时不硬猜，交给用户确认。全部在本机完成。
enum ObjectRecognizer {
    struct Recognition {
        var best: ObjectKind
        /// 给用户选的候选，最多 4 个
        var candidates: [ObjectKind]
        /// 最佳结果是否足够可信。不可信时界面会问"它是什么？"，而不是填一个可能错的名字
        var isConfident: Bool
    }

    /// 打包进 App 的模型，按顺序尝试
    private static let modelNames = ["FastViTMA36F16", "MobileNetV2Int8LUT"]

    private static let coreMLModel: VNCoreMLModel? = {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        for name in modelNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
                  let model = try? MLModel(contentsOf: url, configuration: configuration),
                  let visionModel = try? VNCoreMLModel(for: model) else { continue }
            return visionModel
        }
        return nil
    }()

    static func classifyWithCoreML(_ cgImage: CGImage) -> [(identifier: String, confidence: Float)] {
        guard let model = coreMLModel else { return [] }
        let request = VNCoreMLRequest(model: model)
        // 主体已经补成正方形，这里缩放进模型，不裁剪
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let results = request.results as? [VNClassificationObservation] else { return [] }
        return results.prefix(10).map { ($0.identifier, $0.confidence) }
    }

    static func classifyWithVision(_ cgImage: CGImage) -> [(identifier: String, confidence: Float)] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        guard (try? handler.perform([request])) != nil, let results = request.results else { return [] }
        return results
            .filter { $0.confidence > 0.1 }
            .prefix(12)
            .map { ($0.identifier.replacingOccurrences(of: "_", with: " "), $0.confidence) }
    }

    /// - subject: 抠出的主体（白底正方形）
    /// - scene: 整张照片，提供上下文；没抠到主体时传 nil
    static func recognize(subject: CGImage, scene: CGImage?) -> Recognition {
        var sources = [
            ObjectCatalog.LabelSource(labels: classifyWithCoreML(subject), weight: 1.0),
            ObjectCatalog.LabelSource(labels: classifyWithVision(subject), weight: 0.7),
        ]
        if let scene {
            sources.append(ObjectCatalog.LabelSource(labels: classifyWithCoreML(scene), weight: 0.45))
            sources.append(ObjectCatalog.LabelSource(labels: classifyWithVision(scene), weight: 0.3))
        }
        let scored = ObjectCatalog.scoredKinds(from: sources)
        let best = scored.first?.kind ?? ObjectCatalog.bestMatch(from: sources[0].labels)
        return Recognition(
            best: best,
            candidates: scored.prefix(4).map(\.kind),
            isConfident: (scored.first?.score ?? 0) >= 0.35
        )
    }
}
