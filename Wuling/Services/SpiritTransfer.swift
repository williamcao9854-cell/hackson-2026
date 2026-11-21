import CoreTransferable
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    /// `.wuling` 物灵文件，在 Wuling-Info.plist 中声明
    static let wulingSpirit = UTType(exportedAs: SpiritCapsule.typeIdentifier)
}

/// 让物灵胶囊可以通过 ShareLink 隔空投送、发消息、存到文件。
extension SpiritCapsule: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .wulingSpirit) { capsule in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(capsule.suggestedFileName)
            try capsule.encoded().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        } importing: { received in
            try SpiritCapsule.decode(Data(contentsOf: received.file))
        }
    }

    /// 读取从隔空投送、文件 App 打开的 `.wuling` 文件
    static func read(from url: URL) throws -> SpiritCapsule {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw RelayError.unreadable }
        return try decode(data)
    }
}

/// 收下一个物灵。
enum RelayInbox {
    /// 这个物灵以前在我这里待过吗？（传了一圈又回来了）
    @MainActor
    static func existing(lineage: UUID, in context: ModelContext) -> Spirit? {
        let id = lineage
        var descriptor = FetchDescriptor<Spirit>(predicate: #Predicate { $0.lineageID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    @discardableResult
    static func receive(_ capsule: SpiritCapsule, mySeal: String, in context: ModelContext) -> Spirit {
        let now = Date.now
        let chapters = RelayLogic.chaptersForReceiving(capsule, mySeal: mySeal, now: now)

        if let returning = existing(lineage: capsule.lineageID, in: context) {
            // 它回来了：更新故事，重新"同住"
            returning.chapters = chapters
            returning.spiritImageData = capsule.spiritImage ?? returning.spiritImageData
            returning.releasedAt = nil
            returning.departureRaw = ""
            returning.receivedAt = now
            try? context.save()
            return returning
        }

        let count = (try? context.fetchCount(FetchDescriptor<Spirit>())) ?? 0
        let spirit = Spirit(capsule: capsule, serial: count + 1, chapters: chapters, receivedAt: now)
        context.insert(spirit)
        try? context.save()
        return spirit
    }
}
