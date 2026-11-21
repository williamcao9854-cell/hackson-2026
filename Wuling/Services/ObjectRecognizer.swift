import CoreML
import Vision

/// 设备端物品识别。
///
/// 两个模型一起看：
/// - 打包进 App 的 **Core ML 模型 MobileNetV2**（Apple 官方提供，ImageNet 1000 类）
/// - Vision 内置分类器（类别更多，能补上耳机、钥匙、毛绒玩具这类 ImageNet 没有的东西）
/// 结果给出一个最佳猜测和几个候选，用户可以一键改正。识别全程在本机完成。
enum ObjectRecognizer {
    struct Candidate {
        var identifier: String
        var confidence: Float
    }

    struct Recognition {
        var best: ObjectKind
        /// 给用户选的候选，最多 4 个
        var candidates: [ObjectKind]
    }

    /// 编译好的 Core ML 模型，首次使用时加载一次。
    private static let coreMLModel: VNCoreMLModel? = {
        guard let url = Bundle.main.url(forResource: "MobileNetV2Int8LUT", withExtension: "mlmodelc") else {
            return nil
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        guard let model = try? MLModel(contentsOf: url, configuration: configuration) else { return nil }
        return try? VNCoreMLModel(for: model)
    }()

    /// Core ML 的结果在前（更细的物品类别），Vision 的结果在后（补充 ImageNet 没有的类别）
    static func classify(_ cgImage: CGImage) -> [Candidate] {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        var candidates: [Candidate] = []

        if let model = coreMLModel {
            let request = VNCoreMLRequest(model: model)
            // 图片已经补成正方形，这里缩放进模型，不裁剪
            request.imageCropAndScaleOption = .scaleFit
            if (try? handler.perform([request])) != nil,
               let results = request.results as? [VNClassificationObservation] {
                candidates += results.prefix(10).map { Candidate(identifier: $0.identifier, confidence: $0.confidence) }
            }
        }

        let visionRequest = VNClassifyImageRequest()
        if (try? handler.perform([visionRequest])) != nil, let results = visionRequest.results {
            candidates += results
                .filter { $0.confidence > 0.1 }
                .prefix(10)
                .map { Candidate(identifier: $0.identifier.replacingOccurrences(of: "_", with: " "), confidence: $0.confidence) }
        }
        return candidates
    }

    static func recognize(_ cgImage: CGImage) -> Recognition {
        let labels: [(identifier: String, confidence: Float)] = classify(cgImage).map { ($0.identifier, $0.confidence) }
        let candidates = ObjectCatalog.rankedKinds(from: labels, limit: 4)
        return Recognition(best: candidates.first ?? ObjectCatalog.bestMatch(from: labels), candidates: candidates)
    }
}
