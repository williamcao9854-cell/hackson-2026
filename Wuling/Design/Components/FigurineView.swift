import ARKit
import QuickLook
import SceneKit
import SwiftUI

/// 3D 手办 / 扫描模型的查看器：手指拖动转着看，没碰时缓缓左右转；可以用 AR 摆在桌上。
struct FigurineView: View {
    enum Source: Equatable {
        /// 由物灵立牌图一键生成
        case figurine(UIImage, key: String)
        /// LiDAR 扫描得到的 USDZ
        case scan(URL)

        static func == (lhs: Source, rhs: Source) -> Bool {
            switch (lhs, rhs) {
            case let (.figurine(_, a), .figurine(_, b)): a == b
            case let (.scan(a), .scan(b)): a == b
            default: false
            }
        }
    }

    var source: Source
    var name: String

    @State private var node: SCNNode?
    @State private var failed = false
    @State private var exporting = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let node {
                FigurineSceneView(node: node)
                    .transition(.opacity)
            } else if failed {
                Label("这台设备上没能生成手办", systemImage: "cube.transparent")
                    .font(.system(size: 13))
                    .foregroundStyle(.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(isScan ? "正在读取扫描模型……" : "正在为它塑一尊手办……")
                        .font(.system(size: 13))
                        .foregroundStyle(.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if node != nil {
                Button {
                    openAR()
                } label: {
                    Label(exporting ? "准备中……" : "AR 摆在桌上", systemImage: "arkit")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .foregroundStyle(.ink)
                .disabled(exporting)
                .padding(.bottom, 6)
            }
        }
        .animation(.wlCalm, value: node != nil)
        .task(id: sourceKey) { await load() }
    }

    private var isScan: Bool {
        if case .scan = source { return true }
        return false
    }

    private var sourceKey: String {
        switch source {
        case let .figurine(_, key): "figurine-\(key)"
        case let .scan(url): "scan-\(url.lastPathComponent)"
        }
    }

    private func load() async {
        node = nil
        failed = false
        let source = self.source
        let result: SCNNode? = await Task.detached(priority: .userInitiated) {
            switch source {
            case let .figurine(image, key): ReliefModeler.figurineNode(for: image, key: key)
            case let .scan(url): ReliefModeler.scannedNode(at: url)
            }
        }.value
        node = result
        failed = result == nil
    }

    private func openAR() {
        if case let .scan(url) = source {
            ARQuickLook.present(url)
            return
        }
        guard let node else { return }
        exporting = true
        let name = self.name
        Task {
            let url = await Task.detached(priority: .userInitiated) { ReliefModeler.exportUSDZ(node, name: name) }.value
            exporting = false
            if let url { ARQuickLook.present(url) }
        }
    }
}

/// SceneKit 视图：透明背景，柔和的三点光，缓缓左右转，可以拖动转台式旋转
struct FigurineSceneView: UIViewRepresentable {
    let node: SCNNode

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.preferredFramesPerSecond = 60

        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 850
        key.eulerAngles = SCNVector3(-0.6, 0.55, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 420
        rim.eulerAngles = SCNVector3(-0.2, Float.pi - 0.7, 0)
        scene.rootNode.addChildNode(rim)

        let turntable = SCNNode()
        turntable.addChildNode(node)
        turntable.eulerAngles.y = -0.35
        let swing = SCNAction.rotateBy(x: 0, y: 0.7, z: 0, duration: 3.4)
        swing.timingMode = .easeInEaseOut
        turntable.runAction(.repeatForever(.sequence([swing, swing.reversed()])))
        scene.rootNode.addChildNode(turntable)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 32
        camera.position = SCNVector3(0, 0, 2.15)
        scene.rootNode.addChildNode(camera)

        view.scene = scene
        view.pointOfView = camera
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.maximumVerticalAngle = 25
        view.defaultCameraController.minimumVerticalAngle = -15
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}

/// 系统的 AR 快速查看：把模型摆在真实的桌面上。
/// 直接用 UIKit 弹出，这样系统自带的"完成"按钮和"物体 / AR"切换都能正常出现。
@MainActor
enum ARQuickLook {
    private static var dataSource: DataSource?

    static func present(_ url: URL) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }

        let source = DataSource(url: url)
        dataSource = source
        let preview = QLPreviewController()
        preview.dataSource = source
        top.present(preview, animated: true)
    }

    final class DataSource: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            let item = ARQuickLookPreviewItem(fileAt: url)
            item.allowsContentScaling = true
            return item
        }
    }
}
