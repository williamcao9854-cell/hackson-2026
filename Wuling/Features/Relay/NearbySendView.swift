import SwiftUI

/// 面对面传出：身边在「接灵」的人以名章的样子出现在涟漪里，点一下对方，物灵就飞过去。
struct NearbySendView: View {
    let capsule: SpiritCapsule
    let seal: String
    var onSent: () -> Void
    /// 用户想改用系统分享。这里只负责告诉外面，真正弹出要等本页完全退场（见 RelaySendView 的 onDismiss），
    /// 两个弹窗挤在同一帧时，系统分享会被 SwiftUI 吞掉。
    var onUseShareSheet: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var link: RelayLink?
    @State private var finished = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.top, 8)
                    .frame(minHeight: 96, alignment: .top)

                radar
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)

                Spacer(minLength: 12)
                footer
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 12)
            .background(AmbientBackdrop(intensity: 0.35))
            .foregroundStyle(.ink)
            .navigationTitle("面对面传灵")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .task {
            guard link == nil else { return }
            let link = RelayLink(role: .sender, seal: seal)
            self.link = link
            link.startSending(capsule)
        }
        .onDisappear { link?.stop() }
        .onChange(of: link?.state) { _, state in
            guard state == .sent, !finished else { return }
            finished = true
            Task {
                try? await Task.sleep(for: .seconds(2.4))
                onSent()
                dismiss()
            }
        }
        .sensoryFeedback(.success, trigger: finished)
        .presentationDetents([.large])
    }

    // MARK: - 状态说明

    @ViewBuilder
    private var header: some View {
        let state = link?.state ?? .idle
        VStack(spacing: 8) {
            switch state {
            case .searching where (link?.peers.isEmpty ?? true), .idle:
                title("正在寻找身边的人……")
                subtitle("请对方打开物灵，点首页的「接灵」")
            case .searching:
                title("轻点对方的名章")
                subtitle("把「\(capsule.name)」传给 TA")
            case let .awaitingAcceptance(partner):
                title("等待「\(partner)」收下……")
                subtitle("对方的手机上会出现你的名章和留言")
            case let .transferring(progress):
                title("「\(capsule.name)」正在飞过去")
                ProgressView(value: progress)
                    .tint(.vermilion)
                    .frame(maxWidth: 220)
            case .sent:
                title("已传给「\(link?.partnerSeal ?? "")」")
                subtitle("愿它在新主人那里也被好好珍惜")
            case .declined:
                title("对方暂时没有收下")
                retryButton
            case let .failed(message):
                title("没能传过去")
                subtitle(message)
                retryButton
            default:
                EmptyView()
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .animation(.wlCalm, value: state)
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 20, weight: .semibold))
    }

    private func subtitle(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundStyle(.inkSecondary)
    }

    private var retryButton: some View {
        Button("再试一次") { link?.searchAgain() }
            .buttonStyle(.glass)
            .foregroundStyle(.ink)
            .padding(.top, 4)
    }

    // MARK: - 涟漪与名章

    private var radar: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius: CGFloat = min(size.width, size.height) * 0.36
            let peers = link?.peers ?? []
            let state = link?.state ?? .idle

            ZStack {
                InkRipples()

                // 中间是我
                VStack(spacing: 6) {
                    SealStamp(text: seal, size: 56, rotation: .degrees(-6))
                    Text("我").font(.system(size: 12)).foregroundStyle(.inkSecondary)
                }
                .position(center)

                // 身边的人，绕着我排成一圈
                ForEach(Array(peers.enumerated()), id: \.element.id) { index, peer in
                    let angle: Double = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(max(peers.count, 1))
                    let x: CGFloat = center.x + radius * CGFloat(cos(angle))
                    let y: CGFloat = center.y + radius * CGFloat(sin(angle))
                    let chosen: Bool = state == .awaitingAcceptance(peer.seal)
                    Button {
                        link?.invite(peer)
                    } label: {
                        VStack(spacing: 6) {
                            SealStamp(text: peer.seal, size: 52, rotation: .degrees(5), style: .yang)
                                .scaleEffect(chosen ? 1.12 : 1)
                            Text(peer.seal)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(8)
                        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(state != .searching)
                    .position(x: x, y: y)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("传给 \(peer.seal)")
                }

                if case .transferring = state {
                    GooseFlight(leftToRight: true, duration: 2.6)
                }
                if state == .sent {
                    GooseFlight(leftToRight: true, duration: 2.4)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: peers.count)
        }
    }

    // MARK: - 备用方式

    private var footer: some View {
        Button {
            onUseShareSheet()
            dismiss()
        } label: {
            Label("用其他方式发送（隔空投送、微信……）", systemImage: "square.and.arrow.up")
                .font(.system(size: 14, weight: .medium))
        }
        .buttonStyle(.glass)
        .foregroundStyle(.ink)
    }
}
