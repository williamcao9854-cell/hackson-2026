import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 给物灵起名字、写性格。
///
/// 支持 Apple 智能的设备上，用 **Foundation Models**（Apple 设备端大模型）结合用户写的记忆来写，
/// 记忆文字只在本机使用。其他设备上退回模板起名，体验不打折。
enum OnDeviceSpiritWriter {
    static func write(for seed: SpiritSeed) async -> SpiritProfile {
        let template = TemplateSpiritWriter.write(for: seed)
        #if canImport(FoundationModels)
        if let generated = try? await withTimeout(seconds: 8, operation: { try await generate(for: seed, fallback: template) }) {
            return generated
        }
        #endif
        return template
    }

    #if canImport(FoundationModels)
    @Generable
    struct GeneratedProfile {
        @Guide(description: "物灵的名字。正好三个汉字：第一个字是颜色字，第二个字和物品有关，第三个字从「丸、子、君、郎、姬」中选。例如：青履丸、墨芯君、栗偶子")
        var name: String

        @Guide(description: "对这个物灵性格的温柔描述，用第三人称“它”，一到两句话，总共不超过 40 个字。可以化用主人写下的记忆，但不要照抄。")
        var personality: String
    }

    private static func generate(for seed: SpiritSeed, fallback: SpiritProfile) async throws -> SpiritProfile? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let session = LanguageModelSession(instructions: """
        你是一位温柔的日本民间故事讲述者。日本传说中，器物被人珍惜久了，就会生出灵魂，叫作「付丧神」。
        你的任务是为一件物品的物灵起名字，并描述它的性格。语气安静、温暖、有一点俏皮，不煽情，不说教。
        """)

        var prompt = """
        物品：\(seed.displayName)
        颜色：\(seed.color.name)（名字的第一个字请用「\(seed.color.character)」）
        陪伴主人的时间：\(seed.companionship.title)
        """
        let memory = seed.memory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !memory.isEmpty {
            prompt += "\n主人写下的记忆：\(memory)"
        }

        let response = try await session.respond(to: prompt, generating: GeneratedProfile.self)
        let generated = response.content
        let name = generated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let personality = generated.personality.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...4).contains(name.count), !personality.isEmpty else { return nil }

        var profile = fallback
        profile.name = name
        profile.personality = personality
        return profile
    }
    #endif

    /// 超时就放弃，退回模板，不让用户久等。
    private static func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T?) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
