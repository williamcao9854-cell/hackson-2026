import SwiftUI
import UIKit

// MARK: - 颜色：「和纸与朱印」
//
// 全 App 只有一种强调色：朱红。只用在印章和主按钮上。

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        }
    }
}

extension Color {
    /// 背景：和纸白 / 墨夜
    static let wlPaper = Color(uiColor: .dynamic(light: 0xF4F0E8, dark: 0x15130F))
    /// 卡片
    static let wlCard = Color(uiColor: .dynamic(light: 0xFBF8F2, dark: 0x1F1C17))
    /// 主文字
    static let wlInk = Color(uiColor: .dynamic(light: 0x1C1A17, dark: 0xEDE8DF))
    /// 次要文字
    static let wlInkSecondary = Color(uiColor: .dynamic(light: 0x7A746B, dark: 0x9A9388))
    /// 朱红，唯一强调色
    static let wlVermilion = Color(uiColor: .dynamic(light: 0xC8442F, dark: 0xE0583F))
    /// 分隔线
    static let wlHairline = Color(uiColor: .dynamic(light: 0x1C1A17, dark: 0xEDE8DF, lightAlpha: 0.1, darkAlpha: 0.12))

    init(rgb: RGB) {
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

/// 让 `.foregroundStyle(.ink)`、`Color.ink`、`.tint(.vermilion)` 都能直接使用
extension ShapeStyle where Self == Color {
    static var paper: Color { Color.wlPaper }
    static var card: Color { Color.wlCard }
    static var ink: Color { Color.wlInk }
    static var inkSecondary: Color { Color.wlInkSecondary }
    static var vermilion: Color { Color.wlVermilion }
    static var hairline: Color { Color.wlHairline }
}

// MARK: - 字体
//
// 中文使用系统苹方；西文与数字的标题使用 New York（系统衬线体），编号与日期用等宽数字。

extension Font {
    /// 页面大标题
    static let wlTitle = Font.system(size: 34, weight: .semibold, design: .serif)
    /// 物灵名字（竖排）
    static func wlSpiritName(_ size: CGFloat = 40) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    /// 小节标题
    static let wlHeadline = Font.system(size: 17, weight: .semibold)
    /// 正文
    static let wlBody = Font.system(size: 16, weight: .regular)
    /// 引用（性格描述）
    static let wlQuote = Font.system(size: 18, weight: .regular, design: .serif)
    /// 编号、日期等细节
    static let wlCaption = Font.system(size: 12, weight: .medium, design: .serif)
    /// 全大写的英文小标签，例如 TSUKUMOGAMI
    static let wlEyebrow = Font.system(size: 11, weight: .semibold, design: .serif)
}

extension Text {
    /// 英文小标签：加宽字距
    func eyebrow() -> some View {
        self.font(.wlEyebrow)
            .tracking(2.2)
            .textCase(.uppercase)
            .foregroundStyle(.inkSecondary)
    }
}

// MARK: - 尺寸

enum Metrics {
    static let gutter: CGFloat = 20
    static let cardRadius: CGFloat = 22
    static let smallRadius: CGFloat = 14
}

// MARK: - 日期与编号

enum WLFormat {
    static func date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: date)
    }

    static func serial(_ n: Int) -> String {
        String(format: "No. %03d", n)
    }
}

// MARK: - 动画

extension Animation {
    /// 安静、没有回弹的入场
    static let wlCalm = Animation.smooth(duration: 0.6)
    /// 轻微回弹，用于"拎起"
    static let wlLift = Animation.spring(response: 0.55, dampingFraction: 0.68)
}
