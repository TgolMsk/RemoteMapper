import AppKit
import Observation

public struct LogEntry: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case action, passthrough, preview, error }

    public let id = UUID()
    public let date: Date
    public let button: RemoteButton?
    public let gesture: RemoteGesture?
    public let touch: TouchGesture?
    public let title: String
    public let kind: Kind

    public init(date: Date = Date(), button: RemoteButton?, gesture: RemoteGesture?, touch: TouchGesture? = nil,
                title: String, kind: Kind) {
        self.date = date
        self.button = button
        self.gesture = gesture
        self.touch = touch
        self.title = title
        self.kind = kind
    }
}

/// 串起设备、手势识别、配置解析与动作执行。
@Observable
public final class RemoteEngine {
    public let device: RemoteDevice
    /// 官网版为 MultitouchSupport 触控面；App Store 版为 nil
    public let touch: (any TouchSource)?
    public let battery: BatteryMonitor
    public let dictation = VoiceDictation()
    public let store: ConfigStore
    @ObservationIgnored public let runner = ActionRunner()
    @ObservationIgnored public let interceptor = MediaKeyInterceptor()
    /// 触控鼠标：鼠标模式下由触控面驱动光标，鼠标按键动作也通过它执行
    @ObservationIgnored public let pointer: TouchPointer

    public private(set) var frontmostBundleID: String?
    /// 鼠标模式下触控板是否处于滚轮状态
    public private(set) var isPointerScrolling = false
    public private(set) var log: [LogEntry] = []
    public private(set) var interceptorRunning = false

    /// 为 true 时只记录、不执行动作（设置窗口位于前台时使用，避免把按键打进设置界面）
    @ObservationIgnored public var isPreviewOnly: () -> Bool = { false }
    /// 每次按下遥控器按钮时通知界面
    @ObservationIgnored public var onButtonDown: (RemoteButton) -> Void = { _ in }
    /// 识别出触控手势时通知界面
    @ObservationIgnored public var onTouchGesture: (TouchGesture) -> Void = { _ in }

    @ObservationIgnored private var gestures: GestureEngine!
    @ObservationIgnored private let touchRecognizer = TouchGestureRecognizer()
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    /// 按下时的前台 App；长按、双击在稍后触发，此时前台可能已经切换
    @ObservationIgnored private var pressFrontmost: [RemoteButton: String] = [:]
    /// 没有辅助功能权限时移动光标会被系统丢弃，只提示一次
    @ObservationIgnored private var warnedPointerAccess = false
    private static let logLimit = 40

    public init(store: ConfigStore, device: RemoteDevice = RemoteDevice(), touch: (any TouchSource)? = nil,
                battery: BatteryMonitor = BatteryMonitor(), pointerOutput: PointerOutput = CGPointerOutput()) {
        self.store = store
        self.device = device
        self.touch = touch
        self.battery = battery
        pointer = TouchPointer(settings: store.config.touch, output: pointerOutput)
        touchRecognizer.settings = store.config.touch
        runner.dictation = dictation
        runner.pointer = pointer
        pointer.onScrollingChange = { [unowned self] in self.isPointerScrolling = $0 }
        dictation.settings = store.config.voice
        gestures = GestureEngine(timing: store.config.gestureTiming) { [unowned self] button in
            guard let mapping = self.store.config.resolve(button, frontmost: self.pressFrontmost[button])?.mapping else {
                return .init(gestures: [])
            }
            return .init(gestures: mapping.boundGestures, repeatWhileHeld: mapping.repeatWhileHeld)
        }
        gestures.onOutput = { [unowned self] in self.handle($0) }
        device.onButton = { [unowned self] button, isDown in self.handle(button, isDown: isDown) }
        device.onConnectionChange = { [unowned self] connected in
            connected ? self.touch?.start() : self.touch?.stop()
            self.touchRecognizer.reset()
            if !connected { self.pointer.reset() }
            if connected {
                self.battery.targetName = self.device.productName
                self.battery.start()
            } else {
                self.battery.remoteDisconnected()
            }
        }
        touch?.onFrame = { [unowned self] frame in self.handle(frame) }
        touchRecognizer.onGesture = { [unowned self] in self.handle(touch: $0) }
        runner.onToggleTouchMode = { [unowned self] in
            let mode: TouchMode = self.store.config.touch.mode == .pointer ? .gestures : .pointer
            self.store.config.touch.mode = mode
            self.append(button: nil, gesture: nil, title: "触控已切换为\(mode.displayName)", kind: .action)
        }
        runner.onError = { [unowned self] message in self.append(button: nil, gesture: nil, title: message, kind: .error) }
        interceptor.shouldIntercept = { [unowned self] button in
            let config = self.store.config
            return config.isEnabled && config.interceptSystemKeys && !self.isPreviewOnly()
                && config.resolve(button, frontmost: self.frontmostBundleID) != nil
        }
    }

    public func start() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.frontmostBundleID = app?.bundleIdentifier }
        }
        device.start()
        if device.isConnected {
            touch?.start()
            battery.targetName = device.productName
            battery.start()
        }
        startInterceptorIfPossible()
    }

    /// 获得辅助功能权限后调用，启动媒体键拦截
    public func startInterceptorIfPossible() {
        interceptorRunning = interceptor.start()
    }

    /// 配置变化后调用：同步手势时长，停用时结束进行中的按住动作
    public func configDidChange() {
        gestures.timing = store.config.gestureTiming
        touchRecognizer.settings = store.config.touch
        if pointer.settings.mode != store.config.touch.mode {
            // 切换用途时丢弃进行中的触摸，并松开按住的鼠标键
            touchRecognizer.reset()
            pointer.reset()
        }
        pointer.settings = store.config.touch
        if dictation.settings != store.config.voice { dictation.settings = store.config.voice }
        if !store.config.isEnabled {
            gestures.reset()
            runner.endAll()
        }
    }

    public func clearLog() { log.removeAll() }

    /// 仅用于界面预览与截图
    public func appendPreviewLog(_ entries: [LogEntry], frontmost bundleID: String?) {
        log = entries
        frontmostBundleID = bundleID
    }

    private func handle(_ button: RemoteButton, isDown: Bool) {
        interceptor.noteRemoteActivity(button)
        if isDown {
            pressFrontmost[button] = frontmostBundleID
            onButtonDown(button)
            // 按压触控板时手指必然在触控面上，这次触摸不再识别为滑动或转动
            if button == .select || button.isDirectional { touchRecognizer.suppressCurrentTouch() }
            if store.config.touch.mode == .pointer { pointer.noteButtonPress() }
        }
        guard store.config.isEnabled else {
            if isDown { append(button: button, gesture: nil, title: "映射已停用", kind: .passthrough) }
            return
        }
        if isDown, store.config.resolve(button, frontmost: frontmostBundleID) == nil {
            append(button: button, gesture: nil, title: "未映射 · 系统默认", kind: .passthrough)
        }
        gestures.handle(button, isDown: isDown)
        if !isDown { runner.buttonReleased(button) }
    }

    private func handle(_ output: GestureOutput) {
        switch output {
        case .fire(let button, let gesture):
            guard let bound = boundAction(button, gesture) else { return }
            if isPreviewOnly(), !bound.action.runsWhileSettingsFocused {
                append(button: button, gesture: gesture, title: bound.displayTitle, kind: .preview)
                return
            }
            if gesture == .longPress, case .dictation = bound.action {
                // 长按触发时键还按着：按「按住」的方式开始，松开即结束
                runner.begin(bound.action, for: button)
            } else {
                runner.perform(bound.action)
            }
            // 连续触发的方向键不逐条记录
            if log.first?.button != button || log.first?.gesture != gesture || Date().timeIntervalSince(log.first!.date) > 0.5 {
                append(button: button, gesture: gesture, title: bound.displayTitle, kind: .action)
            }

        case .begin(let button):
            guard let bound = boundAction(button, .hold) else { return }
            if isPreviewOnly(), !bound.action.runsWhileSettingsFocused {
                append(button: button, gesture: .hold, title: bound.displayTitle, kind: .preview)
                return
            }
            runner.begin(bound.action, for: button)
            append(button: button, gesture: .hold, title: bound.displayTitle, kind: .action)

        case .end(let button):
            runner.end(for: button)
        }
    }

    private func handle(_ frame: TouchFrame) {
        let settings = store.config.touch
        guard settings.isEnabled else { return }
        switch settings.mode {
        case .gestures:
            touchRecognizer.handle(frame)
        case .pointer:
            // 设置窗口在前台时也允许移动光标，否则无法用遥控器操作设置界面
            guard store.config.isEnabled else { return }
            guard ActionRunner.hasAccessibility else {
                if !warnedPointerAccess, frame.contacts.contains(where: \.isTouching) {
                    warnedPointerAccess = true
                    append(button: nil, gesture: nil, title: "需要「辅助功能」权限才能移动光标", kind: .error)
                }
                return
            }
            pointer.handle(frame)
        }
    }

    private func handle(touch gesture: TouchGesture) {
        onTouchGesture(gesture)
        guard store.config.isEnabled else { return }
        // 连续转动只记录第一条
        let isContinuation = gesture.isRotation && log.first?.touch == gesture
            && Date().timeIntervalSince(log.first!.date) < 0.6
        guard let bound = store.config.resolve(gesture, frontmost: frontmostBundleID)?.action else {
            if !isContinuation { append(button: nil, gesture: nil, touch: gesture, title: "未映射", kind: .passthrough) }
            return
        }
        let preview = isPreviewOnly()
        if !preview { runner.perform(bound.action) }
        if !isContinuation {
            append(button: nil, gesture: nil, touch: gesture, title: bound.displayTitle, kind: preview ? .preview : .action)
        }
    }

    private func boundAction(_ button: RemoteButton, _ gesture: RemoteGesture) -> BoundAction? {
        store.config.resolve(button, frontmost: pressFrontmost[button] ?? frontmostBundleID)?.mapping[gesture]
    }

    private func append(button: RemoteButton?, gesture: RemoteGesture?, touch: TouchGesture? = nil,
                        title: String, kind: LogEntry.Kind) {
        log.insert(LogEntry(button: button, gesture: gesture, touch: touch, title: title, kind: kind), at: 0)
        if log.count > Self.logLimit { log.removeLast(log.count - Self.logLimit) }
    }
}
