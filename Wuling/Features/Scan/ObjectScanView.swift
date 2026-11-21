import AVFoundation
import RealityKit
import SwiftUI

/// LiDAR 精细扫描（Apple Object Capture，带 LiDAR 的 iPhone Pro 机型）：
/// 绕着物品慢慢走一圈，系统自动拍下几十张照片；拍完在手机上重建出完整的 3D 模型（USDZ）。
struct ObjectScanView: View {
    let spiritID: UUID
    var onFinished: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = ObjectScanModel()

    /// 只在带 LiDAR 的机型上开放
    static var isSupported: Bool { DeviceSupport.hasLiDAR && ObjectCaptureSession.isSupported }

    var body: some View {
        ZStack {
            if let session = model.session {
                ObjectCaptureView(session: session)
                    .ignoresSafeArea()
            } else {
                AmbientBackdrop(intensity: 0.6)
            }

            VStack {
                Spacer()
                panel
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                model.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .foregroundStyle(.ink)
            .padding(.leading, Metrics.gutter)
            .padding(.top, 8)
            .accessibilityLabel("取消扫描")
        }
        .task { await model.start(for: spiritID) }
        .onDisappear { model.cancel() }
        .onChange(of: model.phase) { _, phase in
            if case let .done(fileName) = phase {
                onFinished(fileName)
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    dismiss()
                }
            }
        }
        .sensoryFeedback(.success, trigger: model.phase.isDone)
    }

    @ViewBuilder
    private var panel: some View {
        VStack(spacing: 12) {
            switch model.phase {
            case .unsupported:
                message("这台手机不支持 LiDAR 扫描", detail: "可以用「手办」查看由物灵生成的 3D 模型。")
            case .preparing:
                ProgressView()
                message("正在准备相机……", detail: model.preparingHint)
            case .ready:
                message("把它放在桌面中央", detail: "四周留出空间，光线均匀。准备好后，让取景框框住它。")
                primary("框住了") { model.startDetecting() }
            case .detecting:
                message("调整框的大小，刚好包住它", detail: nil)
                primary("开始扫描") { model.startCapturing() }
            case .capturing:
                message(model.passCompleted ? "这一圈拍好了" : "绕着它慢慢走一圈",
                        detail: model.feedbackHint ?? (model.passCompleted ? "可以完成，也可以再从更高或更低的角度拍一圈。" : "保持手机对准它，跟着屏幕上的提示走。"))
                HStack(spacing: 12) {
                    if model.passCompleted {
                        secondary("再拍一圈") { model.beginNewPass() }
                    }
                    primary("完成扫描") { model.finish() }
                }
            case .finishing:
                ProgressView()
                message("正在整理照片……", detail: nil)
            case let .reconstructing(progress):
                ProgressView(value: progress).tint(.vermilion).frame(maxWidth: 240)
                message("正在重建 3D 模型（\(Int(progress * 100))%）", detail: "大约需要一两分钟，请不要离开这个页面。")
            case .done:
                Label("3D 模型做好了", systemImage: "checkmark.seal").font(.system(size: 17, weight: .semibold))
            case let .failed(reason):
                message("没能完成扫描", detail: reason)
                secondary("关闭") { dismiss() }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .foregroundStyle(.ink)
        .animation(.wlCalm, value: model.phase)
    }

    private func message(_ title: String, detail: String?) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 17, weight: .semibold))
            if let detail {
                Text(detail).font(.system(size: 13)).foregroundStyle(.inkSecondary).multilineTextAlignment(.center)
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(.vermilion)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.glass)
        .foregroundStyle(.ink)
    }
}

/// Object Capture 的流程：准备 → 框住物体 → 绕拍 → 整理 → 重建 → 完成
@MainActor
@Observable
final class ObjectScanModel {
    enum Phase: Equatable {
        case unsupported, preparing, ready, detecting, capturing, finishing
        case reconstructing(Double)
        /// 模型文件名（存在 Documents/Scans 下）
        case done(String)
        case failed(String)

        var isDone: Bool {
            if case .done = self { return true }
            return false
        }
    }

    private(set) var phase: Phase = .preparing
    private(set) var session: ObjectCaptureSession?
    private(set) var passCompleted = false
    private(set) var preparingHint: String? = "将镜头对准桌面并轻轻移动手机"
    private(set) var feedbackHint: String?

    @ObservationIgnored private var workFolder: URL?
    @ObservationIgnored private var fileName = ""
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var reconstructTask: Task<Void, Never>?
    @ObservationIgnored private var photogrammetry: PhotogrammetrySession?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var cancelled = false

    static var scansFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Scans", isDirectory: true)
    }

    static func url(forScan fileName: String) -> URL {
        scansFolder.appendingPathComponent(fileName)
    }

    func start(for spiritID: UUID) async {
        guard !started, session == nil, phase == .preparing else { return }
        started = true
        cancelled = false

        guard ObjectCaptureSession.isSupported else {
            phase = .unsupported
            return
        }

        // 先确保已拿到相机权限，避免 ObjectCaptureSession 静默卡在初始化
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            authorized = false
        }
        guard !cancelled else { return }
        guard authorized else {
            phase = .failed("还没有相机权限，请在「设置 → 物灵」里开启相机。")
            return
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Scan-\(UUID().uuidString)", isDirectory: true)
        let images = folder.appendingPathComponent("Images", isDirectory: true)
        let checkpoint = folder.appendingPathComponent("Checkpoint", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: Self.scansFolder, withIntermediateDirectories: true)
        } catch {
            phase = .failed("没能创建扫描文件夹。")
            return
        }
        workFolder = folder
        fileName = "\(spiritID.uuidString).usdz"

        // 先创建并挂载给 ObjectCaptureView，再开启状态监听，最后再 start()，避免错过 .ready / .failed
        let session = ObjectCaptureSession()
        self.session = session

        tasks.append(Task { [weak self] in
            for await state in session.stateUpdates {
                self?.handle(state)
            }
        })

        // 等待一个渲染周期让 ObjectCaptureView 挂载好，再启动采集会话
        try? await Task.sleep(for: .milliseconds(100))
        guard !cancelled, self.session === session else { return }

        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = checkpoint
        session.start(imagesDirectory: images, configuration: configuration)

        // 立刻同步一次当前状态，兜底防止 start() 同步切状态早于流消费
        handle(session.state)

        // 定时同步状态、扫描圈完成标记与实时追踪提示（兜底不卡死）
        tasks.append(Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                guard let self, let session = self.session else { return }
                ticks += 1
                self.handle(session.state)
                if self.passCompleted != session.userCompletedScanPass {
                    self.passCompleted = session.userCompletedScanPass
                }
                self.feedbackHint = Self.describe(session.feedback)
                if self.phase == .preparing && ticks == 15 {
                    self.preparingHint = "请保持光线充足，对准有纹理的桌面缓慢晃动手机"
                }
            }
        })
    }

    private func handle(_ state: ObjectCaptureSession.CaptureState) {
        switch state {
        case .initializing:
            if phase != .preparing { phase = .preparing }
        case .ready:
            if phase != .ready { phase = .ready }
        case .detecting:
            if phase != .detecting { phase = .detecting }
        case .capturing:
            if phase != .capturing { phase = .capturing }
        case .finishing:
            if phase != .finishing { phase = .finishing }
        case .completed:
            if reconstructTask == nil, !phase.isDone {
                reconstructTask = Task { await reconstruct() }
            }
        case let .failed(error):
            let message = error.localizedDescription
            if phase != .failed(message) {
                phase = .failed(message)
            }
        @unknown default:
            break
        }
    }

    private static func describe(_ feedback: Set<ObjectCaptureSession.Feedback>) -> String? {
        if feedback.contains(.environmentTooDark) { return "环境有点暗，换到更亮的地方试试。" }
        if feedback.contains(.movingTooFast) { return "移动太快了，稍微放慢一点。" }
        if feedback.contains(.objectTooClose) { return "离得太近了，稍微退后一点。" }
        if feedback.contains(.objectTooFar) { return "离得有点远，靠近一些。" }
        if feedback.contains(.outOfFieldOfView) { return "把物品保持在画面中央。" }
        return nil
    }

    func startDetecting() {
        let ok = session?.startDetecting() ?? false
        if let state = session?.state { handle(state) }
        if !ok && phase == .ready {
            preparingHint = "请再对准物体正中央试一次"
        }
    }

    func startCapturing() {
        session?.startCapturing()
        if let state = session?.state { handle(state) }
    }

    func beginNewPass() {
        passCompleted = false
        session?.beginNewScanPass()
    }

    func finish() {
        session?.finish()
        if let state = session?.state { handle(state) }
    }

    func cancel() {
        cancelled = true
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        reconstructTask?.cancel()
        reconstructTask = nil
        photogrammetry?.cancel()
        photogrammetry = nil
        session?.cancel()
        session = nil
        if let workFolder {
            try? FileManager.default.removeItem(at: workFolder)
            self.workFolder = nil
        }
    }

    /// 在手机上把照片重建成 USDZ
    private func reconstruct() async {
        guard let workFolder else { return }
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        session = nil   // 先释放相机
        guard PhotogrammetrySession.isSupported else {
            phase = .failed("这台设备不支持端侧 3D 重建。")
            try? FileManager.default.removeItem(at: workFolder)
            self.workFolder = nil
            return
        }
        phase = .reconstructing(0)
        let images = workFolder.appendingPathComponent("Images", isDirectory: true)
        let output = Self.url(forScan: fileName)
        try? FileManager.default.removeItem(at: output)
        do {
            var configuration = PhotogrammetrySession.Configuration()
            configuration.checkpointDirectory = workFolder.appendingPathComponent("Checkpoint", isDirectory: true)
            let session = try PhotogrammetrySession(input: images, configuration: configuration)
            self.photogrammetry = session
            try session.process(requests: [.modelFile(url: output, detail: .reduced)])
            for try await event in session.outputs {
                if cancelled { break }
                switch event {
                case let .requestProgress(_, fractionComplete):
                    phase = .reconstructing(fractionComplete)
                case .requestComplete:
                    phase = .done(fileName)
                case let .requestError(_, error):
                    phase = .failed(error.localizedDescription)
                case .processingCancelled:
                    phase = .failed("重建被取消了。")
                default:
                    break
                }
            }
        } catch {
            if !cancelled {
                phase = .failed(error.localizedDescription)
            }
        }
        self.photogrammetry = nil
        try? FileManager.default.removeItem(at: workFolder)
        self.workFolder = nil
    }
}
