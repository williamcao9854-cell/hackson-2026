import SwiftData
import SwiftUI
import TipKit

@main
struct WulingApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: Spirit.self)
        try? Tips.configure([.displayFrequency(.immediate)])
        // 自动截图（tools/mac_build_report.sh）时带上 -demo-data，让图鉴里有内容可看
        if ProcessInfo.processInfo.arguments.contains("-demo-data") {
            UserDefaults.standard.set(true, forKey: "wuling.onboarded")
            PreviewData.seedIfEmpty(container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            CollectionView()
                .tint(.vermilion)
        }
        .modelContainer(container)
    }
}
