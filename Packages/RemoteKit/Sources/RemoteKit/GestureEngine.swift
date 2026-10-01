import Foundation

public enum GestureOutput: Equatable, Sendable {
    /// 单击、双击、长按，以及单击的连续触发
    case fire(RemoteButton, RemoteGesture)
    /// 「按住」开始
    case begin(RemoteButton)
    /// 「按住」结束
    case end(RemoteButton)
}

public struct GestureTiming: Equatable, Sendable {
    public var longPress: TimeInterval
    public var doubleTap: TimeInterval
    public var repeatDelay: TimeInterval
    public var repeatInterval: TimeInterval

    public init(longPress: TimeInterval = 0.45, doubleTap: TimeInterval = 0.28,
                repeatDelay: TimeInterval = 0.38, repeatInterval: TimeInterval = 0.07) {
        self.longPress = longPress
        self.doubleTap = doubleTap
        self.repeatDelay = repeatDelay
        self.repeatInterval = repeatInterval
    }
}

public protocol GestureTimer: AnyObject { func cancel() }

/// 定时器抽象，便于在测试中手动推进时间。
public protocol GestureClock {
    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> GestureTimer
}

public final class DispatchGestureClock: GestureClock {
    public init() {}

    private final class Item: GestureTimer {
        let work: DispatchWorkItem
        init(_ work: DispatchWorkItem) { self.work = work }
        func cancel() { work.cancel() }
    }

    public func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> GestureTimer {
        let work = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
        return Item(work)
    }
}

/// 把按钮的按下/松开转换为手势。
///
/// - 绑定了「按住」：按下即 begin，松开即 end，其它手势不生效。
/// - 只绑定了「单击」：按下立即触发，可选按住连续触发，没有额外延迟。
/// - 绑定了双击或长按：松开后才能判定单击，双击会让单击延迟一个双击间隔。
public final class GestureEngine {
    public struct Bindings: Equatable, Sendable {
        public var gestures: Set<RemoteGesture>
        public var repeatWhileHeld: Bool
        public init(gestures: Set<RemoteGesture>, repeatWhileHeld: Bool = false) {
            self.gestures = gestures
            self.repeatWhileHeld = repeatWhileHeld
        }
    }

    public var timing: GestureTiming
    public var resolver: (RemoteButton) -> Bindings
    public var onOutput: (GestureOutput) -> Void = { _ in }

    private let clock: GestureClock
    private var states: [RemoteButton: State] = [:]

    private struct State {
        var bindings: Bindings
        var isDown = false
        var holding = false
        var consumed = false
        var awaitingSecondTap = false
        var longTimer: GestureTimer?
        var doubleTimer: GestureTimer?
        var repeatTimer: GestureTimer?

        var isSimple: Bool { !bindings.gestures.contains(.doubleTap) && !bindings.gestures.contains(.longPress) }
    }

    public init(timing: GestureTiming = .init(), clock: GestureClock = DispatchGestureClock(),
                resolver: @escaping (RemoteButton) -> Bindings) {
        self.timing = timing
        self.clock = clock
        self.resolver = resolver
    }

    public func handle(_ button: RemoteButton, isDown: Bool) {
        isDown ? pressed(button) : released(button)
    }

    /// 结束所有进行中的手势（遥控器断开或停用映射时调用），避免按键卡在按下状态
    public func reset() {
        for (button, state) in states {
            state.longTimer?.cancel()
            state.doubleTimer?.cancel()
            state.repeatTimer?.cancel()
            if state.holding { onOutput(.end(button)) }
        }
        states.removeAll()
    }

    private func pressed(_ button: RemoteButton) {
        if states[button]?.isDown == true { return }
        // 正在等待第二次按下时沿用第一次按下时解析到的绑定
        var state = states[button].flatMap { $0.awaitingSecondTap ? $0 : nil } ?? State(bindings: resolver(button))
        state.isDown = true
        let gestures = state.bindings.gestures

        if gestures.contains(.hold) {
            state.holding = true
            states[button] = state
            onOutput(.begin(button))
            return
        }

        if state.isSimple {
            states[button] = state
            guard gestures.contains(.tap) else { return }
            onOutput(.fire(button, .tap))
            if state.bindings.repeatWhileHeld { scheduleRepeat(button, after: timing.repeatDelay) }
            return
        }

        if state.awaitingSecondTap {
            state.doubleTimer?.cancel()
            state.awaitingSecondTap = false
            state.consumed = true
            states[button] = state
            onOutput(.fire(button, .doubleTap))
            return
        }

        if gestures.contains(.longPress) {
            state.longTimer = clock.schedule(after: timing.longPress) { [weak self] in
                guard let self, var s = self.states[button], s.isDown, !s.consumed else { return }
                s.consumed = true
                self.states[button] = s
                self.onOutput(.fire(button, .longPress))
            }
        }
        states[button] = state
    }

    private func released(_ button: RemoteButton) {
        guard var state = states[button], state.isDown else { return }
        state.isDown = false
        state.longTimer?.cancel()
        state.repeatTimer?.cancel()

        if state.holding {
            states[button] = nil
            onOutput(.end(button))
            return
        }
        if state.isSimple || state.consumed {
            states[button] = nil
            return
        }

        let gestures = state.bindings.gestures
        if gestures.contains(.doubleTap) {
            state.awaitingSecondTap = true
            state.doubleTimer = clock.schedule(after: timing.doubleTap) { [weak self] in
                guard let self, let s = self.states[button], s.awaitingSecondTap, !s.isDown else { return }
                self.states[button] = nil
                if s.bindings.gestures.contains(.tap) { self.onOutput(.fire(button, .tap)) }
            }
            states[button] = state
        } else {
            states[button] = nil
            if gestures.contains(.tap) { onOutput(.fire(button, .tap)) }
        }
    }

    private func scheduleRepeat(_ button: RemoteButton, after interval: TimeInterval) {
        states[button]?.repeatTimer = clock.schedule(after: interval) { [weak self] in
            guard let self, let s = self.states[button], s.isDown else { return }
            self.onOutput(.fire(button, .tap))
            self.scheduleRepeat(button, after: self.timing.repeatInterval)
        }
    }
}
