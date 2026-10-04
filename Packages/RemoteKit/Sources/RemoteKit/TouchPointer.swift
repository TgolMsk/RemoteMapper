import AppKit
import CoreGraphics

/// 鼠标按键
public enum MouseButton: String, CaseIterable, Codable, Sendable {
    case left, right, middle

    public var displayName: String {
        switch self {
        case .left: L10n.text("左键")
        case .right: L10n.text("右键")
        case .middle: L10n.text("中键")
        }
    }
}

/// 滚动所处的阶段，对应触控板滚动事件的 scrollPhase 与 momentumPhase。
/// 带上阶段后 Safari、Chrome 会按触控板处理：滚动更顺滑，到边缘有回弹
public enum ScrollPhase: Equatable, Sendable {
    case began, changed, ended
    case momentumBegan, momentum, momentumEnded
}

/// 鼠标事件的出口。实际使用 CGPointerOutput 合成 CGEvent，测试中换成记录器
public protocol PointerOutput: AnyObject {
    /// 光标相对移动，单位像素，y 向下；dragging 为正按住的鼠标键
    func move(dx: Double, dy: Double, dragging: MouseButton?)
    func button(_ button: MouseButton, isDown: Bool, clickCount: Int)
    /// 像素滚动，正值显示上方 / 左侧的内容（与滚轮向上一致）
    func scroll(dx: Double, dy: Double, phase: ScrollPhase)
}

/// 触控鼠标：把触控面上单指的相对位移转换为光标移动，并管理鼠标按键的按住状态。
///
/// - 移动带加速：手指慢时精细定位，快时一次划得更远。
/// - 右侧滚动区：从触控面右侧区域开始、上下移动的触摸当作滚轮，内容跟着手指走，松手后带惯性；横着划仍是移动光标。
/// - 外圈转盘：从外圈（右侧滚动区以外）开始、沿圆周移动的触摸当作滚轮，顺时针向下、逆时针向上；往里或往外划仍是移动光标。
/// - 有鼠标键按住时移动即拖动；滚轮状态下移动改为滚动，内容跟随手指，松手后按速度惯性滑行。
/// - 实体按键按下后短暂冻结移动：按压触控板时手指会轻微滑动，否则光标会在点击瞬间跑偏。
/// - 可选轻点点按：短促且几乎不移动的触摸视为左键单击。
public final class TouchPointer {
    public var settings: TouchSettings
    public let output: PointerOutput
    /// 滚轮状态：为 true 时触控移动改为滚动
    public var isScrolling = false {
        didSet {
            guard isScrolling != oldValue else { return }
            endScrollGesture()
            stopMomentum()
            remainder = (0, 0)
            onScrollingChange(isScrolling)
        }
    }
    /// 光标与滚轮切换时通知界面
    public var onScrollingChange: (Bool) -> Void = { _ in }
    public private(set) var heldButtons: [MouseButton] = []

    /// 慢速与快速移动时，划过整个触控面对应的光标像素
    var slowGain = 600.0
    var fastGain = 2000.0
    /// 达到最大加速的手指速度：每秒划过触控面的倍数
    var accelerationSpeed = 2.5
    var scrollGain = 900.0
    /// 惯性滚动每帧（1/60 秒）保留的速度比例，以及启动与停止惯性的速度（像素 / 秒）
    var momentumDecay = 0.95
    var momentumStartSpeed = 250.0
    var momentumStopSpeed = 20.0
    var tapMaxDuration: TimeInterval = 0.22
    var tapMaxTravel = 0.03
    var settleDuration: TimeInterval = 0.15
    var doubleClickInterval: TimeInterval = NSEvent.doubleClickInterval
    /// 从外圈开始的触摸，移动这么远后按方向判定是转盘还是移动光标
    var ringDecisionDistance = 0.035
    /// 切向位移至少是径向的多少倍才算沿圆周转动
    var ringTangentialRatio = 1.2
    /// 转盘每转过 1 弧度滚动的像素
    var ringGain = 190.0

    private enum TouchKind {
        case pointer
        /// 外圈转盘
        case ring
        /// 右侧滚动区
        case strip
        /// 从外圈开始，还没走够距离判断是转盘还是移动光标
        case ringCandidate
        /// 从右侧滚动区开始，还没走够距离判断是上下滚动还是移动光标
        case stripCandidate
    }

    private struct Track {
        let id: Int32
        let startTime: TimeInterval
        let startX: Double
        let startY: Double
        var x: Double
        var y: Double
        var time: TimeInterval
        var kind: TouchKind
        var travel = 0.0
        var suppressed = false
        /// 判定方向前积累的位移，判定为移动光标后一次补发
        var pending = (dx: 0.0, dy: 0.0, dt: 0.0)
        var lastAngle = 0.0
    }

    private var track: Track?
    /// 不足一个像素的位移累积到下一帧，慢速移动才不会丢失
    private var remainder = (x: 0.0, y: 0.0)
    private var pendingSettle = false
    private var settleUntil: TimeInterval = 0
    private var lastClick: (button: MouseButton, time: TimeInterval, count: Int)?
    /// 上次点击后光标移动的像素，移远了就不再算连击
    private var travelSinceClick = 0.0
    /// 当前这次触摸是否已发出滚动开始
    private var scrollGestureActive = false
    /// 手指滚动的速度（像素 / 秒，已平滑）与最后一次有位移的时间，用于松手后的惯性
    private var scrollVelocity = (x: 0.0, y: 0.0)
    private var lastScrollMove: TimeInterval = 0
    private var momentumTimer: GestureTimer?
    private var momentumActive = false
    private let now: () -> TimeInterval
    private let clock: GestureClock

    public init(settings: TouchSettings = TouchSettings(), output: PointerOutput,
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                clock: GestureClock = DispatchGestureClock()) {
        self.settings = settings
        self.output = output
        self.now = now
        self.clock = clock
    }

    public func handle(_ frame: TouchFrame) {
        if pendingSettle {
            // 冻结时长按触控帧的时钟计算，与按键事件的时钟无关
            settleUntil = frame.timestamp + settleDuration
            pendingSettle = false
        }
        let active = frame.contacts.filter(\.isTouching)
        guard let contact = track.flatMap({ t in active.first { $0.id == t.id } }) ?? active.first else {
            if let finished = track { finish(finished, at: frame.timestamp) }
            track = nil
            return
        }
        guard var t = track, t.id == contact.id else {
            if let finished = track { finish(finished, at: frame.timestamp) }
            // 手指放上去就停住惯性，和触控板一致
            stopMomentum()
            track = Track(id: contact.id, startTime: frame.timestamp, startX: contact.x, startY: contact.y,
                          x: contact.x, y: contact.y, time: frame.timestamp, kind: startKind(x: contact.x, y: contact.y))
            remainder = (0, 0)
            scrollVelocity = (0, 0)
            return
        }
        let dx = contact.x - t.x
        let dy = contact.y - t.y
        let dt = max(frame.timestamp - t.time, 1.0 / 250)
        t.x = contact.x
        t.y = contact.y
        t.time = frame.timestamp
        t.travel += hypot(dx, dy)
        track = t
        guard frame.timestamp >= settleUntil else { return }
        if isScrolling {
            emitScroll(dx: dx, dy: dy, dt: dt, at: frame.timestamp)
            return
        }
        switch t.kind {
        case .pointer:
            emitMove(dx: dx, dy: dy, dt: dt)
        case .ring:
            emitRing(x: contact.x, y: contact.y)
        case .strip:
            emitScroll(dx: 0, dy: dy, dt: dt, at: frame.timestamp)
        case .ringCandidate, .stripCandidate:
            t.pending = (t.pending.dx + dx, t.pending.dy + dy, t.pending.dt + dt)
            guard hypot(t.pending.dx, t.pending.dy) >= ringDecisionDistance else {
                track = t
                return
            }
            if t.kind == .stripCandidate {
                // 上下为主是滚动，横着为主是移动光标；判定前积累的位移一并补发
                if abs(t.pending.dy) >= ringTangentialRatio * abs(t.pending.dx) {
                    t.kind = .strip
                    track = t
                    emitScroll(dx: 0, dy: t.pending.dy, dt: t.pending.dt, at: frame.timestamp)
                } else {
                    t.kind = .pointer
                    track = t
                    emitMove(dx: t.pending.dx, dy: t.pending.dy, dt: t.pending.dt)
                }
                return
            }
            // 起点相对中心的方向为径向，与之垂直的为切向
            let rx = t.startX - 0.5, ry = t.startY - 0.5
            let length = hypot(rx, ry)
            let radial = (t.pending.dx * rx + t.pending.dy * ry) / length
            let tangential = (t.pending.dx * ry - t.pending.dy * rx) / length
            if abs(tangential) >= ringTangentialRatio * abs(radial) {
                t.kind = .ring
                t.lastAngle = atan2(ry, rx)
                track = t
                emitRing(x: contact.x, y: contact.y)
            } else {
                t.kind = .pointer
                track = t
                emitMove(dx: t.pending.dx, dy: t.pending.dy, dt: t.pending.dt)
            }
        }
    }

    /// 起手位置决定这次触摸可能的用途：右侧滚动区优先于外圈；按住鼠标键时一律移动（拖动）
    private func startKind(x: Double, y: Double) -> TouchKind {
        guard heldButtons.isEmpty else { return .pointer }
        if settings.sideScroll, x >= 1 - settings.sideScrollWidth { return .stripCandidate }
        // 外圈从离中心 0.5 - ringWidth 处开始（触控面边长为 1）
        if settings.ringScroll, hypot(x - 0.5, y - 0.5) >= 0.5 - settings.ringWidth { return .ringCandidate }
        return .pointer
    }

    /// 转盘：按转过的角度滚动，逆时针为正（显示上方内容），顺时针为负（显示下方内容）
    private func emitRing(x: Double, y: Double) {
        guard var t = track else { return }
        let angle = atan2(y - 0.5, x - 0.5)
        var delta = angle - t.lastAngle
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        t.lastAngle = angle
        track = t
        guard let (_, pixels) = takeWhole(0, delta * ringGain * settings.pointerSpeed) else { return }
        output.scroll(dx: 0, dy: pixels, phase: scrollGestureActive ? .changed : .began)
        scrollGestureActive = true
    }

    /// 实体按键按下时调用：短暂冻结移动，这次触摸也不再算轻点
    public func noteButtonPress() {
        pendingSettle = true
        track?.suppressed = true
    }

    public func press(_ button: MouseButton) {
        guard !heldButtons.contains(button) else { return }
        heldButtons.append(button)
        output.button(button, isDown: true, clickCount: nextClickCount(button))
    }

    public func release(_ button: MouseButton) {
        guard let index = heldButtons.firstIndex(of: button) else { return }
        heldButtons.remove(at: index)
        let count = lastClick?.button == button ? lastClick?.count ?? 1 : 1
        output.button(button, isDown: false, clickCount: count)
    }

    public func click(_ button: MouseButton) {
        press(button)
        release(button)
    }

    /// 松开所有按住的鼠标键并结束滚动，切换模式或遥控器断开时调用
    public func reset() {
        for button in heldButtons.reversed() { release(button) }
        endScrollGesture()
        stopMomentum()
        isScrolling = false
        track = nil
        remainder = (0, 0)
    }

    private func emitMove(dx: Double, dy: Double, dt: TimeInterval) {
        let distance = hypot(dx, dy)
        guard distance > 0 else { return }
        let ratio = min(distance / dt / accelerationSpeed, 1)
        let gain = (slowGain + (fastGain - slowGain) * ratio) * settings.pointerSpeed
        // 触控面 y 向上，屏幕 y 向下
        guard let (x, y) = takeWhole(dx * gain, -dy * gain) else { return }
        travelSinceClick += hypot(x, y)
        output.move(dx: x, dy: y, dragging: heldButtons.first)
    }

    private func emitScroll(dx: Double, dy: Double, dt: TimeInterval, at time: TimeInterval) {
        let gain = scrollGain * settings.pointerSpeed
        // 内容跟随手指：手指上移显示下方内容（滚轮负值），手指右移显示左侧内容（正值）
        let px = dx * gain, py = -dy * gain
        if px != 0 || py != 0 {
            scrollVelocity = (0.5 * scrollVelocity.x + 0.5 * px / dt, 0.5 * scrollVelocity.y + 0.5 * py / dt)
            lastScrollMove = time
        }
        guard let (x, y) = takeWhole(px, py) else { return }
        output.scroll(dx: x, dy: y, phase: scrollGestureActive ? .changed : .began)
        scrollGestureActive = true
    }

    private func endScrollGesture() {
        guard scrollGestureActive else { return }
        scrollGestureActive = false
        output.scroll(dx: 0, dy: 0, phase: .ended)
    }

    /// 松手后按速度继续滚动，每帧衰减，速度足够低时结束
    private func startMomentum(at time: TimeInterval) {
        // 抬起前手指已经停住的，不再滑行
        guard time - lastScrollMove <= 0.06, hypot(scrollVelocity.x, scrollVelocity.y) >= momentumStartSpeed else { return }
        var velocity = scrollVelocity
        let interval = 1.0 / 60
        func step() {
            velocity = (velocity.x * momentumDecay, velocity.y * momentumDecay)
            guard hypot(velocity.x, velocity.y) >= momentumStopSpeed else {
                momentumTimer = nil
                stopMomentum()
                return
            }
            if let (x, y) = takeWhole(velocity.x * interval, velocity.y * interval) {
                output.scroll(dx: x, dy: y, phase: momentumActive ? .momentum : .momentumBegan)
                momentumActive = true
            }
            momentumTimer = clock.schedule(after: interval) { [weak self] in if self != nil { step() } }
        }
        remainder = (0, 0)
        momentumTimer = clock.schedule(after: interval) { [weak self] in if self != nil { step() } }
    }

    private func stopMomentum() {
        momentumTimer?.cancel()
        momentumTimer = nil
        if momentumActive {
            momentumActive = false
            output.scroll(dx: 0, dy: 0, phase: .momentumEnded)
        }
    }

    /// 加上累积的余量后取整，余下的小数留到下一帧
    private func takeWhole(_ x: Double, _ y: Double) -> (Double, Double)? {
        let total = (x: x + remainder.x, y: y + remainder.y)
        let whole = (x: total.x.rounded(.towardZero), y: total.y.rounded(.towardZero))
        remainder = (total.x - whole.x, total.y - whole.y)
        return whole.x == 0 && whole.y == 0 ? nil : whole
    }

    private func finish(_ t: Track, at time: TimeInterval) {
        if t.kind == .ring, !isScrolling {
            // 转盘停手即停，不做惯性
            endScrollGesture()
            return
        }
        if t.kind == .strip, !isScrolling {
            endScrollGesture()
            startMomentum(at: time)
            return
        }
        if isScrolling, scrollGestureActive {
            endScrollGesture()
            startMomentum(at: time)
            return
        }
        guard settings.tapToClick, !isScrolling, !t.suppressed, heldButtons.isEmpty,
              time - t.startTime <= tapMaxDuration, t.travel <= tapMaxTravel else { return }
        click(.left)
    }

    private func nextClickCount(_ button: MouseButton) -> Int {
        let time = now()
        var count = 1
        if let last = lastClick, last.button == button, time - last.time <= doubleClickInterval, travelSinceClick <= 4 {
            count = min(last.count + 1, 3)
        }
        lastClick = (button, time, count)
        travelSinceClick = 0
        return count
    }
}

/// 用 CGEvent 合成鼠标事件。需要「辅助功能」权限，否则事件会被系统静默丢弃。
public final class CGPointerOutput: PointerOutput {
    private let source = CGEventSource(stateID: .hidSystemState)

    public init() {}

    public func move(dx: Double, dy: Double, dragging: MouseButton?) {
        let current = CGEvent(source: nil)?.location ?? .zero
        let target = Self.clamp(CGPoint(x: current.x + dx, y: current.y + dy), from: current)
        let type: CGEventType = switch dragging {
        case nil: .mouseMoved
        case .left: .leftMouseDragged
        case .right: .rightMouseDragged
        case .middle: .otherMouseDragged
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target,
                                  mouseButton: dragging?.cgButton ?? .left) else { return }
        // 游戏等读取原始位移的 App 依赖这两个字段
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        post(event)
    }

    public func button(_ button: MouseButton, isDown: Bool, clickCount: Int) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType = switch (button, isDown) {
        case (.left, true): .leftMouseDown
        case (.left, false): .leftMouseUp
        case (.right, true): .rightMouseDown
        case (.right, false): .rightMouseUp
        case (.middle, true): .otherMouseDown
        case (.middle, false): .otherMouseUp
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location,
                                  mouseButton: button.cgButton) else { return }
        // App 靠点击计数识别双击、三击
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        post(event)
    }

    public func scroll(dx: Double, dy: Double, phase: ScrollPhase) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return }
        // 取值同 CGScrollPhase（开始 1、进行中 2、结束 4）与 CGMomentumScrollPhase（开始 1、进行中 2、结束 3）
        let (scrollPhase, momentumPhase): (Int64, Int64) = switch phase {
        case .began: (1, 0)
        case .changed: (2, 0)
        case .ended: (4, 0)
        case .momentumBegan: (0, 1)
        case .momentum: (0, 2)
        case .momentumEnded: (0, 3)
        }
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        post(event)
    }

    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: KeyboardSynth.eventMarker)
        event.post(tap: .cghidEventTap)
    }

    /// 落在任一显示器内就直接使用，否则夹在当前所在显示器的边界内
    static func clamp(_ point: CGPoint, from current: CGPoint) -> CGPoint {
        let displays = activeDisplayBounds()
        if displays.contains(where: { $0.contains(point) }) { return point }
        guard let bounds = displays.first(where: { $0.contains(current) }) ?? displays.first else { return point }
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX - 1),
                       y: min(max(point.y, bounds.minY), bounds.maxY - 1))
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }
}

extension MouseButton {
    var cgButton: CGMouseButton {
        switch self {
        case .left: .left
        case .right: .right
        case .middle: .center
        }
    }
}
