import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 生成物灵图像的能力。真实接口（AMD 图像生成 API）和离线占位实现都遵循它。
protocol SpiritImageGenerating: Sendable {
    /// 返回 PNG / JPEG 数据
    func generateImage(prompt: String) async throws -> Data
}

enum ImageGenerationError: LocalizedError {
    case notConfigured
    case badStatus(Int, String)
    case emptyResponse
    case undecodableImage

    var errorDescription: String? {
        switch self {
        case .notConfigured: "还没有配置图像生成 API。"
        case let .badStatus(code, body): "图像生成失败（HTTP \(code)）：\(body.prefix(200))"
        case .emptyResponse: "图像生成接口没有返回图片。"
        case .undecodableImage: "无法解析返回的图片。"
        }
    }
}

/// 图像 API 配置。从 App 包里的 `Secrets.plist` 读取（该文件不提交到 Git）。
/// 参考 `Secrets.example.plist`。
struct ImageGenerationConfig: Sendable {
    var baseURL: URL
    /// 默认 OpenAI 兼容路径
    var path: String = "/v1/images/generations"
    var apiKey: String
    var model: String
    var size: String = "1024x1024"
    /// 有的模型不接受 response_format，留空则不发送这个字段
    var responseFormat: String? = "b64_json"

    var endpoint: URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(trimmed)
    }

    static func load(from bundle: Bundle = .main) -> ImageGenerationConfig? {
        guard let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return from(dictionary: plist)
    }

    static func from(dictionary plist: [String: Any]) -> ImageGenerationConfig? {
        func string(_ key: String) -> String? {
            guard let value = plist[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let base = string("IMAGE_API_BASE_URL"), let baseURL = URL(string: base),
              let key = string("IMAGE_API_KEY"), !key.hasPrefix("YOUR_"),
              let model = string("IMAGE_API_MODEL")
        else { return nil }

        var config = ImageGenerationConfig(baseURL: baseURL, apiKey: key, model: model)
        if let path = string("IMAGE_API_PATH") { config.path = path }
        if let size = string("IMAGE_API_SIZE") { config.size = size }
        if plist["IMAGE_API_RESPONSE_FORMAT"] != nil {
            config.responseFormat = string("IMAGE_API_RESPONSE_FORMAT")
        }
        return config
    }
}

/// OpenAI 兼容的 `/images/generations` 客户端。
/// 拿到 AMD API 文档后，如果格式不同，只需要改这个文件。
struct OpenAICompatibleImageGenerator: SpiritImageGenerating {
    let config: ImageGenerationConfig
    var session: URLSession = .shared

    func makeRequest(prompt: String) throws -> URLRequest {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": config.model,
            "prompt": prompt,
            "n": 1,
            "size": config.size,
        ]
        if let format = config.responseFormat { body["response_format"] = format }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func generateImage(prompt: String) async throws -> Data {
        let request = try makeRequest(prompt: prompt)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImageGenerationError.badStatus(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        switch try Self.parse(data) {
        case let .inline(imageData):
            return imageData
        case let .remote(url):
            let (imageData, _) = try await session.data(from: url)
            return imageData
        }
    }

    enum Payload: Equatable {
        case inline(Data)
        case remote(URL)
    }

    /// 解析 `{"data":[{"b64_json": "..."}]}` 或 `{"data":[{"url": "..."}]}`
    static func parse(_ data: Data) throws -> Payload {
        struct Response: Decodable {
            struct Item: Decodable {
                var b64_json: String?
                var url: String?
            }
            var data: [Item]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let item = decoded.data?.first else { throw ImageGenerationError.emptyResponse }
        if let base64 = item.b64_json {
            guard let imageData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
                throw ImageGenerationError.undecodableImage
            }
            return .inline(imageData)
        }
        if let string = item.url, let url = URL(string: string) {
            return .remote(url)
        }
        throw ImageGenerationError.emptyResponse
    }
}
