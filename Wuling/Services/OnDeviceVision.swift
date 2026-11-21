#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 用 Apple 端侧大模型"看图识物"（iOS 27 起，Foundation Models 支持图片输入）。
///
/// 比分类模型强得多：不受 ImageNet 1000 类的限制，能直接说出"蓝牙耳机""毛绒兔子""外婆的搪瓷杯"，
/// 还能描述它的颜色、形状和磨损，这段描述会写进生成提示词，让物灵更像原物。
/// 全程在手机上完成，照片不上传。不支持的系统或机型返回 nil，自动退回分类模型。
enum OnDeviceVision {
    struct Seen: Sendable {
        var kind: ObjectKind
        /// 给插画师的英文外观描述，例如 "a round white enamel mug with a chipped blue rim"
        var appearance: String
    }

    #if canImport(CoreGraphics)
    static func identify(_ image: CGImage) async -> Seen? {
        // Attachment（图片输入）只在 iOS 27 SDK（Xcode 27，Swift 6.4）中存在
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let reply = await withTimeout(seconds: 12) { try await ask(image) }
            return reply.flatMap(parse)
        }
        #endif
        return nil
    }
    #endif

    #if canImport(FoundationModels) && canImport(CoreGraphics) && compiler(>=6.4)
    @available(iOS 27.0, *)
    private static func ask(_ image: CGImage) async throws -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: """
        You identify everyday personal belongings in photos. The background has been removed.
        Answer in exactly four lines, nothing else:
        中文名: <the common Chinese name, 2-6 characters, e.g. 马克杯、跑鞋、蓝牙耳机、毛绒兔子>
        english: <the same object in plain English, 1-4 words>
        family: <one of: \(ObjectFamily.allCases.map(\.rawValue).joined(separator: ", "))>
        look: <an English description of its appearance for an illustrator: shape, colors, patterns, visible wear; under 25 words>
        """)
        let response = try await session.respond {
            "What is this object? Follow the four-line format."
            Attachment(image)
        }
        return response.content
    }
    #endif

    /// 解析四行回答。容错：大小写、全角冒号、多余空白、行序都不严格要求。
    static func parse(_ reply: String) -> Seen? {
        var fields: [String: String] = [:]
        for rawLine in reply.split(whereSeparator: \.isNewline) {
            let line = rawLine.replacingOccurrences(of: "：", with: ":")
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”<>*"))
            guard !value.isEmpty else { continue }
            fields[key] = value
        }
        guard let chinese = fields["中文名"] ?? fields["chinese"] ?? fields["name"], !chinese.isEmpty else { return nil }

        // 目录里认识这个中文名，就用目录里规范的英文名和大类；否则采用模型给的
        let catalogKind = ObjectCatalog.kind(matchingChinese: chinese)
        let english = fields["english"] ?? catalogKind?.english ?? ObjectKind.unknown.english
        let family = fields["family"].flatMap { ObjectFamily(rawValue: $0.lowercased()) } ?? catalogKind?.family ?? .other
        let look = String((fields["look"] ?? "").prefix(220))
        return Seen(kind: ObjectKind(chinese: String(chinese.prefix(12)), english: english, family: family), appearance: look)
    }

    private static func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
