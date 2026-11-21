import AVFoundation
import SwiftUI
import UIKit

/// 自制相机：只需要"取景 + 拍一张"，比系统相机界面更贴合 App 的设计。
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    enum Status: Equatable {
        case idle
        case running
        /// 没有权限或没有相机（例如模拟器）
        case unavailable
    }

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "wuling.camera")
    private var isConfigured = false
    private var continuation: CheckedContinuation<UIImage?, Never>?

    /// 请求权限并启动相机，返回最终状态
    func start() async -> Status {
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard authorized,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else { return .unavailable }

        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                if !isConfigured {
                    session.beginConfiguration()
                    session.sessionPreset = .photo
                    guard let input = try? AVCaptureDeviceInput(device: device),
                          session.canAddInput(input), session.canAddOutput(output)
                    else {
                        session.commitConfiguration()
                        continuation.resume(returning: .unavailable)
                        return
                    }
                    session.addInput(input)
                    session.addOutput(output)
                    output.maxPhotoQualityPrioritization = .balanced
                    session.commitConfiguration()
                    isConfigured = true
                }
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: .running)
            }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capturePhoto() async -> UIImage? {
        // 上一张还没拍完时忽略，避免覆盖等待中的回调
        guard continuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            queue.async { [self] in
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        let pending = continuation
        continuation = nil
        pending?.resume(returning: image)
    }
}

/// 相机取景画面
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
