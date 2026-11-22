import Foundation

/// 水面的物理波纹：在一张小网格上解带阻尼的二维波动方程，每一帧把高度场交给水面着色器。
///
/// 河灯落水、手指轻点，都是往网格上"滴一滴水"；之后波纹自己扩散、在岸边反射、相互叠加、慢慢平息。
/// 网格比屏幕粗得多（默认 72 × 18），着色器里做双线性插值，CPU 每秒只算几十步，几乎不花时间。
final class RippleField {
    let columns: Int
    let rows: Int

    private var current: [Float]
    private var previous: [Float]
    private var lastTime: TimeInterval?
    /// 还有没有在动（全静止时不再计算，直接返回）
    private var energetic = false

    /// 每一步的阻尼：越接近 1，波纹传得越远
    var damping: Float = 0.972
    /// 每秒推进多少步：决定波纹扩散的速度
    var stepsPerSecond: Double = 30

    init(columns: Int = 72, rows: Int = 18) {
        precondition(columns >= 3 && rows >= 3)
        self.columns = columns
        self.rows = rows
        current = Array(repeating: 0, count: columns * rows)
        previous = current
    }

    /// 在水面某处落下一滴。x、y 是 0…1 的相对位置（y = 0 是水线）。
    func drop(x: Double, y: Double, strength: Float = 1, radius: Double = 2.2) {
        let cx = min(max(x, 0), 1) * Double(columns - 1)
        let cy = min(max(y, 0), 1) * Double(rows - 1)
        let reach = Int(radius.rounded(.up))
        for row in max(1, Int(cy) - reach)...min(rows - 2, Int(cy) + reach) {
            for column in max(1, Int(cx) - reach)...min(columns - 2, Int(cx) + reach) {
                let dx = Double(column) - cx, dy = Double(row) - cy
                let d2 = (dx * dx + dy * dy) / (radius * radius)
                guard d2 < 1 else { continue }
                // 中间凹下去，边缘平滑：(1 - d²)²
                current[row * columns + column] -= strength * Float((1 - d2) * (1 - d2))
            }
        }
        energetic = true
    }

    private var lastWake: TimeInterval = -.infinity

    /// 河灯漂过时，身后不断泛起很轻的水纹：每隔一会儿在它脚下滴一小滴
    func wake(x: Double, y: Double, at time: TimeInterval, every interval: TimeInterval = 0.45, strength: Float = 0.16) {
        guard time - lastWake >= interval else { return }
        lastWake = time
        drop(x: x, y: y, strength: strength, radius: 1.6)
    }

    /// 推进到某个时刻，返回此刻的高度场（按行排列，columns × rows）
    func heights(at time: TimeInterval) -> [Float] {
        guard let last = lastTime else {
            lastTime = time
            return current
        }
        let step = 1 / stepsPerSecond
        var steps = Int((time - last) / step)
        // SwiftUI 可能用同一个（甚至更早的）时刻再算一遍：不倒退，原样返回
        guard steps > 0 else { return current }
        if steps > 6 {
            // 切到后台或掉帧太久：不追赶，免得一下子算很多步
            steps = 6
            lastTime = time
        } else {
            lastTime = last + Double(steps) * step
        }
        if energetic {
            for _ in 0..<steps { advance() }
        }
        return current
    }

    /// 网格上最大的起伏（测试和"是否已经平息"用）
    var peak: Float { current.reduce(0) { max($0, abs($1)) } }

    private func advance() {
        // 经典的离散波动方程：新 = 四邻平均 × 2 − 上一步，再乘阻尼。边界固定为 0，波纹碰到岸会反射回来。
        var next = previous
        var maximum: Float = 0
        for row in 1..<(rows - 1) {
            let base = row * columns
            for column in 1..<(columns - 1) {
                let i = base + column
                let value = ((current[i - 1] + current[i + 1] + current[i - columns] + current[i + columns]) * 0.5
                    - previous[i]) * damping
                next[i] = value
                maximum = max(maximum, abs(value))
            }
        }
        previous = current
        current = next
        if maximum < 0.003 {
            // 已经平息：清零，停止计算
            for i in current.indices {
                current[i] = 0
                previous[i] = 0
            }
            energetic = false
        }
    }
}
