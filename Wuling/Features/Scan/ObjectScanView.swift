import RealityKit
import SwiftUI

/// LiDAR 精细扫描（Apple Object Capture，带 LiDAR 的 iPhone Pro 机型）：
/// 绕着物品慢慢走一圈，系统自动拍下几十张照片；拍完在手机上重建出完整的 3D 模型（USDZ）。
struct ObjectScanView: View {
    let spiritID: UUID
    var onFinished: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = ObjectScanModel()

    static var isSupported: Bool { ObjectCaptureSession.isSupported }

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
        .task { model.start(for: spiritID) }
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
                message("正在准备相机……", detail: nil)
            case .ready:
                message("把它放在桌面中央", detail: "四周留出空间，光线均匀。准备好后，让取景框框住它。")
                primary("框住了") { model.startDetecting() }
            case .detecting:
                message("调整框的大小，刚好包住它", detail: nil)
                primary("开始扫描") { model.startCapturing() }
            case .capturing:
                message(model.passCompleted ? "这一圈拍好了" : "绕着它慢慢走一圈",
                        detail: model.passCompleted ? "可以完成，也可以再从更高或更低的角度拍一圈。" : "保持手机对准它，跟着屏幕上的提示走。")
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

    @ObservationIgnored private var workFolder: URL?
    @ObservationIgnored private var fileName = ""
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    static var scansFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Scans", isDirectory: true)
    }

    static func url(forScan fileName: String) -> URL {
        scansFolder.appendingPathComponent(fileName)
    }

    func start(for spiritID: UUID) {
        guard session == nil, phase == .preparing else { return }
        guard ObjectCaptureSession.isSupported else {
            phase = .unsupported
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

        let session = ObjectCaptureSession()
        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = checkpoint
        session.start(imagesDirectory: images, configuration: configuration)
        self.session = session

        tasks.append(Task { [weak self] in
            for await state in session.stateUpdates {
                self?.handle(state)
            }
        })
        // 这一圈拍完没有：定时看一眼
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let session = self.session else { return }
                if self.passCompleted != session.userCompletedScanPass {
                    self.passCompleted = session.userCompletedScanPass
                }
            }
        })
    }

    private func handle(_ state: ObjectCaptureSession.CaptureState) {
        switch state {
        case .ready: phase = .ready
        case .detecting: phase = .detecting
        case .capturing: phase = .capturing
        case .finishing: phase = .finishing
        case .completed:
            Task { await reconstruct() }
        case let .failed(error):
            phase = .failed(error.localizedDescription)
        default:
            break
        }
    }

    func startDetecting() { _ = session?.startDetecting() }
    func startCapturing() { session?.startCapturing() }
    func beginNewPass() {
        passCompleted = false
        session?.beginNewScanPass()
    }
    func finish() { session?.finish() }

    func cancel() {
        tasks.forEach { $0.cancel() }
        session?.cancel()
        session = nil
        if let workFolder { try? FileManager.default.removeItem(at: workFolder) }
    }

    /// 在手机上把照片重建成 USDZ
    private func reconstruct() async {
        guard let workFolder else { return }
        tasks.forEach { $0.cancel() }
        session = nil   // 先释放相机
        phase = .reconstructing(0)
        let images = workFolder.appendingPathComponent("Images", isDirectory: true)
        let output = Self.url(forScan: fileName)
        try? FileManager.default.removeItem(at: output)
        do {
            var configuration = PhotogrammetrySession.Configuration()
            configuration.checkpointDirectory = workFolder.appendingPathComponent("Checkpoint", isDirectory: true)
            let photogrammetry = try PhotogrammetrySession(input: images, configuration: configuration)
            try photogrammetry.process(requests: [.modelFile(url: output)])
            for try await event in photogrammetry.outputs {
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
            phase = .failed(error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: workFolder)
    }
}
