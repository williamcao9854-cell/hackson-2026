import SwiftUI

/// 接灵：在身边广播自己的名章，等对方把物灵传过来。收到后进入「一个物灵来到了你身边」。
struct ReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("wuling.mySeal") private var mySeal = ""
    @State private var sealDraft = ""
    @State private var link: RelayLink?
    @FocusState private var sealFocused: Bool

    var body: some View {
        ZStack {
            if let capsule = link?.receivedCapsule {
                ArrivalView(capsule: capsule)
                    .transition(.opacity)
            } else {
                AmbientBackdrop(intensity: 0.6)
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text("Receive").eyebrow()
                        Text("接灵").font(.system(size: 26, weight: .semibold))
                    }
                    .padding(.top, 64)

                    Spacer()
                    if let link {
                        stage(link)
                    } else {
                        sealEntry
                    }
                    Spacer()
                    Spacer()
                }
                .padding(.horizontal, Metrics.gutter)
                .overlay(alignment: .topLeading) { closeButton }
            }
        }
        .foregroundStyle(.ink)
        .animation(.wlCalm, value: link?.state)
        .sensoryFeedback(.impact(weight: .medium), trigger: link?.state == .received)
        .onAppear {
            sealDraft = mySeal
            if !mySeal.trimmingCharacters(in: .whitespaces).isEmpty { start() }
        }
        .onDisappear { link?.stop() }
    }

    private func start() {
        let seal = RelayLogic.normalizedSeal(sealDraft)
        guard !seal.isEmpty else { return }
        mySeal = seal
        sealFocused = false
        let link = RelayLink(role: .receiver, seal: seal)
        self.link = link
        link.startReceiving()
    }

    /// 等待中想换个名章：先停掉广播，回到填写名章那一步
    private func editSeal() {
        link?.stop()
        withAnimation(.wlCalm) { link = nil }
        sealDraft = mySeal
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            sealFocused = true
        }
    }

    private var editSealButton: some View {
        Button {
            editSeal()
        } label: {
            Label("改名章", systemImage: "pencil")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.inkSecondary)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .foregroundStyle(.ink)
        .padding(.leading, Metrics.gutter)
        .padding(.top, 8)
        .accessibilityLabel("关闭")
    }

    // MARK: - 先写下名章

    private var sealEntry: some View {
        VStack(spacing: 20) {
            Text("对方会在身边看到你的名章，\n点一下，就能把物灵传给你。")
                .font(.system(size: 15))
                .foregroundStyle(.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            TextField("你的名章，比如：阿明", text: $sealDraft)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .focused($sealFocused)
                .submitLabel(.go)
                .onSubmit { start() }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .glassEffect(.regular, in: Capsule())
            Button {
                start()
            } label: {
                Text("开始接灵")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.vermilion)
            .disabled(RelayLogic.normalizedSeal(sealDraft).isEmpty)
        }
    }

    // MARK: - 等待 / 邀请 / 传送中

    @ViewBuilder
    private func stage(_ link: RelayLink) -> some View {
        switch link.state {
        case let .invited(sender, spirit, epithet):
            invitation(link: link, sender: sender, spirit: spirit, epithet: epithet)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
        case let .transferring(progress):
            VStack(spacing: 16) {
                ZStack {
                    InkRipples(rings: 3, period: 2.4)
                    GooseFlight(leftToRight: false, duration: 2.8)
                }
                .frame(height: 260)
                Text("物灵正在飞来……").font(.system(size: 18, weight: .semibold))
                ProgressView(value: progress).tint(.vermilion).frame(maxWidth: 220)
            }
        case let .failed(message):
            VStack(spacing: 14) {
                Text("没能收下").font(.system(size: 18, weight: .semibold))
                Text(message).font(.system(size: 14)).foregroundStyle(.inkSecondary).multilineTextAlignment(.center)
                Button("再等一次") { link.searchAgain() }
                    .buttonStyle(.glass)
                    .foregroundStyle(.ink)
                editSealButton
            }
        default:
            VStack(spacing: 20) {
                ZStack {
                    InkRipples()
                    // 轻点自己的名章，可以回去改
                    Button {
                        editSeal()
                    } label: {
                        SealStamp(text: link.seal, size: 64, rotation: .degrees(-6))
                            .padding(12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("我的名章：\(link.seal)")
                    .accessibilityHint("轻点可以改名章")
                }
                .frame(height: 280)
                Text("把手机靠近对方，等物灵飞来")
                    .font(.system(size: 18, weight: .semibold))
                Text("对方在物灵里点「传给下一位」，\n盖章后选「面对面传给 TA」，就能看到你")
                    .font(.system(size: 14))
                    .foregroundStyle(.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                editSealButton
            }
        }
    }

    private func invitation(link: RelayLink, sender: String, spirit: String, epithet: String) -> some View {
        VStack(spacing: 18) {
            SealStamp(text: sender, size: 64, rotation: .degrees(-6), style: .yang)
            VStack(spacing: 6) {
                Text("「\(sender)」想把").font(.system(size: 15)).foregroundStyle(.inkSecondary)
                Text(spirit).font(.system(size: 30, weight: .semibold, design: .serif))
                if !epithet.isEmpty {
                    Text(epithet).font(.system(size: 14)).foregroundStyle(.inkSecondary)
                }
                Text("传给你").font(.system(size: 15)).foregroundStyle(.inkSecondary)
            }
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        link.respond(accept: false)
                    } label: {
                        Text("婉拒").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.ink)

                    Button {
                        link.respond(accept: true)
                    } label: {
                        Text("收下").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.vermilion)
                }
            }
        }
        .padding(24)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
