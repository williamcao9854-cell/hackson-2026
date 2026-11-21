import SwiftData
import SwiftUI

@main
struct WulingApp: App {
    var body: some Scene {
        WindowGroup {
            CollectionView()
                .tint(.vermilion)
        }
        .modelContainer(for: Spirit.self)
    }
}
