import MetalKit
import SwiftUI

/// 送别：原物被风吹散成墨点，落到水面上，再绕着落点收拢成一盏河灯。
///
/// 一条真正的 GPU 渲染管线（见 InkShaders.metal）：把抠出来的贴纸按 2pt 左右的间距采样成几千个墨点，
/// 每个墨点的轨迹都在顶点着色器里按时间算出来，CPU 每帧只传一个时间；片元着色器把它画成边缘洇开的圆点。
/// 刚开始时每个墨点是一块方形像素，拼起来正好是原图，所以从贴纸过渡到粒子没有接缝。
struct InkDissolveView: UIViewRepresentable {
    var image: UIImage
    /// 贴纸在这块画布上的位置（pt），图片按比例缩放、居中放在里面
    var imageRect: CGRect
    var waterY: CGFloat
    /// 墨点最后收进去的地方：河灯的灯芯
    var lanternPoint: CGPoint
    var startDate: Date
    var isDark: Bool

    /// 墨点从什么时候开始往河灯收拢（秒）
    static let gatherStart: Double = 1.9
    static let gatherDuration: Double = 0.75
    /// 河灯亮起的时刻：大部分墨点已经收进去
    static let landingTime: Double = 2.75
    /// 最后一个墨点也收进去了，画布清空
    static let endTime: Double = 3.1

    /// 这台设备能不能跑（Metal 不可用、着色器没编进去时，退回 Canvas 版的光点）
    static var isAvailable: Bool { InkParticleRenderer.shared != nil }

    final class Coordinator {
        var renderer: InkParticleRenderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: InkParticleRenderer.shared?.device)
        view.isOpaque = false
        view.layer.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.isUserInteractionEnabled = false

        let ink: SIMD3<Float> = isDark ? SIMD3(0.93, 0.91, 0.87) : SIMD3(0.11, 0.10, 0.09)
        if let renderer = InkParticleRenderer(image: image, imageRect: imageRect, waterY: waterY,
                                              lanternPoint: lanternPoint, startDate: startDate, ink: ink) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
            view.isPaused = false
        } else {
            view.isPaused = true
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
        coordinator.renderer = nil
    }
}

/// 和 InkShaders.metal 里的 InkParticle 一一对应（两个 float4，32 字节）
struct InkParticle {
    /// xy = 起点（pt），z = 随机数 0…1，w = 出发的延迟（秒）
    var origin: SIMD4<Float>
    /// 原图这个像素的颜色（未预乘），w = 不透明度
    var color: SIMD4<Float>
}

/// 和 InkShaders.metal 里的 InkUniforms 一一对应（四个 float4，64 字节）
struct InkUniforms {
    var view: SIMD4<Float>
    var target: SIMD4<Float>
    var ink: SIMD4<Float>
    var glow: SIMD4<Float>
}

final class InkParticleRenderer: NSObject, MTKViewDelegate {
    /// 设备和渲染管线只建一次
    static let shared: (device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState)? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "inkParticleVertex"),
              let fragment = library.makeFunction(name: "inkParticleFragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        guard let attachment = descriptor.colorAttachments[0] else { return nil }
        attachment.pixelFormat = .bgra8Unorm
        // 预乘透明度的"盖上去"混合
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        return (device, queue, pipeline)
    }()

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let particles: MTLBuffer
    private let count: Int
    private var uniforms: InkUniforms
    private let startMediaTime: CFTimeInterval

    init?(image: UIImage, imageRect: CGRect, waterY: CGFloat, lanternPoint: CGPoint, startDate: Date, ink: SIMD3<Float>) {
        guard let shared = Self.shared else { return nil }
        let sampled = Self.sample(image, in: imageRect)
        guard !sampled.particles.isEmpty,
              let buffer = shared.device.makeBuffer(bytes: sampled.particles,
                                                    length: MemoryLayout<InkParticle>.stride * sampled.particles.count,
                                                    options: .storageModeShared)
        else { return nil }

        queue = shared.queue
        pipeline = shared.pipeline
        particles = buffer
        count = sampled.particles.count
        uniforms = InkUniforms(
            view: .zero,
            target: SIMD4(Float(lanternPoint.x), Float(lanternPoint.y), Float(waterY), Float(InkDissolveView.gatherStart)),
            ink: SIMD4(ink.x, ink.y, ink.z, Float(InkDissolveView.gatherDuration)),
            glow: SIMD4(1.0, 0.8, 0.48, Float(sampled.spacing))
        )
        startMediaTime = CACurrentMediaTime() - Date.now.timeIntervalSince(startDate)
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let elapsed = CACurrentMediaTime() - startMediaTime
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        if elapsed < InkDissolveView.endTime {
            var frame = uniforms
            frame.view = SIMD4(Float(view.bounds.width), Float(view.bounds.height),
                               Float(max(elapsed, 0)), Float(view.contentScaleFactor))
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(particles, offset: 0, index: 0)
            encoder.setVertexBytes(&frame, length: MemoryLayout<InkUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()

        // 墨点全部收进河灯后，画最后一帧空白就停下，不再占用 GPU
        if elapsed >= InkDissolveView.endTime {
            view.isPaused = true
        }
    }

    // MARK: - 把贴纸拆成墨点

    /// 按比例缩放、居中放进 rect 后，每隔 spacing pt 取一个点；透明的地方不要
    static func sample(_ image: UIImage, in rect: CGRect, target: Int = 7000) -> (particles: [InkParticle], spacing: CGFloat) {
        guard image.size.width > 0, image.size.height > 0, rect.width > 0, rect.height > 0 else { return ([], 1) }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let fitted = CGRect(x: rect.midX - image.size.width * scale / 2, y: rect.midY - image.size.height * scale / 2,
                            width: image.size.width * scale, height: image.size.height * scale)
        // 大约 target 个采样点（透明处会被丢掉，实际更少）
        let spacing = max(1.6, (fitted.width * fitted.height / CGFloat(target)).squareRoot())
        let columns = max(1, Int(fitted.width / spacing))
        let rows = max(1, Int(fitted.height / spacing))

        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: raw.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                                          bytesPerRow: columns * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            // 翻成 UIKit 的坐标（左上角为原点），这样第 0 行就是图片最上面一行，也顺便处理了图片方向
            context.translateBy(x: 0, y: CGFloat(rows))
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0, y: 0, width: columns, height: rows))
            UIGraphicsPopContext()
            return true
        }
        guard drawn else { return ([], spacing) }

        var result: [InkParticle] = []
        result.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let i = (row * columns + column) * 4
                let alpha = Float(pixels[i + 3]) / 255
                guard alpha > 0.35 else { continue }
                let red = min(1, Float(pixels[i]) / 255 / alpha)
                let green = min(1, Float(pixels[i + 1]) / 255 / alpha)
                let blue = min(1, Float(pixels[i + 2]) / 255 / alpha)
                let x = fitted.minX + (CGFloat(column) + 0.5) * spacing
                let y = fitted.minY + (CGFloat(row) + 0.5) * spacing
                let seed = Self.noise(row * 7919 + column * 104_729)
                // 风从左上吹来：左上角的墨点先走，右下角的最后走
                let u = Float(column) / Float(max(columns - 1, 1))
                let v = Float(row) / Float(max(rows - 1, 1))
                let delay = 0.05 + 0.85 * (u * 0.7 + v * 0.3) + seed * 0.25
                result.append(InkParticle(origin: SIMD4(Float(x), Float(y), seed, delay),
                                          color: SIMD4(red, green, blue, alpha)))
            }
        }
        return (result, spacing)
    }

    /// 0…1 的稳定伪随机数
    private static func noise(_ n: Int) -> Float {
        var x = UInt32(truncatingIfNeeded: n) &* 747_796_405 &+ 2_891_336_453
        x = ((x >> ((x >> 28) &+ 4)) ^ x) &* 277_803_737
        x = (x >> 22) ^ x
        return Float(x) / Float(UInt32.max)
    }
}
