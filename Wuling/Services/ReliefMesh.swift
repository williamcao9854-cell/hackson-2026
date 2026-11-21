import Foundation

/// 从"轮廓 + 深度图"生成一个闭合的 3D 手办网格。纯计算，不依赖任何 Apple 框架。
///
/// - 正面：按深度起伏（离镜头越近越凸）
/// - 背面：同样的起伏、浅一些，像手办圆润的背
/// - 边缘：深度向轮廓收拢到 0，正反两面在边上合拢；再用一圈侧壁把缝补上
struct ReliefMesh {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    /// 贴图坐标（0...1，左上为原点）
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    var triangleCount: Int { indices.count / 3 }
}

enum ReliefMeshBuilder {
    /// 输入：同尺寸的轮廓（0...1，>0.5 视为物体）和深度（任意范围，越大越近）。行优先，左上为原点。
    struct Field {
        let width: Int
        let height: Int
        let mask: [Float]
        let depth: [Float]
    }

    /// - step: 网格采样间隔（像素），越小越细
    /// - frontDepth / backDepth: 正面、背面最大起伏，单位是"物体最长边 = 1"
    static func build(_ field: Field, step: Int = 2, frontDepth: Float = 0.24, backDepth: Float = 0.14) -> ReliefMesh? {
        let w = field.width, h = field.height
        guard w > 2, h > 2, field.mask.count == w * h, field.depth.count == w * h, step >= 1 else { return nil }

        // 1. 物体的包围盒与深度范围
        var minX = w, minY = h, maxX = -1, maxY = -1
        var dMin = Float.greatestFiniteMagnitude, dMax = -Float.greatestFiniteMagnitude
        for y in 0..<h {
            for x in 0..<w where field.mask[y * w + x] > 0.5 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                let d = field.depth[y * w + x]
                if d.isFinite {
                    dMin = min(dMin, d); dMax = max(dMax, d)
                }
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        let dRange = dMax - dMin

        // 2. 模糊后的轮廓：离边缘越远越接近 1，用来让起伏在边缘收拢
        let boxWidth = maxX - minX + 1, boxHeight = maxY - minY + 1
        let radius = max(3, min(boxWidth, boxHeight) / 16)
        let soft = boxBlur(field.mask, width: w, height: h, radius: radius)

        func relief(_ x: Int, _ y: Int) -> Float {
            let i = y * w + x
            guard field.mask[i] > 0.5 else { return 0 }
            let d = field.depth[i]
            let normalized: Float = dRange > 1e-6 && d.isFinite ? (d - dMin) / dRange : 0.5
            let falloff = smoothstep(0.5, 0.95, soft[i])
            return (0.3 + 0.7 * normalized) * falloff
        }

        // 3. 网格
        let xs = Array(stride(from: minX, through: maxX, by: step))
        let ys = Array(stride(from: minY, through: maxY, by: step))
        let nx = xs.count, ny = ys.count
        guard nx >= 2, ny >= 2 else { return nil }
        let scale = 1 / Float(max(boxWidth, boxHeight))
        let centerX = Float(minX + maxX) / 2, centerY = Float(minY + maxY) / 2

        var mesh = ReliefMesh()
        mesh.positions.reserveCapacity(nx * ny * 2)
        var inside = [Bool](repeating: false, count: nx * ny)
        var frontZ = [Float](repeating: 0, count: nx * ny)
        for j in 0..<ny {
            for i in 0..<nx {
                let px = xs[i], py = ys[j]
                let k = j * nx + i
                inside[k] = field.mask[py * w + px] > 0.5
                frontZ[k] = relief(px, py)
            }
        }

        // 正面、背面的顶点（背面紧接在正面之后）
        for side in 0..<2 {
            let depthScale: Float = side == 0 ? frontDepth : -backDepth
            for j in 0..<ny {
                for i in 0..<nx {
                    let px = xs[i], py = ys[j]
                    let k = j * nx + i
                    let x = (Float(px) - centerX) * scale
                    let y = -(Float(py) - centerY) * scale
                    mesh.positions.append(SIMD3(x, y, frontZ[k] * depthScale))
                    mesh.uvs.append(SIMD2(Float(px) / Float(w - 1), Float(py) / Float(h - 1)))
                    mesh.normals.append(normal(i: i, j: j, nx: nx, ny: ny, z: frontZ, depthScale: depthScale,
                                               spacing: Float(step) * scale, back: side == 1))
                }
            }
        }

        // 4. 三角形：四个角都在物体内的格子才画
        let back = UInt32(nx * ny)
        var included = [Bool](repeating: false, count: (nx - 1) * (ny - 1))
        for j in 0..<(ny - 1) {
            for i in 0..<(nx - 1) {
                let a = j * nx + i, b = a + 1, c = a + nx, d = c + 1
                guard inside[a], inside[b], inside[c], inside[d] else { continue }
                included[j * (nx - 1) + i] = true
                let ua = UInt32(a), ub = UInt32(b), uc = UInt32(c), ud = UInt32(d)
                // 正面（从 +z 看逆时针）
                mesh.indices += [ua, uc, ud, ua, ud, ub]
                // 背面（反过来）
                mesh.indices += [back + ua, back + ud, back + uc, back + ua, back + ub, back + ud]
            }
        }
        guard !mesh.indices.isEmpty else { return nil }

        // 5. 侧壁：物体边缘处，把正面和背面的边连起来，补上缝
        func cellIncluded(_ i: Int, _ j: Int) -> Bool {
            guard i >= 0, j >= 0, i < nx - 1, j < ny - 1 else { return false }
            return included[j * (nx - 1) + i]
        }
        func wall(_ p: Int, _ q: Int) {
            let up = UInt32(p), uq = UInt32(q)
            mesh.indices += [up, back + up, uq, uq, back + up, back + uq]
        }
        for j in 0..<(ny - 1) {
            for i in 0..<(nx - 1) where cellIncluded(i, j) {
                let a = j * nx + i, b = a + 1, c = a + nx, d = c + 1
                if !cellIncluded(i, j - 1) { wall(a, b) }   // 上边
                if !cellIncluded(i, j + 1) { wall(d, c) }   // 下边
                if !cellIncluded(i - 1, j) { wall(c, a) }   // 左边
                if !cellIncluded(i + 1, j) { wall(b, d) }   // 右边
            }
        }
        return mesh
    }

    // MARK: - 工具

    static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// 可分离的方框模糊（先横后竖），O(像素数)
    static func boxBlur(_ input: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        guard radius > 0 else { return input }
        var horizontal = [Float](repeating: 0, count: input.count)
        let window = Float(radius * 2 + 1)
        for y in 0..<height {
            let row = y * width
            var sum: Float = 0
            for x in -radius...radius { sum += input[row + min(width - 1, max(0, x))] }
            for x in 0..<width {
                horizontal[row + x] = sum / window
                let removeX = min(width - 1, max(0, x - radius))
                let addX = min(width - 1, max(0, x + radius + 1))
                sum += input[row + addX] - input[row + removeX]
            }
        }
        var output = [Float](repeating: 0, count: input.count)
        for x in 0..<width {
            var sum: Float = 0
            for y in -radius...radius { sum += horizontal[min(height - 1, max(0, y)) * width + x] }
            for y in 0..<height {
                output[y * width + x] = sum / window
                let removeY = min(height - 1, max(0, y - radius))
                let addY = min(height - 1, max(0, y + radius + 1))
                sum += horizontal[addY * width + x] - horizontal[removeY * width + x]
            }
        }
        return output
    }

    /// 由相邻格点的高度差估算法线
    private static func normal(i: Int, j: Int, nx: Int, ny: Int, z: [Float], depthScale: Float,
                               spacing: Float, back: Bool) -> SIMD3<Float> {
        let left = z[j * nx + max(0, i - 1)] * depthScale
        let right = z[j * nx + min(nx - 1, i + 1)] * depthScale
        let up = z[max(0, j - 1) * nx + i] * depthScale
        let down = z[min(ny - 1, j + 1) * nx + i] * depthScale
        let dzdx = (right - left) / (2 * spacing)
        // 行号向下增加，而 y 向上增加
        let dzdy = (up - down) / (2 * spacing)
        let n: SIMD3<Float> = back ? SIMD3(dzdx, dzdy, -1) : SIMD3(-dzdx, -dzdy, 1)
        let length = (n * n).sum().squareRoot()
        return length > 0 ? n / length : SIMD3(0, 0, back ? -1 : 1)
    }
}
