import CoreTransferable
import SwiftData
import UIKit
import UniformTypeIdentifiers

extension UTType {
    /// `.wuling` 物灵文件，在 Wuling-Info.plist 中声明
    static let wulingSpirit = UTType(exportedAs: SpiritCapsule.typeIdentifier)
}

/// 让物灵胶囊可以通过 ShareLink 隔空投送、发消息、存到文件。
extension SpiritCapsule: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .wulingSpirit) { capsule in
            SentTransferredFile(try capsule.writeTemporaryFile())
        } importing: { received in
            try SpiritCapsule.decode(Data(contentsOf: received.file))
        }
    }

    /// 写成一个临时的 `.wuling` 文件，用于分享
    func writeTemporaryFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(suggestedFileName)
        try encoded().write(to: url, options: .atomic)
        return url
    }

    /// 传出前压缩图片：插画转 JPEG、长边 1024；贴纸保留透明、长边 640。
    /// 一个物灵文件从好几 MB 降到几百 KB，隔空投送几乎是瞬间完成。
    func compressedForTransfer() -> SpiritCapsule {
        var copy = self
        if let data = spiritImage, let image = UIImage(data: data) {
            copy.spiritImage = ImageCompression.resized(image, maxDimension: 1024).jpegData(compressionQuality: 0.82) ?? data
        }
        if let data = stickerImage, let image = UIImage(data: data) {
            copy.stickerImage = ImageCompression.resized(image, maxDimension: 640).pngData() ?? data
        }
        return copy
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

        let spirit = Spirit(capsule: capsule, serial: Spirit.nextSerial(in: context), chapters: chapters, receivedAt: now)
        context.insert(spirit)
        try? context.save()
        return spirit
    }
}

enum ImageCompression {
    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return image }
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
