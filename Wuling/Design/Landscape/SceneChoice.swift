import SwiftUI

/// 天气：晴、雨、雪，以及「岚」——山间浮动的雾气。
enum Weather: String, CaseIterable, Sendable {
    case clear, rain, snow, mist

    var title: String {
        switch self {
        case .clear: "晴"
        case .rain: "雨"
        case .snow: "雪"
        case .mist: "岚"
        }
    }

    /// 没有指定天气时：冬天落雪，其余时候晴
    static func natural(for season: SolarTerm.Season) -> Weather {
        season == .winter ? .snow : .clear
    }
}

/// 园林此刻的景。默认（全为 nil）跟着真实的时辰、节气走；
/// 也可以单独指定时辰、季节、天气中的任意几项，演示时随时换到任何一天。
///
/// 存在 UserDefaults 里（`@AppStorage(SceneChoice.storageKey)`），首页与所有页面的淡山水背景共用。
struct SceneChoice: Equatable, Sendable, RawRepresentable {
    var phase: DayPhase?
    var season: SolarTerm.Season?
    var weather: Weather?

    static let storageKey = "wuling.scene"
    /// 演示：还没有送别、传出过物灵时，也在水上点几盏河灯、天上放几只鸿雁
    static let showcaseKey = "wuling.scene.showcase"

    static let auto = SceneChoice()

    init(phase: DayPhase? = nil, season: SolarTerm.Season? = nil, weather: Weather? = nil) {
        self.phase = phase
        self.season = season
        self.weather = weather
    }

    var isAuto: Bool { phase == nil && season == nil && weather == nil }

    /// 例如 "dusk.autumn.auto"；未指定的一项写作 auto
    var rawValue: String {
        [phase?.rawValue ?? "auto", season?.rawValue ?? "auto", weather?.rawValue ?? "auto"].joined(separator: ".")
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        phase = DayPhase(rawValue: parts[0])
        season = SolarTerm.Season(rawValue: parts[1])
        weather = Weather(rawValue: parts[2])
    }

    /// 手动选了时辰时，整个 App 跟着这幅景走：夜里是一纸墨色，其余时辰是和纸白。
    /// 跟随时辰时不干预，沿用系统的深浅色。
    var preferredColorScheme: ColorScheme? {
        guard let phase else { return nil }
        return phase == .night ? .dark : .light
    }

    /// 题签上写的节气：季节没被改动时写今天的；换了季节，就写那个季节里最有画面的一个节气。
    func solarTerm(for date: Date) -> SolarTerm {
        let today = SolarTerm(date: date)
        guard let season, season != today.season else { return today }
        switch season {
        case .spring: return SolarTerm(index: 1)    // 清明 · 桐始华
        case .summer: return SolarTerm(index: 8)    // 大暑 · 腐草为萤
        case .autumn: return SolarTerm(index: 13)   // 寒露 · 鸿雁来宾
        case .winter: return SolarTerm(index: 17)   // 大雪 · 鹖鴠不鸣
        }
    }
}

/// 换景面板里的「意境」：每一幅取自一句诗。
struct ScenePreset: Identifiable, Sendable {
    let title: String
    let verse: String
    let choice: SceneChoice
    var id: String { title }

    static let all: [ScenePreset] = [
        ScenePreset(title: "春江晨岚", verse: "春江潮水连海平",
                    choice: SceneChoice(phase: .dawn, season: .spring, weather: .mist)),
        ScenePreset(title: "斜风细雨", verse: "斜风细雨不须归",
                    choice: SceneChoice(phase: .day, season: .spring, weather: .rain)),
        ScenePreset(title: "荷风昼长", verse: "接天莲叶无穷碧",
                    choice: SceneChoice(phase: .day, season: .summer, weather: .clear)),
        ScenePreset(title: "夏夜流萤", verse: "清风半夜鸣蝉",
                    choice: SceneChoice(phase: .night, season: .summer, weather: .clear)),
        ScenePreset(title: "秋暮归雁", verse: "落霞与孤鹜齐飞",
                    choice: SceneChoice(phase: .dusk, season: .autumn, weather: .clear)),
        ScenePreset(title: "秋江月夜", verse: "月是故乡明",
                    choice: SceneChoice(phase: .night, season: .autumn, weather: .clear)),
        ScenePreset(title: "寒江独钓", verse: "独钓寒江雪",
                    choice: SceneChoice(phase: .day, season: .winter, weather: .snow)),
        ScenePreset(title: "江天暮雪", verse: "晚来天欲雪",
                    choice: SceneChoice(phase: .dusk, season: .winter, weather: .snow)),
    ]
}
