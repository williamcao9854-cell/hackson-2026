import SwiftData
import UIKit

/// 老的物灵（或别人传来的物灵）还没有立牌图：在后台串行逐个抠出来存回去。
/// 绝不并发触发多个 Vision 抠图，避免冷启动时抢占 CPU/GPU 导致界面卡死。
@MainActor
enum FigureCache {
    private static var attempted = Set<UUID>()
    private static var queue: [(spirit: Spirit, context: ModelContext)] = []
    private static var worker: Task<Void, Never>?

    static func ensureFigure(for spirit: Spirit, in context: ModelContext) {
        guard spirit.figureImageData == nil,
              spirit.spiritImageData != nil,
              !attempted.contains(spirit.id) else { return }
        attempted.insert(spirit.id)
        queue.append((spirit, context))
        startWorkerIfNeeded()
    }

    private static func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task {
            // 等首页首帧与转场完全稳定后再开始后台抠图
            try? await Task.sleep(for: .milliseconds(700))
            while !queue.isEmpty {
                let job = queue.removeFirst()
                guard job.spirit.figureImageData == nil,
                      let art = job.spirit.spiritImageData else { continue }
                let figure = await Task.detached(priority: .background) {
                    ImageProcessing.figure(fromArt: art)
                }.value
                if let figure {
                    job.spirit.figureImageData = figure
                    try? job.context.save()
                }
                // 每个之间喘一口气，不堵主线程和渲染管线
                try? await Task.sleep(for: .milliseconds(150))
            }
            worker = nil
        }
    }
}
