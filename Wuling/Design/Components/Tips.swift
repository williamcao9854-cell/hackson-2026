import SwiftUI
import TipKit

/// 用 Apple 原生的 TipKit 在关键位置轻轻提示一次，看过就不再出现。

struct GardenTip: Tip {
    var title: Text { Text("这是你的园林") }
    var message: Text? { Text("同住的物灵站在岸边，点一下可以看它；倾斜手机，山水会跟着动。") }
    var image: Image? { Image(systemName: "leaf") }
}

struct RenameTip: Tip {
    /// 名字写完、卡片完全展开后才出现，不打断揭晓动画
    @Parameter static var isReady: Bool = false
    var rules: [Rule] { #Rule(Self.$isReady) { $0 == true } }

    var title: Text { Text("轻点名字可以改名") }
    var message: Text? { Text("名字多长都可以。") }
    var image: Image? { Image(systemName: "pencil") }
}

struct StandeeTip: Tip {
    var title: Text { Text("转一转它") }
    var message: Text? { Text("左右拖动立牌，或者倾斜手机。轻点它会跳一下。") }
    var image: Image? { Image(systemName: "rotate.3d") }
}
