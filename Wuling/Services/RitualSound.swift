#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

/// 仪式微音效：物灵醒来、印章落纸、化作河灯。
///
/// - 不带任何音频文件：第一次用到时，在后台把三段极短的声音合成为 16-bit PCM WAV，缓存在内存里。
/// - 用 `AVAudioPlayer(data:)` 播放，不用 `AVAudioEngine`，免得和相机、LiDAR 的会话抢音频。
/// - 音频会话是 ambient + mixWithOthers：手机静音时不出声，也不打断正在听的音乐。
/// - 声音只是点缀，任何一步失败都静默跳过。
enum RitualSound {
    enum Cue: CaseIterable, Sendable {
        /// 卡片揭晓：五声音阶的一串风铃泛音，余韵慢慢散开（约 0.9 秒）
        case awaken
        /// 盖章：印章落在纸上，低沉温润的一声（约 0.12 秒）
        case stamp
        /// 化作河灯：一滴清润的水声，带一点余韵（约 0.7 秒）
        case lantern

        /// 播放音量，都偏轻
        var volume: Float {
            switch self {
            case .awaken: 0.4
            case .stamp: 0.55
            case .lantern: 0.42
            }
        }
    }

    #if canImport(AVFoundation)
    /// 合成、建播放器、设置音频会话都在这条串行队列上做，不碰主线程
    private static let queue = DispatchQueue(label: "wuling.ritual-sound", qos: .userInitiated)
    // 下面三个只在 queue 上读写
    nonisolated(unsafe) private static var clips: [Cue: Data] = [:]
    nonisolated(unsafe) private static var players: [AVAudioPlayer] = []
    nonisolated(unsafe) private static var sessionReady = false

    /// 提前在后台合成好（进入仪式页面时调用），真正要响的时候不用等
    static func prepare() {
        queue.async { warmUp() }
    }

    static func play(_ cue: Cue) {
        let requested = DispatchTime.now().uptimeNanoseconds
        queue.async {
            warmUp()
            // 万一第一次合成太慢，声音会和画面错开，这一次就不响了
            guard DispatchTime.now().uptimeNanoseconds - requested < 350_000_000,
                  let data = clips[cue],
                  let player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            else { return }
            player.volume = cue.volume
            players.removeAll { !$0.isPlaying }
            players.append(player) // 播完之前要有人拿着它
            player.play()
        }
    }

    private static func warmUp() {
        if clips.isEmpty {
            for cue in Cue.allCases {
                clips[cue] = RitualSynth.wav(for: cue)
            }
        }
        if !sessionReady {
            sessionReady = true
            let session = AVAudioSession.sharedInstance()
            if (try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])) == nil {
                try? session.setCategory(.ambient)
            }
        }
    }
    #endif
}

/// 纯计算的声音合成，不依赖任何系统音频框架。
enum RitualSynth {
    static let sampleRate = 44_100

    static func wav(for cue: RitualSound.Cue) -> Data {
        encodeWAV(samples(for: cue))
    }

    static func samples(for cue: RitualSound.Cue) -> [Float] {
        switch cue {
        case .awaken: awaken()
        case .stamp: stamp()
        case .lantern: lantern()
        }
    }

    // MARK: - 三段声音

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

    // MARK: - 积木

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
