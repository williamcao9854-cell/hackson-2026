import SwiftData
import UIKit

/// 老的物灵（或别人传来的物灵）还没有立牌图：第一次用到时在后台抠出来，存回去。
@MainActor
enum FigureCache {
    private static var inFlight = Set<UUID>()

    static func ensureFigure(for spirit: Spirit, in context: ModelContext) {
        guard spirit.figureImageData == nil, let art = spirit.spiritImageData, !inFlight.contains(spirit.id) else { return }
        let id = spirit.id
        inFlight.insert(id)
        Task {
            let figure = await Task.detached(priority: .utility) { ImageProcessing.figure(fromArt: art) }.value
            inFlight.remove(id)
            guard let figure else { return }
            spirit.figureImageData = figure
            try? context.save()
        }
    }
}
