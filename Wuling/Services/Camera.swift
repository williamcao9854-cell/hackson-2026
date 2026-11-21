import AVFoundation
import SwiftUI
import UIKit

/// 自制相机：取景、多镜头缩放（0.5× / 1× / 2× / 3×）、双指缩放、轻点对焦、拍照。
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
    private var device: AVCaptureDevice?

    /// 显示倍率 × displayBase = 设备的 videoZoomFactor。
    /// 有超广角的多摄设备，videoZoomFactor = 1 是超广角，所以"1×"对应的 factor 是 2 左右。
    private(set) var displayBase: CGFloat = 1
    /// 镜头按钮上的倍率，例如 [0.5, 1, 2, 3]
    private(set) var lensPresets: [CGFloat] = [1, 2]
    private(set) var minDisplayZoom: CGFloat = 1
    private(set) var maxDisplayZoom: CGFloat = 6

    /// 请求权限并启动相机，返回最终状态
    func start() async -> Status {
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard authorized, let device = Self.bestBackCamera() else { return .unavailable }
        self.device = device

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
                    configureZoom(for: device)
                    isConfigured = true
                }
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: .running)
            }
        }
    }

    /// 优先选能无缝切换镜头的多摄"虚拟相机"
    private static func bestBackCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back).devices
        for type in types {
            if let device = devices.first(where: { $0.deviceType == type }) { return device }
        }
        return nil
    }

    private func configureZoom(for device: AVCaptureDevice) {
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let constituents = device.constituentDevices.map(\.deviceType)
        let hasUltraWide = constituents.contains(.builtInUltraWideCamera)
        let hasTele = constituents.contains(.builtInTelephotoCamera)

        displayBase = hasUltraWide ? (switchOvers.first ?? 2) : 1
        var presets: [CGFloat] = hasUltraWide ? [0.5, 1] : [1]
        if hasTele, let teleFactor = switchOvers.last {
            presets.append((teleFactor / displayBase).rounded())
        } else {
            presets.append(2)
        }
        lensPresets = presets
        minDisplayZoom = device.minAvailableVideoZoomFactor / displayBase
        maxDisplayZoom = min(device.maxAvailableVideoZoomFactor / displayBase, 10)

        // 默认 1×
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, min(displayBase, device.maxAvailableVideoZoomFactor))
            device.unlockForConfiguration()
        }
    }

    /// 设置缩放（显示倍率）。点镜头按钮时平滑过渡，双指缩放时直接跟手。
    func setZoom(_ display: CGFloat, smooth: Bool) {
        guard let device else { return }
        let lower: CGFloat = device.minAvailableVideoZoomFactor
        let upper: CGFloat = min(device.maxAvailableVideoZoomFactor, maxDisplayZoom * displayBase)
        let wanted: CGFloat = display * displayBase
        let factor: CGFloat = max(lower, min(wanted, upper))
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if smooth {
                device.ramp(toVideoZoomFactor: factor, withRate: 10)
            } else {
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = factor
            }
            device.unlockForConfiguration()
        }
    }

    /// 对焦并测光到指定点（设备坐标，0...1）
    func focus(at devicePoint: CGPoint) {
        guard let device else { return }
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
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

/// 取景画面。`layerBox` 用来把屏幕上的点换算成相机坐标（轻点对焦）。
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var layerBox: PreviewLayerBox? = nil

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        layerBox?.layer = view.previewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

final class PreviewLayerBox {
    weak var layer: AVCaptureVideoPreviewLayer?

    func devicePoint(for viewPoint: CGPoint) -> CGPoint? {
        layer?.captureDevicePointConverted(fromLayerPoint: viewPoint)
    }
}
