#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

/// 物灵的声音：仪式微音效，加上让手指"有回应"的小声音。
///
/// - 不带任何音频文件：每段声音第一次用到时，在后台合成为 16-bit PCM WAV，缓存在内存里。
/// - 用 `AVAudioPlayer(data:)` 播放，不用 `AVAudioEngine`，免得和相机、LiDAR 的会话抢音频。
///   每种声音留几个播放器轮流用，连点水面时不用每次重新解析。
/// - 音频会话是 ambient + mixWithOthers：手机静音时不出声，也不打断正在听的音乐。
/// - 换景面板里可以关掉音效；声音只是点缀，任何一步失败都静默跳过。
enum RitualSound {
    enum Cue: Hashable, Sendable {
        /// 卡片揭晓：五声音阶的一串风铃泛音，余韵慢慢散开（约 0.9 秒）
        case awaken
        /// 盖章：印章落在纸上，低沉温润的一声（约 0.12 秒）
        case stamp
        /// 化作河灯：一滴清润的水声，带一点余韵（约 0.7 秒）
        case lantern
        /// 点水面：一滴水落下，音高按左右位置排成五声音阶（0 最低 … 7 最高），连着点像在弹水
        case water(Int)
        /// 点山和天：毛笔在纸上点一下，闷闷的"嗒"
        case inkDot
        /// 轻点立牌：物灵蹦一下，"啵"（三种音高轮流）
        case hop(Int)
        /// 抠好的贴纸从照片上揭起来
        case peel
        /// 快门：轻轻的"咔嚓"
        case shutter
        /// 信笺展开：纸声
        case paper
        /// 拨动选项：很轻的一下木声
        case tick
        /// 送别的一刻：一阵风把它吹散成墨点，夹着几点细碎的光
        case scatter
        /// 长按送别时，声音和触感一起慢慢涨上来（约 2.6 秒，跟长按的时长对齐）
        case holdSwell

        static let waterNotes = 8
        static let hopVariants = 3

        static var allCases: [Cue] {
            [.awaken, .stamp, .lantern, .inkDot, .peel, .shutter, .paper, .tick, .scatter, .holdSwell]
                + (0..<waterNotes).map(Cue.water) + (0..<hopVariants).map(Cue.hop)
        }

        /// 播放音量，都偏轻
        var volume: Float {
            switch self {
            case .awaken: 0.4
            case .stamp: 0.55
            case .lantern: 0.42
            case .water: 0.42
            case .inkDot: 0.32
            case .hop: 0.38
            case .peel: 0.36
            case .shutter: 0.4
            case .paper: 0.34
            case .tick: 0.2
            case .scatter: 0.42
            case .holdSwell: 0.4
            }
        }
    }

    /// 换景面板里的「音效」开关
    static let enabledKey = "wuling.sound.effects"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// 首页、园林里随手点的那些声音：App 一打开就在后台备好
    static let everyday: [Cue] = (0..<Cue.waterNotes).map(Cue.water) + (0..<Cue.hopVariants).map(Cue.hop) + [.inkDot, .tick, .paper, .lantern]

    #if canImport(AVFoundation)
    /// 合成、建播放器、设置音频会话都在这条串行队列上做，不碰主线程
    private static let queue = DispatchQueue(label: "wuling.ritual-sound", qos: .userInitiated)
    // 下面几个只在 queue 上读写
    nonisolated(unsafe) private static var clips: [Cue: Data] = [:]
    nonisolated(unsafe) private static var pools: [Cue: [AVAudioPlayer]] = [:]
    nonisolated(unsafe) private static var holdPlayer: AVAudioPlayer?
    private static let poolSize = 4

    /// 提前在后台合成好（进入仪式页面时调用），真正要响的时候不用等
    static func prepare(_ cues: [Cue] = [.awaken, .stamp, .lantern, .scatter, .holdSwell]) {
        queue.async {
            AudioSessionSetup.ensure()
            for cue in cues { _ = clip(for: cue) }
        }
    }

    static func play(_ cue: Cue) {
        guard isEnabled else { return }
        let requested = DispatchTime.now().uptimeNanoseconds
        queue.async {
            AudioSessionSetup.ensure()
            // 万一第一次合成太慢，声音会和画面错开，这一次就不响了
            guard let player = player(for: cue),
                  DispatchTime.now().uptimeNanoseconds - requested < 350_000_000
            else { return }
            player.volume = cue.volume
            player.currentTime = 0
            player.play()
        }
    }

    /// 长按开始：蓄力的声音慢慢涨上来
    static func beginHold() {
        guard isEnabled else { return }
        queue.async {
            AudioSessionSetup.ensure()
            holdPlayer?.stop()
            guard let data = clip(for: .holdSwell),
                  let player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            else { return }
            player.volume = Cue.holdSwell.volume
            player.play()
            holdPlayer = player
        }
    }

    /// 长按结束：送出去了就顺势收住，中途松手就像一口气轻轻呼出去
    static func endHold(completed: Bool) {
        queue.async {
            guard let player = holdPlayer else { return }
            holdPlayer = nil
            let fade = completed ? 0.5 : 0.28
            player.setVolume(0, fadeDuration: fade)
            queue.asyncAfter(deadline: .now() + fade + 0.05) { player.stop() }
        }
    }

    private static func clip(for cue: Cue) -> Data? {
        if let data = clips[cue] { return data }
        let data = RitualSynth.wav(for: cue)
        clips[cue] = data
        return data
    }

    /// 从这种声音的播放器里找一个空着的；都在响就再建一个，满了就把最早那个拿来重新放
    private static func player(for cue: Cue) -> AVAudioPlayer? {
        var pool = pools[cue] ?? []
        if let idle = pool.first(where: { !$0.isPlaying }) { return idle }
        if pool.count < poolSize, let data = clip(for: cue),
           let player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) {
            player.prepareToPlay()
            pool.append(player)
            pools[cue] = pool
            return player
        }
        guard let oldest = pool.first else { return nil }
        oldest.stop()
        pools[cue] = Array(pool.dropFirst()) + [oldest]
        return oldest
    }
    #endif
}

#if canImport(AVFoundation)
/// 音效和背景音乐共用的音频会话：ambient + mixWithOthers
enum AudioSessionSetup {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var done = false

    static func ensure() {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        let session = AVAudioSession.sharedInstance()
        if (try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])) == nil {
            try? session.setCategory(.ambient)
        }
    }
}
#endif

/// 纯计算的声音合成，不依赖任何系统音频框架。
enum RitualSynth {
    static let sampleRate = 44_100

    static func wav(for cue: RitualSound.Cue) -> Data {
        encodeWAV(samples(for: cue))
    }

    static func samples(for cue: RitualSound.Cue) -> [Float] {
        var buffer = raw(for: cue)
        // 开头留半毫秒淡入：噪声起头的声音也不会"啪"一下
        let length = min(26, buffer.count)
        for i in 0..<length { buffer[i] *= Float(i) / Float(length) }
        return buffer
    }

    private static func raw(for cue: RitualSound.Cue) -> [Float] {
        switch cue {
        case .awaken: awaken()
        case .stamp: stamp()
        case .lantern: lantern()
        case let .water(note): water(note)
        case .inkDot: inkDot()
        case let .hop(variant): hop(variant)
        case .peel: peel()
        case .shutter: shutter()
        case .paper: paper()
        case .tick: tick()
        case .scatter: scatter()
        case .holdSwell: holdSwell()
        }
    }

    /// 水面上的五声音阶（D 宫：D E F♯ A B），和背景音乐同一组音，怎么点都不会"错音"
    static let waterScale: [Double] = [440.00, 493.88, 587.33, 659.25, 739.99, 880.00, 987.77, 1174.66]

    // MARK: - 仪式

    /// 宫、徵、羽三个音依次轻轻敲响，像风吹过一串铜铃；底下垫一个低八度的宫音，让它温一点。
    private static func awaken() -> [Float] {
        var buffer = [Float](repeating: 0, count: count(0.9))
        // G 宫调：G5（宫）、D6（徵）、E6（羽）
        let notes: [(start: Double, frequency: Double, gain: Double)] = [
            (0.00, 783.99, 1.0),
            (0.11, 1174.66, 0.72),
            (0.22, 1318.51, 0.58),
        ]
        for note in notes {
            // 风铃的泛音不是整数倍，高泛音衰减得更快，听起来更柔
            bell(&buffer, start: note.start, frequency: note.frequency, gain: note.gain, decay: 0.34,
                 partials: [(1.0, 1.0, 1.0), (1.0024, 0.45, 1.0), (2.0, 0.16, 0.5), (2.76, 0.07, 0.3), (5.40, 0.02, 0.15)])
        }
        // 低八度的宫音，若有若无
        bell(&buffer, start: 0.0, frequency: 392.0, gain: 0.22, decay: 0.42, partials: [(1.0, 1.0, 1.0)], attack: 0.03)
        fadeOut(&buffer, seconds: 0.18)
        normalize(&buffer, peak: 0.5)
        return buffer
    }

    /// 印章落纸："笃"的一声。音高从高往低落得很快，再加一点被纸吸收的轻擦声。
    /// 手机扬声器放不出 150Hz 以下，所以"低沉"落在 140～300Hz，配一个泛音让它在外放时也听得见。
    private static func stamp() -> [Float] {
        let n = count(0.12)
        var buffer = [Float](repeating: 0, count: n)
        var phase = 0.0, bodyPhase = 0.0
        var noise = NoiseSource(seed: 7)
        var lowpassed = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            let frequency = 138 + 150 * exp(-t / 0.011)
            phase += 2 * .pi * frequency / Double(sampleRate)
            bodyPhase += 2 * .pi * 318 / Double(sampleRate)
            let attack = min(1, t / 0.0015)
            let thump = (sin(phase) + 0.3 * sin(2 * phase)) * exp(-t / 0.03)
            let body = sin(bodyPhase) * 0.26 * exp(-t / 0.016)
            // 一阶低通的噪声，只留下闷闷的"沙"
            lowpassed += 0.09 * (noise.next() - lowpassed)
            let paper = lowpassed * 0.45 * exp(-t / 0.006)
            buffer[i] = Float(attack * (thump + body + paper))
        }
        fadeOut(&buffer, seconds: 0.03)
        normalize(&buffer, peak: 0.62)
        return buffer
    }

    /// 河灯入水：一滴水"叮"一下（音高快速上扬），水面上留一圈徵、宫的余韵，远处再落一滴更轻的。
    private static func lantern() -> [Float] {
        var buffer = [Float](repeating: 0, count: count(0.7))
        drop(&buffer, start: 0.0, from: 540, to: 1350, gain: 1.0)
        drop(&buffer, start: 0.34, from: 620, to: 1480, gain: 0.22)
        // 余韵：D6、G6，起得慢一点，像涟漪荡开
        bell(&buffer, start: 0.025, frequency: 1174.66, gain: 0.26, decay: 0.24, partials: [(1.0, 1.0, 1.0), (1.003, 0.5, 1.0)], attack: 0.02)
        bell(&buffer, start: 0.04, frequency: 1567.98, gain: 0.1, decay: 0.18, partials: [(1.0, 1.0, 1.0)], attack: 0.02)
        fadeOut(&buffer, seconds: 0.15)
        normalize(&buffer, peak: 0.48)
        return buffer
    }

    // MARK: - 指尖的小声音

    /// 一滴水落进池子："咕"地一下（气泡的音高往上跳），然后在这个音上留一点清亮的余韵
    private static func water(_ note: Int) -> [Float] {
        let frequency = waterScale[min(max(note, 0), waterScale.count - 1)]
        var buffer = [Float](repeating: 0, count: count(0.62))
        drop(&buffer, start: 0, from: frequency * 0.55, to: frequency * 1.2, gain: 0.55)
        bell(&buffer, start: 0.012, frequency: frequency, gain: 0.8, decay: 0.26,
             partials: [(1.0, 1.0, 1.0), (1.004, 0.35, 0.9), (2.0, 0.12, 0.4), (3.01, 0.05, 0.25)], attack: 0.006)
        // 落水的一点"噗"
        var noise = NoiseSource(seed: UInt64(31 + note))
        var low = 0.0
        for i in 0..<min(count(0.03), buffer.count) {
            let t = Double(i) / Double(sampleRate)
            low += 0.25 * (noise.next() - low)
            buffer[i] += Float(low * 0.35 * exp(-t / 0.006))
        }
        fadeOut(&buffer, seconds: 0.12)
        normalize(&buffer, peak: 0.5)
        return buffer
    }

    /// 毛笔在纸上一点：闷闷的一声"嗒"，没有音高
    private static func inkDot() -> [Float] {
        let n = count(0.12)
        var buffer = [Float](repeating: 0, count: n)
        var noise = NoiseSource(seed: 11)
        var low = 0.0, phase = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            low += 0.22 * (noise.next() - low)
            // 手机扬声器放不出 200Hz 以下，"闷"落在 280～400Hz
            phase += 2 * .pi * (280 + 120 * exp(-t / 0.01)) / Double(sampleRate)
            let attack = min(1, t / 0.002)
            buffer[i] = Float(attack * (low * 1.2 * exp(-t / 0.014) + sin(phase) * 0.55 * exp(-t / 0.03)))
        }
        fadeOut(&buffer, seconds: 0.03)
        normalize(&buffer, peak: 0.45)
        return buffer
    }

    /// 物灵蹦一下："啵"，音高往上一挑，尾巴带一点颤
    private static func hop(_ variant: Int) -> [Float] {
        let targets = [587.33, 739.99, 880.0]
        let target = targets[min(max(variant, 0), targets.count - 1)]
        let n = count(0.24)
        var buffer = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            let glide = min(1, t / 0.045)
            let eased = 1 - (1 - glide) * (1 - glide)
            let wobble = 1 + 0.012 * sin(2 * .pi * 11 * t) * min(1, t / 0.05)
            let frequency = target * (0.62 + 0.38 * eased) * wobble
            phase += 2 * .pi * frequency / Double(sampleRate)
            let attack = min(1, t / 0.004)
            buffer[i] = Float(attack * (sin(phase) + 0.18 * sin(2 * phase)) * exp(-t / 0.07))
        }
        fadeOut(&buffer, seconds: 0.05)
        normalize(&buffer, peak: 0.48)
        return buffer
    }

    /// 揭贴纸："嘶——"一下往上走，末尾轻轻"啵"地离开
    private static func peel() -> [Float] {
        let n = count(0.34)
        var buffer = [Float](repeating: 0, count: n)
        var noise = NoiseSource(seed: 23)
        var filter = Biquad()
        var crackle = 1.0
        let block = count(0.002)
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            if i % 32 == 0 {
                let progress = min(1, t / 0.27)
                filter.setBandpass(frequency: 700 * pow(5, progress), q: 1.3)
            }
            // 胶面一点点剥开：每 2 毫秒强弱不一
            if i % block == 0 { crackle = 0.45 + 0.55 * abs(noise.next()) }
            let envelope = min(1, t / 0.03) * (t < 0.26 ? 1 : exp(-(t - 0.26) / 0.015))
            buffer[i] = Float(filter.process(noise.next()) * envelope * crackle * 1.4)
        }
        bell(&buffer, start: 0.262, frequency: 920, gain: 0.25, decay: 0.018, partials: [(1.0, 1.0, 1.0)], attack: 0.002)
        fadeOut(&buffer, seconds: 0.04)
        normalize(&buffer, peak: 0.42)
        return buffer
    }

    /// 快门："咔——嚓"，两下轻轻的机械声
    private static func shutter() -> [Float] {
        var buffer = [Float](repeating: 0, count: count(0.17))
        click(&buffer, start: 0.0, ping: 2600, body: 330, gain: 1.0, seed: 41)
        click(&buffer, start: 0.065, ping: 2050, body: 280, gain: 0.75, seed: 43)
        fadeOut(&buffer, seconds: 0.03)
        normalize(&buffer, peak: 0.5)
        return buffer
    }

    /// 信笺展开：一阵沙沙的纸声，里面夹着几下脆响
    private static func paper() -> [Float] {
        let n = count(0.7)
        var buffer = [Float](repeating: 0, count: n)
        var noise = NoiseSource(seed: 59)
        var picker = NoiseSource(seed: 61)
        var filter = Biquad()
        filter.setBandpass(frequency: 2400, q: 0.9)
        // 十几粒长短不一的"沙"
        var grains: [(start: Double, decay: Double, gain: Double)] = []
        for _ in 0..<14 {
            grains.append((start: 0.55 * abs(picker.next()), decay: 0.012 + 0.03 * abs(picker.next()), gain: 0.4 + 0.6 * abs(picker.next())))
        }
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            var envelope = 0.28 * sin(.pi * min(1, t / 0.68))
            for grain in grains where t >= grain.start {
                envelope += grain.gain * exp(-(t - grain.start) / grain.decay)
            }
            buffer[i] = Float(filter.process(noise.next()) * envelope)
        }
        fadeOut(&buffer, seconds: 0.1)
        normalize(&buffer, peak: 0.38)
        return buffer
    }

    /// 拨动选项：很短的一下木声
    private static func tick() -> [Float] {
        var buffer = [Float](repeating: 0, count: count(0.05))
        bell(&buffer, start: 0, frequency: 2100, gain: 0.8, decay: 0.006, partials: [(1.0, 1.0, 1.0), (1.51, 0.3, 0.6)], attack: 0.0008)
        var noise = NoiseSource(seed: 71)
        for i in 0..<min(count(0.004), buffer.count) {
            let t = Double(i) / Double(sampleRate)
            buffer[i] += Float(noise.next() * 0.4 * exp(-t / 0.0008))
        }
        fadeOut(&buffer, seconds: 0.01)
        normalize(&buffer, peak: 0.35)
        return buffer
    }

    /// 送别：一阵风从低到高卷起再散开，风里有几点细碎的高音，像墨点被吹散时闪的光
    private static func scatter() -> [Float] {
        let n = count(1.8)
        var buffer = [Float](repeating: 0, count: n)
        var noise = NoiseSource(seed: 83)
        var filter = Biquad()
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            if i % 32 == 0 {
                // 风先往上卷（0.5 秒到最高），再慢慢落下来
                let center = t < 0.5 ? 350 * pow(4, t / 0.5) : 1400 * pow(600.0 / 1400, min(1, (t - 0.5) / 1.3))
                filter.setBandpass(frequency: center, q: 0.9)
            }
            let rise = smoothstep(min(1, t / 0.35))
            let envelope = t < 0.35 ? rise : exp(-(t - 0.35) / 0.55)
            buffer[i] = Float(filter.process(noise.next()) * envelope * 1.3)
        }
        // 碎光：D 宫的高音区，随机落下十几粒
        let sparkle: [Double] = [1174.66, 1318.51, 1479.98, 1760.0, 1975.53, 2349.32]
        var picker = NoiseSource(seed: 89)
        for k in 0..<16 {
            let start = 0.15 + 1.15 * abs(picker.next())
            let frequency = sparkle[Int(abs(picker.next()) * Double(sparkle.count)) % sparkle.count]
            let gain = 0.06 + 0.08 * abs(picker.next()) * (k < 8 ? 1 : 0.6)
            bell(&buffer, start: start, frequency: frequency, gain: gain, decay: 0.06 + 0.06 * abs(picker.next()),
                 partials: [(1.0, 1.0, 1.0), (2.0, 0.2, 0.5)], attack: 0.003)
        }
        fadeOut(&buffer, seconds: 0.3)
        normalize(&buffer, peak: 0.42)
        return buffer
    }

    /// 长按蓄力：一个宫、徵、宫的和音从无到有涨上来，颤动越来越快，像屏住的一口气
    private static func holdSwell() -> [Float] {
        let n = count(2.6)
        var buffer = [Float](repeating: 0, count: n)
        let chord: [(frequency: Double, gain: Double)] = [(293.66, 0.5), (440.0, 0.34), (587.33, 0.26)]
        var phases = [Double](repeating: 0, count: chord.count * 2)
        var noise = NoiseSource(seed: 97)
        var low = 0.0
        var tremoloPhase = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            let swell = pow(min(1, t / 2.4), 1.6)
            tremoloPhase += 2 * .pi * (3 + 6 * min(1, t / 2.4)) / Double(sampleRate)
            let tremolo = 1 - 0.18 * swell * (0.5 + 0.5 * sin(tremoloPhase))
            var value = 0.0
            for (k, voice) in chord.enumerated() {
                // 每个音两根略微走调的弦，拍出一点呼吸感；越到后面越亮
                for (j, detune) in [0.9975, 1.0025].enumerated() {
                    let index = k * 2 + j
                    phases[index] += 2 * .pi * voice.frequency * detune * (1 + 0.004 * swell) / Double(sampleRate)
                    value += voice.gain * (sin(phases[index]) + 0.12 * swell * sin(2 * phases[index]))
                }
            }
            // 气声：低通噪声，截止频率随蓄力升高
            let cutoff = 300 + 1700 * swell
            low += (1 - exp(-2 * .pi * cutoff / Double(sampleRate))) * (noise.next() - low)
            let attack = min(1, t / 0.03)
            buffer[i] = Float(attack * swell * (value * 0.5 * tremolo + low * 0.5))
        }
        fadeOut(&buffer, seconds: 0.15)
        normalize(&buffer, peak: 0.45)
        return buffer
    }

    // MARK: - 积木
    private static func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// 一下机械"咔"：高通的噪声 + 一个金属感的短鸣 + 一点机身的闷响
    private static func click(_ buffer: inout [Float], start: Double, ping: Double, body: Double, gain: Double, seed: UInt64) {
        let first = count(start)
        let length = min(count(0.06), buffer.count - first)
        guard length > 0 else { return }
        var noise = NoiseSource(seed: seed)
        var low = 0.0
        for i in 0..<length {
            let t = Double(i) / Double(sampleRate)
            let raw = noise.next()
            low += 0.2 * (raw - low)
            let snap = (raw - low) * exp(-t / 0.0025)
            let ring = sin(2 * .pi * ping * t) * 0.35 * exp(-t / 0.008)
            let thud = sin(2 * .pi * body * t) * 0.4 * exp(-t / 0.015)
            buffer[first + i] += Float(gain * (snap + ring + thud))
        }
    }

    /// 二阶带通（RBJ 公式），中心频率可以随时改
    private struct Biquad {
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        mutating func setBandpass(frequency: Double, q: Double) {
            let w0 = 2 * .pi * min(frequency, Double(sampleRate) * 0.45) / Double(sampleRate)
            let alpha = sin(w0) / (2 * q)
            let a0 = 1 + alpha
            b0 = alpha / a0
            b1 = 0
            b2 = -alpha / a0
            a1 = -2 * cos(w0) / a0
            a2 = (1 - alpha) / a0
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            return y
        }
    }


    private static func count(_ seconds: Double) -> Int { Int(seconds * Double(sampleRate)) }

    /// 一个带泛音的敲击音。partials：(频率倍数, 音量, 衰减时间倍数)
    private static func bell(_ buffer: inout [Float], start: Double, frequency: Double, gain: Double, decay: Double,
                             partials: [(Double, Double, Double)], attack: Double = 0.004) {
        let first = count(start)
        guard first < buffer.count else { return }
        for i in first..<buffer.count {
            let t = Double(i - first) / Double(sampleRate)
            let rise = t < attack ? 0.5 - 0.5 * cos(.pi * t / attack) : 1
            var value = 0.0
            for (ratio, amount, decayScale) in partials {
                value += amount * sin(2 * .pi * frequency * ratio * t) * exp(-t / (decay * decayScale))
            }
            buffer[i] += Float(gain * rise * value)
        }
    }

    /// 水滴：一个音高迅速上扬、很快消失的正弦
    private static func drop(_ buffer: inout [Float], start: Double, from: Double, to: Double, gain: Double) {
        let first = count(start)
        let length = min(count(0.12), buffer.count - first)
        guard length > 0 else { return }
        var phase = 0.0
        let sweep = 0.045
        for i in 0..<length {
            let t = Double(i) / Double(sampleRate)
            let progress = min(1, t / sweep)
            let frequency = from * pow(to / from, progress)
            phase += 2 * .pi * frequency / Double(sampleRate)
            let rise = min(1, t / 0.003)
            buffer[first + i] += Float(gain * rise * sin(phase) * exp(-t / 0.032))
        }
    }

    /// 结尾淡出，避免最后一下"咔"
    private static func fadeOut(_ buffer: inout [Float], seconds: Double) {
        let length = min(count(seconds), buffer.count)
        for k in 0..<length {
            let i = buffer.count - length + k
            buffer[i] *= Float(0.5 + 0.5 * cos(.pi * Double(k) / Double(length)))
        }
    }

    private static func normalize(_ buffer: inout [Float], peak: Float) {
        let maximum = buffer.reduce(Float(0)) { max($0, abs($1)) }
        guard maximum > 0 else { return }
        let scale = peak / maximum
        for i in buffer.indices { buffer[i] *= scale }
    }

    /// 可复现的白噪声（每次合成出来的"沙"声都一样）
    private struct NoiseSource {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: state >> 11) & 0xFFFFF) / Double(0xFFFFF) * 2 - 1
        }
    }

    // MARK: - WAV

    /// 单声道 16-bit PCM WAV
    static func encodeWAV(_ samples: [Float]) -> Data {
        let channels: UInt16 = 1, bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(samples.count) * UInt32(blockAlign)

        var data = Data(capacity: 44 + Int(dataSize))
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(channels); append(UInt32(sampleRate)); append(byteRate)
        append(blockAlign); append(bitsPerSample)
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        for sample in samples {
            append(Int16((max(-1, min(1, sample)) * Float(Int16.max)).rounded()))
        }
        return data
    }
}
