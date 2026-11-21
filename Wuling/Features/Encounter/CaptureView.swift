import PhotosUI
import SwiftUI

/// ① 取景：对准一件旧物。
struct CaptureView: View {
    @Bindable var model: EncounterModel

    @State private var camera = CameraController()
    @State private var status: CameraController.Status = .idle
    @State private var pickerItem: PhotosPickerItem?
    @State private var shutterCount = 0
    @State private var scanPhase: CGFloat = -1
    @State private var isCapturing = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 64)
                .padding(.bottom, 22)

            viewfinder
                .padding(.horizontal, Metrics.gutter)

            controls
                .padding(.top, 28)
                .padding(.bottom, 20)
        }
        .task {
            status = await camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await model.usePhoto(image)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: shutterCount)
    }

    // MARK: - 标题

    private var header: some View {
        VStack(spacing: 8) {
            Text("遇见").eyebrow()
            Text(model.isProcessingPhoto ? "正在看清它……" : "对准一件旧物")
                .font(.system(size: 26, weight: .semibold))
                .contentTransition(.opacity)
                .animation(.wlCalm, value: model.isProcessingPhoto)
            Text("一双穿旧的鞋、一只掉漆的杯子，或者你舍不得扔的任何东西")
                .font(.system(size: 14))
                .foregroundStyle(.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - 取景框

    private var viewfinder: some View {
        ZStack {
            switch status {
            case .running:
                CameraPreview(session: camera.session)
            case .unavailable:
                unavailableState
            case .idle:
                Color.ink.opacity(0.04)
            }

            if model.isProcessingPhoto, let photo = model.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .overlay { scanningShimmer }
                    .transition(.opacity)
            }

            ViewfinderCorners()
                .stroke(Color.white.opacity(status == .running ? 0.9 : 0), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .padding(26)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .animation(.wlCalm, value: model.isProcessingPhoto)
    }

    private var unavailableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.inkSecondary)
            Text("相机不可用")
                .font(.wlHeadline)
            Text("可以从相册里选一张照片，\n或者在「设置」中允许物灵使用相机。")
                .font(.system(size: 14))
                .foregroundStyle(.inkSecondary)
                .multilineTextAlignment(.center)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text("从相册选择")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.vermilion)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.card)
    }

    /// 识别中：一道柔光从上往下扫过
    private var scanningShimmer: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .white.opacity(0.45), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: geo.size.height * 0.35)
            .offset(y: scanPhase * geo.size.height)
            .onAppear {
                scanPhase = -0.4
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    scanPhase = 1.0
                }
            }
        }
        .background(Color.black.opacity(0.15))
        .allowsHitTesting(false)
    }

    // MARK: - 底部控制

    private var controls: some View {
        GlassEffectContainer(spacing: 28) {
            HStack(spacing: 44) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(.ink)
                .accessibilityLabel("从相册选择")

                Button {
                    guard !isCapturing else { return }
                    isCapturing = true
                    shutterCount += 1
                    Task {
                        if let image = await camera.capturePhoto() {
                            camera.stop()
                            await model.usePhoto(image)
                        }
                        isCapturing = false
                    }
                } label: {
                    ShutterLabel()
                }
                .buttonStyle(ShutterButtonStyle())
                .disabled(status != .running || model.isProcessingPhoto || isCapturing)
                .opacity(status == .running ? 1 : 0.35)
                .accessibilityLabel("拍照")

                // 占位，保持快门居中
                Color.clear.frame(width: 54, height: 54)
            }
        }
        .disabled(model.isProcessingPhoto)
    }
}

/// 快门：墨色细环 + 朱红圆心
private struct ShutterLabel: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.ink, lineWidth: 3)
                .frame(width: 78, height: 78)
            Circle()
                .fill(Color.vermilion)
                .frame(width: 62, height: 62)
        }
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.wlLift, value: configuration.isPressed)
    }
}

/// 取景框四角的细线
private struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 26
        var path = Path()
        // 左上
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        // 右上
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        // 右下
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        // 左下
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}
