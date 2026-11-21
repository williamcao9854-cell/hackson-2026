import MultipeerConnectivity
import SwiftUI

/// 面对面传灵：两台手机都打开物灵，一个「传」，一个「接」，通过 MultipeerConnectivity 直接连接。
///
/// 不需要网络、不需要服务器，也不用经过系统分享菜单和"用其他 App 打开"。
/// 接收方在附近广播自己的名章；传出方能看到身边所有在「接灵」的人，点一下对方即可发出邀请，
/// 对方确认"收下"后，物灵文件通过加密连接传过去。
@MainActor
@Observable
final class RelayLink {
    enum Role { case sender, receiver }

    struct Peer: Identifiable, Hashable {
        let id: MCPeerID
        var seal: String
    }

    enum State: Equatable {
        case idle
        /// 传出方：正在寻找身边在接灵的人
        case searching
        /// 接收方：正在等待物灵飞来
        case waiting
        /// 接收方：有人想传物灵过来
        case invited(sender: String, spirit: String, epithet: String)
        /// 传出方：已发出邀请，等对方收下
        case awaitingAcceptance(String)
        case transferring(Double)
        case sent
        case received
        case declined
        case failed(String)
    }

    static let serviceType = "wuling-relay"

    private(set) var state: State = .idle
    private(set) var peers: [Peer] = []
    private(set) var receivedCapsule: SpiritCapsule?
    /// 对方的名章（传出成功后显示"已传给 ××"）
    private(set) var partnerSeal = ""

    let role: Role
    let seal: String

    @ObservationIgnored private let peerID: MCPeerID
    @ObservationIgnored private let session: MCSession
    @ObservationIgnored private var bridge: RelayLinkBridge?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var pendingInvitation: ((Bool, MCSession?) -> Void)?
    @ObservationIgnored private var outgoing: SpiritCapsule?
    @ObservationIgnored private var progress: Progress?
    @ObservationIgnored private var progressTimer: Timer?

    private struct Invitation: Codable {
        var sender: String
        var spirit: String
        var epithet: String
    }

    init(role: Role, seal: String) {
        self.role = role
        let trimmed = seal.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "物灵主人" : trimmed
        self.seal = resolved
        // MCPeerID 的名字最多 63 字节，中文每字 3 字节
        self.peerID = MCPeerID(displayName: String(resolved.prefix(20)))
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        let bridge = RelayLinkBridge(owner: self)
        self.bridge = bridge
        session.delegate = bridge
    }

    // MARK: - 开始 / 结束

    /// 传出方：开始寻找身边在接灵的人
    func startSending(_ capsule: SpiritCapsule) {
        outgoing = capsule
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = bridge
        browser.startBrowsingForPeers()
        self.browser = browser
        state = .searching
    }

    /// 接收方：开始在附近广播自己的名章
    func startReceiving() {
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["seal": String(seal.prefix(40))],
                                                   serviceType: Self.serviceType)
        advertiser.delegate = bridge
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        state = .waiting
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        pendingInvitation?(false, nil)
        pendingInvitation = nil
        stopTracking()
        session.disconnect()
    }

    // MARK: - 传出方

    func invite(_ peer: Peer) {
        guard let outgoing, let browser else { return }
        let info = Invitation(sender: seal, spirit: outgoing.name, epithet: outgoing.epithet)
        let context = try? JSONEncoder().encode(info)
        partnerSeal = peer.seal
        browser.invitePeer(peer.id, to: session, withContext: context, timeout: 45)
        state = .awaitingAcceptance(peer.seal)
    }

    /// 对方婉拒或超时后，回到寻找状态
    func searchAgain() {
        session.disconnect()
        state = role == .sender ? .searching : .waiting
    }

    private func send(_ capsule: SpiritCapsule, to peer: MCPeerID) {
        do {
            let url = try capsule.writeTemporaryFile()
            state = .transferring(0)
            let progress = session.sendResource(at: url, withName: capsule.suggestedFileName, toPeer: peer) { [weak self] error in
                Task { @MainActor in self?.finishSending(error: error) }
            }
            track(progress)
        } catch {
            state = .failed("没能打包这个物灵，再试一次吧。")
        }
    }

    private func finishSending(error: Error?) {
        stopTracking()
        if error == nil {
            state = .sent
            browser?.stopBrowsingForPeers()
        } else {
            state = .failed("传到一半断开了。请两台手机靠近一些，再试一次。")
        }
    }

    // MARK: - 接收方

    func respond(accept: Bool) {
        pendingInvitation?(accept, accept ? session : nil)
        pendingInvitation = nil
        state = accept ? .transferring(0) : .waiting
    }

    // MARK: - 来自 MultipeerConnectivity 的回调（已切回主线程）

    fileprivate func found(_ peer: MCPeerID, info: [String: String]?) {
        guard !peers.contains(where: { $0.id == peer }) else { return }
        peers.append(Peer(id: peer, seal: info?["seal"] ?? peer.displayName))
    }

    fileprivate func lost(_ peer: MCPeerID) {
        peers.removeAll { $0.id == peer }
    }

    fileprivate func invitation(from peer: MCPeerID, context: Data?, handler: @escaping (Bool, MCSession?) -> Void) {
        guard state == .waiting else {
            handler(false, nil)
            return
        }
        let info = context.flatMap { try? JSONDecoder().decode(Invitation.self, from: $0) }
        pendingInvitation = handler
        partnerSeal = info?.sender ?? peer.displayName
        state = .invited(sender: partnerSeal, spirit: info?.spirit ?? "一个物灵", epithet: info?.epithet ?? "")
    }

    fileprivate func peer(_ peer: MCPeerID, changed newState: MCSessionState) {
        switch newState {
        case .connected:
            if role == .sender, let outgoing, case .awaitingAcceptance = state {
                send(outgoing, to: peer)
            }
        case .notConnected:
            switch state {
            case .awaitingAcceptance: state = .declined
            case .transferring: state = .failed("连接断开了。请两台手机靠近一些，再试一次。")
            default: break
            }
        default:
            break
        }
    }

    fileprivate func startedReceiving(_ progress: Progress) {
        track(progress)
    }

    fileprivate func finishedReceiving(data: Data?) {
        stopTracking()
        if let data, let capsule = try? SpiritCapsule.decode(data) {
            receivedCapsule = capsule
            state = .received
            advertiser?.stopAdvertisingPeer()
        } else {
            state = .failed("没能收下这个物灵，请对方再传一次。")
        }
    }

    fileprivate func failedToStart() {
        state = .failed("没能打开附近连接。请在「设置 → 物灵」里允许访问本地网络。")
    }

    // MARK: - 进度

    private func track(_ progress: Progress?) {
        stopTracking()
        self.progress = progress
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let progress = self.progress, case .transferring = self.state else { return }
                self.state = .transferring(progress.fractionCompleted)
            }
        }
    }

    private func stopTracking() {
        progressTimer?.invalidate()
        progressTimer = nil
        progress = nil
    }
}

/// MultipeerConnectivity 的代理要求 NSObject，回调发生在后台线程：这里统一切回主线程交给 RelayLink。
final class RelayLinkBridge: NSObject, MCSessionDelegate, MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate {
    weak var owner: RelayLink?

    init(owner: RelayLink) {
        self.owner = owner
    }

    // MARK: 浏览（传出方）

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let owner = self.owner
        Task { @MainActor in owner?.found(peerID, info: info) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let owner = self.owner
        Task { @MainActor in owner?.lost(peerID) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        let owner = self.owner
        Task { @MainActor in owner?.failedToStart() }
    }

    // MARK: 广播（接收方）

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let owner = self.owner
        Task { @MainActor in
            if let owner {
                owner.invitation(from: peerID, context: context, handler: invitationHandler)
            } else {
                invitationHandler(false, nil)
            }
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let owner = self.owner
        Task { @MainActor in owner?.failedToStart() }
    }

    // MARK: 会话

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let owner = self.owner
        Task { @MainActor in owner?.peer(peerID, changed: state) }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {
        let owner = self.owner
        Task { @MainActor in owner?.startedReceiving(progress) }
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // 临时文件在回调返回后会被删除，必须在这里同步读出来
        let data = error == nil ? localURL.flatMap { try? Data(contentsOf: $0) } : nil
        let owner = self.owner
        Task { @MainActor in owner?.finishedReceiving(data: data) }
    }
}
