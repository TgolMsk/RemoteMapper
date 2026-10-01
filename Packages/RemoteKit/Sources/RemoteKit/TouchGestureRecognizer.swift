import Foundation

/// 把触点序列识别为滑动或转动。
///
/// - 转动：手指在外圈（距中心超过 ringRadius）移动，累计转角超过阈值，且轨迹明显弯曲（排除贴边的直线滑动），
///   之后每转过 rotationStep 度触发一次，直到抬起。
/// - 滑动：抬起时未进入转动、用时不长、位移超过阈值且主方向明显。
/// - 触摸过程中发生了物理按压（按下触控板或方向键）则整次触摸不识别，避免按键时误触发滑动。
public final class TouchGestureRecognizer {
    public var settings: TouchSettings
    public var onGesture: (TouchGesture) -> Void = { _ in }

    public var ringRadius = 0.24
    public var maxSwipeDuration: TimeInterval = 0.9
    /// 主方向位移至少是另一方向的多少倍
    public var axisRatio = 1.4
    /// 轨迹偏离起止连线的最小距离，用于区分弧线与直线
    public var minimumSagitta = 0.05

    private var track: Track?

    private struct Track {
        let id: Int32
        let start: (x: Double, y: Double, time: TimeInterval)
        var last: (x: Double, y: Double, time: TimeInterval)
        var path: [(x: Double, y: Double)]
        var lastAngle: Double?
        var accumulated = 0.0
        var isRotating = false
        var isSuppressed = false
    }

    public init(settings: TouchSettings = TouchSettings()) {
        self.settings = settings
    }

    /// 物理按压发生时调用：当前这次触摸不再识别为手势
    public func suppressCurrentTouch() {
        track?.isSuppressed = true
    }

    public func reset() {
        track = nil
    }

    public func handle(_ frame: TouchFrame) {
        let active = frame.contacts.filter(\.isTouching)
        let current = track.flatMap { t in active.first { $0.id == t.id } } ?? active.first

        guard let contact = current else {
            if let finished = track { finish(finished) }
            track = nil
            return
        }

        if track?.id != contact.id {
            if let finished = track { finish(finished) }
            track = Track(id: contact.id, start: (contact.x, contact.y, frame.timestamp),
                          last: (contact.x, contact.y, frame.timestamp), path: [(contact.x, contact.y)])
        }
        update(with: contact, time: frame.timestamp)
    }

    private func update(with contact: TouchContact, time: TimeInterval) {
        guard var t = track else { return }
        t.last = (contact.x, contact.y, time)
        t.path.append((contact.x, contact.y))
        if t.path.count > 240 { t.path.removeFirst(t.path.count - 240) }

        let dx = contact.x - 0.5
        let dy = contact.y - 0.5
        if hypot(dx, dy) >= ringRadius {
            let angle = atan2(dy, dx)
            if let previous = t.lastAngle {
                var delta = angle - previous
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }
                t.accumulated += delta
            }
            t.lastAngle = angle
        } else {
            t.lastAngle = nil
        }

        let step = settings.rotationStep * .pi / 180
        if !t.isRotating, !t.isSuppressed, abs(t.accumulated) >= max(step, .pi / 4), sagitta(of: t) >= minimumSagitta {
            t.isRotating = true
        }
        // 先写回再触发，回调里可能会读取识别器状态
        var ticks: [TouchGesture] = []
        if t.isRotating, !t.isSuppressed {
            while abs(t.accumulated) >= step {
                // y 轴向上时，角度减小即顺时针
                ticks.append(t.accumulated < 0 ? .rotateClockwise : .rotateCounterclockwise)
                t.accumulated -= t.accumulated < 0 ? -step : step
            }
        }
        track = t
        ticks.forEach(onGesture)
    }

    private func finish(_ t: Track) {
        guard !t.isRotating, !t.isSuppressed, t.last.time - t.start.time <= maxSwipeDuration else { return }
        let dx = t.last.x - t.start.x
        let dy = t.last.y - t.start.y
        if abs(dx) >= settings.swipeDistance, abs(dx) >= abs(dy) * axisRatio {
            onGesture(dx > 0 ? .swipeRight : .swipeLeft)
        } else if abs(dy) >= settings.swipeDistance, abs(dy) >= abs(dx) * axisRatio {
            onGesture(dy > 0 ? .swipeUp : .swipeDown)
        }
    }

    /// 轨迹上的点到起止连线的最大距离
    private func sagitta(of t: Track) -> Double {
        let ax = t.start.x, ay = t.start.y
        let bx = t.last.x, by = t.last.y
        let length = hypot(bx - ax, by - ay)
        guard length > 0.001 else { return t.path.map { hypot($0.x - ax, $0.y - ay) }.max() ?? 0 }
        return t.path.map { abs((bx - ax) * (ay - $0.y) - (ax - $0.x) * (by - ay)) / length }.max() ?? 0
    }
}
