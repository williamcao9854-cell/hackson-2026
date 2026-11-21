import SwiftData
import SwiftUI
import TipKit

@main
struct WulingApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: Spirit.self)
        // 自动截图（tools/mac_build_report.sh）时带上 -demo-data，让图鉴里有内容可看
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-demo-data") {
            UserDefaults.standard.set(true, forKey: "wuling.onboarded")
            PreviewData.seedIfEmpty(container.mainContext)
        }
        // 演示 / 截图时直接指定一幅景，例如 -scene night.summer.clear（任一项写 auto 表示跟随）
        if let index = arguments.firstIndex(of: "-scene"), index + 1 < arguments.count,
           let choice = SceneChoice(rawValue: arguments[index + 1]) {
            UserDefaults.standard.set(choice.rawValue, forKey: SceneChoice.storageKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            CollectionView()
                .tint(.vermilion)
                .task {
                    try? Tips.configure([.displayFrequency(.immediate)])
                }
        }
        .modelContainer(container)
    }
}
