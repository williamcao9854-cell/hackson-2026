#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

/// 园林的背景音乐：古琴般的拨弦、泛音、远处的水声（`tools/compose_ambient.py` 合成，见 Resources/Sounds）。
///
/// - 白天、夜里各一段；园林下雨时再叠一层雨声。换景时交叉淡入淡出。
/// - 仪式时（醒来、送别、来信）先让一让：压低几秒，留出风铃和水声。
/// - 和音效共用 ambient + mixWithOthers 的音频会话：手机静音时不出声；
///   别的 App 正在放音乐时（`secondaryAudioShouldBeSilencedHint`）不放，免得两段音乐叠在一起。
/// - 换景面板里可以关掉。任何一步失败都静默跳过。
enum AmbientMusic {
    enum Mood: String, Sendable {
        case day, night
    }

    /// 换景面板里的「背景音乐」开关
    static let enabledKey = "wuling.sound.music"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    #if canImport(AVFoundation)
    private static let queue = DispatchQueue(label: "wuling.ambient-music", qos: .utility)
    // 下面几个只在 queue 上读写
    nonisolated(unsafe) private static var music: AVAudioPlayer?
    nonisolated(unsafe) private static var musicMood: Mood?
    nonisolated(unsafe) private static var rainPlayer: AVAudioPlayer?
    nonisolated(unsafe) private static var wanted: (mood: Mood, rain: Bool)?
    nonisolated(unsafe) private static var duckCount = 0
    nonisolated(unsafe) private static var active = true
    nonisolated(unsafe) private static var observing = false

    private static let musicVolume: Float = 0.34
    private static let rainVolume: Float = 0.2
    /// 让一让时压到原来的几成
    private static let duckScale: Float = 0.28

    /// 首页根据此刻的景调用：白天、夜里换曲子，下雨时叠一层雨声
    static func update(mood: Mood, rain: Bool) {
        queue.async {
            observeOtherAudio()
            wanted = (mood, rain)
            apply(fade: 2.5)
        }
    }

    /// 开关变了
    static func refresh() {
        queue.async { apply(fade: 1.2) }
    }

    /// App 切到后台、回到前台
    static func setActive(_ isActive: Bool) {
        queue.async {
            active = isActive
            apply(fade: isActive ? 1.5 : 0.3)
        }
    }

    /// 仪式时让一让：压低一会儿，再慢慢回来
    static func duck(for seconds: Double) {
        queue.async {
            duckCount += 1
            applyVolumes(fade: 0.5)
            queue.asyncAfter(deadline: .now() + seconds) {
                duckCount = max(0, duckCount - 1)
                applyVolumes(fade: 2.0)
            }
        }
    }

    private static var shouldPlay: Bool {
        isEnabled && active && !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    }

    private static func apply(fade: Double) {
        guard let wanted, shouldPlay else {
            retire(music, fade: fade)
            retire(rainPlayer, fade: fade)
            music = nil
            musicMood = nil
            rainPlayer = nil
            return
        }
        AudioSessionSetup.ensure()

        if musicMood != wanted.mood || music == nil {
            retire(music, fade: fade)
            music = makeLoop(named: "ambient-\(wanted.mood.rawValue)")
            musicMood = wanted.mood
            music?.volume = 0
            music?.play()
        } else if let music, !music.isPlaying {
            music.play()
        }

        if wanted.rain {
            if rainPlayer == nil {
                rainPlayer = makeLoop(named: "ambient-rain")
                rainPlayer?.volume = 0
            }
            if let rainPlayer, !rainPlayer.isPlaying { rainPlayer.play() }
        } else {
            retire(rainPlayer, fade: fade)
            rainPlayer = nil
        }
        applyVolumes(fade: fade)
    }

    private static func applyVolumes(fade: Double) {
        let scale: Float = duckCount > 0 ? duckScale : 1
        music?.setVolume(musicVolume * scale, fadeDuration: fade)
        rainPlayer?.setVolume(rainVolume * scale, fadeDuration: fade)
    }

    /// 淡出后停掉（期间如果又被拿回来用，就不停）
    private static func retire(_ player: AVAudioPlayer?, fade: Double) {
        guard let player else { return }
        player.setVolume(0, fadeDuration: fade)
        queue.asyncAfter(deadline: .now() + fade + 0.1) {
            if player !== music && player !== rainPlayer { player.stop() }
        }
    }

    private static func makeLoop(named name: String) -> AVAudioPlayer? {
        let url = Bundle.main.url(forResource: name, withExtension: "wav")
            ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = -1
        player.prepareToPlay()
        return player
    }

    /// 别的 App 开始、停止放音乐时，跟着让开或回来
    private static func observeOtherAudio() {
        guard !observing else { return }
        observing = true
        _ = NotificationCenter.default.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification,
                                               object: nil, queue: nil) { _ in
            refresh()
        }
    }
    #else
    static func update(mood: Mood, rain: Bool) {}
    static func refresh() {}
    static func setActive(_ isActive: Bool) {}
    static func duck(for seconds: Double) {}
    #endif
}
