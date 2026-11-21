import SwiftUI
import UIKit

/// 系统分享面板（隔空投送、微信、信息、存到文件……）。
/// 和 ShareLink 不同，它能告诉我们"是否真的发出去了"，传灵靠它自动标记"已传出"。
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
