import SwiftUI

/// ⑥ 送别仪式：道一声谢 → 长按印章 → 原物被风吹散成墨点，落到水面汇成一盏河灯 → 朱印盖下。
///
/// 墨点是 GPU 粒子（InkDissolveView），水面是 Metal 着色器（inkWater）：
/// 波纹来自真实的波动方程（RippleField），水面倒映着上面的物件、物灵插画和河灯。轻点水面也会荡开涟漪。
///
/// 在「遇见」流程的最后使用，也可以从图鉴里给"同住"的物灵补办送别。
struct FarewellView: View {
    var sticker: UIImage?
    var spiritImageData: Data?
    var spiritName: String
    var palette: [RGB]
    var suggestion: String
    var onReleased: (String) -> Void
    var onFinish: () -> Void
    /// 从详情页打开时提供，左上角显示关闭按钮（送别开始后隐藏）
    var onCancel: (() -> Void)? = nil

    private enum Phase { case writing, dissolving, sealed }

    @State private var note = ""
    @State private var phase: Phase = .writing
    @State private var dissolveStart = Date.now
    @State private var stampLanded = false
    /// 墨点收拢，河灯落在水面上
    @State private var lanternLanded = false
    /// 河灯开始顺水漂走的时刻
    @State private var driftStart: Date?
    @State private var ripples = RippleField()
    @State private var stageWidth: CGFloat = 390
    @State private var waterTouches = 0
    @FocusState private var noteFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private static let stageHeight: CGFloat = 300
    private static let waterDepth: CGFloat = 66
    private static let stickerSize: CGFloat = 200
    private static let artSize: CGFloat = 220
    private static let driftDuration: Double = 7

    /// 有贴纸、设备支持 Metal 时用墨点粒子；否则退回原来的光点
    private var usesInk: Bool { sticker != nil && InkDissolveView.isAvailable }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("送别").eyebrow()
                Text(phase == .sealed ? "它会一直记得你" : "向\(spiritName)道别")
                    .font(.system(size: 26, weight: .semibold))
                    .contentTransition(.opacity)
            }
            .padding(.top, 64)

            Spacer(minLength: 16)

            stage
                .frame(height: 300)

            Spacer(minLength: 16)

            bottom
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 16)
        }
        .animation(.wlCalm, value: phase)
        .sensoryFeedback(.impact(weight: .heavy), trigger: stampLanded)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: lanternLanded)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.4), trigger: waterTouches)
        .onAppear { RitualSound.prepare() }
        .overlay(alignment: .topLeading) {
            if let onCancel, phase == .writing {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(.ink)
                .padding(.leading, Metrics.gutter)
                .padding(.top, 8)
                .accessibilityLabel("先不送别")
            }
        }
    }

    // MARK: - 舞台：原物 → 墨点 → 落在水面汇成河灯；水面倒映着上面的一切

    private var stage: some View {
        GeometryReader { geo in
            let size = geo.size
            let waterY = size.height - Self.waterDepth
            let center = CGPoint(x: size.width / 2, y: waterY / 2)
            let lanternHome = CGPoint(x: size.width / 2 + 34, y: waterY - 7)

            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let lantern = lanternState(home: lanternHome, at: timeline.date)
                    let heights = waterHeights(at: time, lantern: lantern, width: size.width)
                    scene(size: size, center: center, lantern: lantern)
                        .layerEffect(
                            ShaderLibrary.inkWater(
                                .float2(size),
                                .float(Float(waterY)),
                                .float(Float(time.truncatingRemainder(dividingBy: 3600))),
                                .floatArray(heights),
                                .float(Float(ripples.columns)),
                                .color(.ink)
                            ),
                            maxSampleOffset: CGSize(width: 16, height: Self.waterDepth * 2 + 16)
                        )
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    touchWater(at: location, size: size, waterY: waterY)
                }

                if phase != .writing {
                    if usesInk, let sticker {
                        InkDissolveView(image: sticker, imageRect: stickerRect(center: center), waterY: waterY,
                                        lanternPoint: CGPoint(x: lanternHome.x, y: lanternHome.y + 3),
                                        startDate: dissolveStart, isDark: colorScheme == .dark)
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                    } else {
                        DissolveParticles(colors: particleColors, startDate: dissolveStart)
                            .frame(width: 320, height: 360)
                            .position(center)
                            .allowsHitTesting(false)
                    }
                }
            }
            .onAppear { stageWidth = size.width }
            .onChange(of: size.width) { _, width in stageWidth = width }
        }
        .frame(height: Self.stageHeight)
    }

    /// 水线以上的一切（物件、物灵插画、朱印、河灯），都会被水面倒映出来
    private func scene(size: CGSize, center: CGPoint, lantern: (point: CGPoint, opacity: Double)?) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // 物灵插画，送别完成后浮现
            SpiritArtView(data: spiritImageData)
                .frame(width: Self.artSize, height: Self.artSize)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    SealStamp(text: "已送别", size: 64)
                        .scaleEffect(stampLanded ? 1 : 1.8)
                        .opacity(stampLanded ? 1 : 0)
                        .offset(x: 12, y: 12)
                }
                .opacity(phase == .sealed ? 1 : 0)
                .scaleEffect(phase == .sealed ? 1 : 0.9)
                .position(center)

            // 原物贴纸。用墨点时，墨点一开始就拼成原图，贴纸立刻让位；没有 Metal 时还是慢慢化开
            if let sticker {
                StickerView(image: sticker, lifted: phase == .writing)
                    .frame(width: Self.stickerSize, height: Self.stickerSize)
                    .opacity(phase == .writing ? 1 : 0)
                    .blur(radius: phase == .writing || usesInk ? 0 : 16)
                    .scaleEffect(phase == .writing || usesInk ? 1 : 1.12)
                    .animation(usesInk ? .easeOut(duration: 0.12) : .easeOut(duration: 1.3), value: phase)
                    .position(center)
            }

            // 墨点汇成的河灯：落在水面上，过一会儿顺水漂走
            if let lantern {
                LanternGlyph()
                    .frame(width: 34, height: 34)
                    .position(lantern.point)
                    .opacity(lantern.opacity)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// 河灯此刻在哪：落水后先停一会儿，再顺水往右漂，轻轻起伏，最后淡出
    private func lanternState(home: CGPoint, at date: Date) -> (point: CGPoint, opacity: Double)? {
        guard lanternLanded else { return nil }
        var progress = 0.0
        if let driftStart {
            let p = min(max(date.timeIntervalSince(driftStart) / Self.driftDuration, 0), 1)
            progress = p * p * (3 - 2 * p)
        }
        let bob = sin(date.timeIntervalSinceReferenceDate * 1.7) * 1.2
        let point = CGPoint(x: home.x + progress * 150, y: home.y + bob)
        let opacity = progress < 0.8 ? 1 : (1 - progress) / 0.2
        return (point, opacity)
    }

    /// 推进水面的波动方程；河灯漂动时，身后拖出一串轻轻的水纹
    private func waterHeights(at time: TimeInterval, lantern: (point: CGPoint, opacity: Double)?, width: CGFloat) -> [Float] {
        if let lantern, driftStart != nil, lantern.opacity > 0.1, width > 0 {
            ripples.wake(x: lantern.point.x / width, y: 0.12, at: time)
        }
        return ripples.heights(at: time)
    }

    /// 长按时贴纸是"拎起来"的样子（放大 3%），墨点要从同样的位置出发
    private func stickerRect(center: CGPoint) -> CGRect {
        let side = Self.stickerSize * 1.03
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// 轻点水面：荡开一圈涟漪
    private func touchWater(at location: CGPoint, size: CGSize, waterY: CGFloat) {
        guard location.y > waterY, size.width > 0 else { return }
        ripples.drop(x: location.x / size.width, y: (location.y - waterY) / max(size.height - waterY, 1), strength: 0.7)
        waterTouches += 1
        let notes = RitualSound.Cue.waterNotes
        RitualSound.play(.water(min(max(Int(location.x / size.width * CGFloat(notes)), 0), notes - 1)))
    }

    private var particleColors: [Color] {
        palette.map(Color.init(rgb:)) + [Color.ink.opacity(0.6), .white]
    }

    // MARK: - 底部：写下谢谢 + 长按印章 / 完成

    @ViewBuilder
    private var bottom: some View {
        switch phase {
        case .writing:
            VStack(spacing: 22) {
                TextField(suggestion, text: $note, axis: .vertical)
                    .font(.wlQuote)
                    .multilineTextAlignment(.center)
                    .lineLimit(1...3)
                    .focused($noteFocused)
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.hairline).frame(height: 1)
                    }
                    .accessibilityLabel("对它说一句谢谢")

                HoldToReleaseButton {
                    release()
                }
            }
            .transition(.opacity)

        case .dissolving:
            Text(finalNote)
                .font(.wlQuote)
                .foregroundStyle(.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(height: 180)
                .transition(.opacity)

        case .sealed:
            VStack(spacing: 18) {
                Text("「\(finalNote)」")
                    .font(.wlQuote)
                    .multilineTextAlignment(.center)
                Text("它化作一盏河灯，漂进了你的园林　·　\(WLFormat.date(.now))")
                    .font(.wlCaption)
                    .monospacedDigit()
                    .foregroundStyle(.inkSecondary)
                Button(action: onFinish) {
                    Text("收入图鉴")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.vermilion)
                .padding(.top, 8)
            }
            .transition(.opacity.combined(with: .offset(y: 10)))
        }
    }

    private var finalNote: String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? suggestion : trimmed
    }

    private func release() {
        noteFocused = false
        // 风声、水声、盖章声之间，音乐先退到远处
        AmbientMusic.duck(for: 7)
        onReleased(finalNote)
        dissolveStart = .now
        phase = .dissolving
        let landing = usesInk ? InkDissolveView.landingTime : 2.2
        Task {
            try? await Task.sleep(for: .seconds(landing))
            // 墨点收拢：河灯在水面上亮起，荡开一圈涟漪
            RitualSound.play(.lantern)
            ripples.drop(x: 0.5 + 34 / Double(max(stageWidth, 1)), y: 0.1, strength: 1.1)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { lanternLanded = true }
            phase = .sealed
            try? await Task.sleep(for: .milliseconds(800))
            RitualSound.play(.stamp)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                stampLanded = true
            }
            try? await Task.sleep(for: .milliseconds(700))
            driftStart = .now
        }
    }
}
