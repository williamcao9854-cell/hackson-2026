import CoreML
import SceneKit
import UIKit
import Vision

/// 一键生成 3D 手办：Core ML 深度模型（Apple 官方 Depth Anything V2）估算物灵每个像素的远近，
/// 再由 ReliefMeshBuilder 生成闭合网格，贴上物灵的画。所有手机都能用，完全在设备上，一秒左右。
enum ReliefModeler {
    /// 深度模型的输入尺寸
    static let canvasWidth = 518
    static let canvasHeight = 392

    private static let depthModel: VNCoreMLModel? = {
        guard let url = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc") else { return nil }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        guard let model = try? MLModel(contentsOf: url, configuration: configuration) else { return nil }
        return try? VNCoreMLModel(for: model)
    }()

    private static let cache: NSCache<NSString, SCNNode> = {
        let c = NSCache<NSString, SCNNode>()
        c.countLimit = 4
        return c
    }()

    /// 生成手办节点（已缓存则直接复制一份）。耗时操作，请在后台调用。
    static func figurineNode(for figure: UIImage, key: String) -> SCNNode? {
        if let cached = cache.object(forKey: key as NSString) { return cached.clone() }
        guard let canvas = renderCanvas(figure),
              let depth = estimateDepth(canvas.image),
              let mesh = ReliefMeshBuilder.build(.init(width: canvasWidth, height: canvasHeight,
                                                       mask: canvas.mask, depth: depth), step: 3)
        else { return nil }
        let node = SCNNode(geometry: geometry(from: mesh, texture: canvas.image))
        node.name = "figurine"
        cache.setObject(node, forKey: key as NSString)
        return node.clone()
    }

    // MARK: - 画布：把物灵居中放进模型需要的尺寸，同时得到轮廓

    private static func renderCanvas(_ figure: UIImage) -> (image: CGImage, mask: [Float])? {
        guard let cg = figure.cgImage else { return nil }
        let w = canvasWidth, h = canvasHeight
        let margin = 0.06
        let availableW = Double(w) * (1 - margin * 2)
        let availableH = Double(h) * (1 - margin * 2)
        let scale = min(availableW / Double(cg.width), availableH / Double(cg.height))
        let drawW = Double(cg.width) * scale, drawH = Double(cg.height) * scale
        let rect = CGRect(x: (Double(w) - drawW) / 2, y: (Double(h) - drawH) / 2, width: drawW, height: drawH)
        let space = CGColorSpaceCreateDeviceRGB()

        // 彩色画布：浅纸色底
        guard let color = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        color.setFillColor(UIColor(hex: 0xF4F0E8).cgColor)
        color.fill(CGRect(x: 0, y: 0, width: w, height: h))
        color.interpolationQuality = .high
        color.draw(cg, in: rect)
        guard let image = color.makeImage() else { return nil }

        // 轮廓：只画物灵，读 alpha
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: rect)
            return true
        }
        guard ok else { return nil }
        var mask = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { mask[i] = Float(pixels[i * 4 + 3]) / 255 }
        return (image, mask)
    }

    // MARK: - 深度

    private static func estimateDepth(_ image: CGImage) -> [Float]? {
        guard let model = depthModel else { return nil }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNPixelBufferObservation else { return nil }
        return read(observation.pixelBuffer)
    }

    /// 读出深度图并缩放到画布尺寸（支持 16 位和 32 位浮点灰度）
    private static func read(_ buffer: CVPixelBuffer) -> [Float]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bw = CVPixelBufferGetWidth(buffer), bh = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let w = canvasWidth, h = canvasHeight
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let sy = min(bh - 1, y * bh / h)
            let row = base.advanced(by: sy * rowBytes)
            for x in 0..<w {
                let sx = min(bw - 1, x * bw / w)
                switch format {
                case kCVPixelFormatType_OneComponent16Half, kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DisparityFloat16:
                    let bits = row.load(fromByteOffset: sx * 2, as: UInt16.self)
                    out[y * w + x] = halfToFloat(bits)
                case kCVPixelFormatType_OneComponent32Float, kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_DisparityFloat32:
                    out[y * w + x] = row.load(fromByteOffset: sx * 4, as: Float.self)
                default:
                    return nil
                }
            }
        }
        return out
    }

    /// IEEE 754 半精度 → 单精度（不依赖 Float16 类型，Intel Mac 的模拟器上也能编译）
    static func halfToFloat(_ bits: UInt16) -> Float {
        let sign: UInt32 = UInt32(bits & 0x8000) << 16
        let exponent = Int((bits >> 10) & 0x1F)
        let mantissa = UInt32(bits & 0x03FF)
        if exponent == 0 {
            // 非规格化数或 0
            let value = Float(mantissa) / 1024 * powf(2, -14)
            return sign == 0 ? value : -value
        }
        if exponent == 31 {
            return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13))
        }
        let floatExponent = UInt32(exponent - 15 + 127) << 23
        return Float(bitPattern: sign | floatExponent | (mantissa << 13))
    }

    // MARK: - SceneKit 几何体

    private static func geometry(from mesh: ReliefMesh, texture: CGImage) -> SCNGeometry {
        let vertices = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
        let uvs = mesh.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        let sources = [
            SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals),
            SCNGeometrySource(textureCoordinates: uvs),
        ]
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: sources, elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = UIImage(cgImage: texture)
        material.lightingModel = .blinn
        material.specular.contents = UIColor(white: 0.35, alpha: 1)
        material.shininess = 0.35
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }

    // MARK: - LiDAR 扫描模型

    /// 读入扫描得到的 USDZ，缩放到"最长边 = 1"并居中，和手办用同一个查看器
    static func scannedNode(at url: URL) -> SCNNode? {
        guard let scene = try? SCNScene(url: url, options: nil) else { return nil }
        let container = SCNNode()
        for child in scene.rootNode.childNodes { container.addChildNode(child) }
        let (minBound, maxBound) = container.boundingBox
        let size = SCNVector3(maxBound.x - minBound.x, maxBound.y - minBound.y, maxBound.z - minBound.z)
        let longest = max(size.x, max(size.y, size.z))
        guard longest > 0 else { return nil }
        let scale = 1 / longest
        container.scale = SCNVector3(scale, scale, scale)
        container.pivot = SCNMatrix4MakeTranslation((minBound.x + maxBound.x) / 2, (minBound.y + maxBound.y) / 2, (minBound.z + maxBound.z) / 2)
        return container
    }

    // MARK: - AR

    /// 导出成 USDZ，供 AR 快速查看摆在桌上。手办实际大小约 12 厘米。
    static func exportUSDZ(_ node: SCNNode, name: String) -> URL? {
        let scene = SCNScene()
        let holder = node.clone()
        holder.scale = SCNVector3(0.12, 0.12, 0.12)
        holder.position = SCNVector3(0, 0.06, 0)
        scene.rootNode.addChildNode(holder)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Figurines", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = name.replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = folder.appendingPathComponent("\(safeName.isEmpty ? "wuling" : safeName).usdz")
        try? FileManager.default.removeItem(at: url)
        return scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) ? url : nil
    }
}
