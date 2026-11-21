import CoreML
import Vision

/// 设备端物品识别。
///
/// 优先使用打包进 App 的 **Core ML 模型 MobileNetV2**（Apple 官方提供，ImageNet 1000 类），
/// 模型不可用时退回 Vision 内置的分类器。识别全程在本机完成。
enum ObjectRecognizer {
    struct Candidate {
        var identifier: String
        var confidence: Float
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

    /// 返回按置信度从高到低排列的候选标签
    static func classify(_ cgImage: CGImage) -> [Candidate] {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        if let model = coreMLModel {
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .centerCrop
            if (try? handler.perform([request])) != nil,
               let results = request.results as? [VNClassificationObservation], !results.isEmpty {
                return results.prefix(10).map { Candidate(identifier: $0.identifier, confidence: $0.confidence) }
            }
        }

        let fallback = VNClassifyImageRequest()
        if (try? handler.perform([fallback])) != nil, let results = fallback.results {
            return results
                .filter { $0.confidence > 0.05 }
                .prefix(10)
                .map { Candidate(identifier: $0.identifier.replacingOccurrences(of: "_", with: " "), confidence: $0.confidence) }
        }
        return []
    }

    /// 识别并映射成中文物品
    static func recognize(_ cgImage: CGImage) -> ObjectKind {
        let candidates = classify(cgImage)
        return ObjectCatalog.bestMatch(from: candidates.map { ($0.identifier, $0.confidence) })
    }
}
