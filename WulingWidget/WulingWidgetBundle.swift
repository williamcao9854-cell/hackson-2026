import SwiftUI
import WidgetKit

/// 物灵的小组件：桌面上的「园林」，锁屏上的「节气」。
///
/// 演示为主：免费开发者账户用不了 App Groups，小组件读不到 App 里的物灵，
/// 内容只靠今天的日期算出来（节气、物候、农历、示例物灵青履君的来信）；
/// 「放灯」按钮记在小组件自己的存储里。
@main
struct WulingWidgetBundle: WidgetBundle {
    var body: some Widget {
        GardenWidget()
        TermWidget()
    }
}
