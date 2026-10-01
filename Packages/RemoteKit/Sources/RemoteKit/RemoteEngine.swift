import AppKit
import Observation

public struct LogEntry: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case action, passthrough, preview, error }

    public let id = UUID()
    public let date: Date
    public let button: RemoteButton?
    public let gesture: RemoteGesture?
    public let title: String
    public let kind: Kind

    public init(date: Date = Date(), button: RemoteButton?, gesture: RemoteGesture?, title: String, kind: Kind) {
        self.date = date
        self.button = button
        self.gesture = gesture
        self.title = title
        self.kind = kind
    }
}

/// 串起设备、手势识别、配置解析与动作执行。
@Observable
public final class RemoteEngine {
    public let device: RemoteDevice
    public let store: ConfigStore
    @ObservationIgnored public let runner = ActionRunner()
    @ObservationIgnored public let interceptor = MediaKeyInterceptor()

    public private(set) var frontmostBundleID: String?
    public private(set) var log: [LogEntry] = []
    public private(set) var interceptorRunning = false

    /// 为 true 时只记录、不执行动作（设置窗口位于前台时使用，避免把按键打进设置界面）
    @ObservationIgnored public var isPreviewOnly: () -> Bool = { false }
    /// 每次按下遥控器按钮时通知界面
    @ObservationIgnored public var onButtonDown: (RemoteButton) -> Void = { _ in }

    @ObservationIgnored private var gestures: GestureEngine!
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    /// 按下时的前台 App；长按、双击在稍后触发，此时前台可能已经切换
    @ObservationIgnored private var pressFrontmost: [RemoteButton: String] = [:]
    private static let logLimit = 40

    public init(store: ConfigStore, device: RemoteDevice = RemoteDevice()) {
        self.store = store
        self.device = device
        gestures = GestureEngine(timing: store.config.gestureTiming) { [unowned self] button in
            guard let mapping = self.store.config.resolve(button, frontmost: self.pressFrontmost[button])?.mapping else {
                return .init(gestures: [])
            }
            return .init(gestures: mapping.boundGestures, repeatWhileHeld: mapping.repeatWhileHeld)
        }
        gestures.onOutput = { [unowned self] in self.handle($0) }
        device.onButton = { [unowned self] button, isDown in self.handle(button, isDown: isDown) }
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
        startInterceptorIfPossible()
    }

    /// 获得辅助功能权限后调用，启动媒体键拦截
    public func startInterceptorIfPossible() {
        interceptorRunning = interceptor.start()
    }

    /// 配置变化后调用：同步手势时长，停用时结束进行中的按住动作
    public func configDidChange() {
        gestures.timing = store.config.gestureTiming
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
        }
        guard store.config.isEnabled else {
            if isDown { append(button: button, gesture: nil, title: "映射已停用", kind: .passthrough) }
            return
        }
        if isDown, store.config.resolve(button, frontmost: frontmostBundleID) == nil {
            append(button: button, gesture: nil, title: "未映射 · 系统默认", kind: .passthrough)
        }
        gestures.handle(button, isDown: isDown)
    }

    private func handle(_ output: GestureOutput) {
        switch output {
        case .fire(let button, let gesture):
            guard let bound = boundAction(button, gesture) else { return }
            if isPreviewOnly() {
                append(button: button, gesture: gesture, title: bound.displayTitle, kind: .preview)
                return
            }
            runner.perform(bound.action)
            // 连续触发的方向键不逐条记录
            if log.first?.button != button || log.first?.gesture != gesture || Date().timeIntervalSince(log.first!.date) > 0.5 {
                append(button: button, gesture: gesture, title: bound.displayTitle, kind: .action)
            }

        case .begin(let button):
            guard let bound = boundAction(button, .hold) else { return }
            if isPreviewOnly() {
                append(button: button, gesture: .hold, title: bound.displayTitle, kind: .preview)
                return
            }
            runner.begin(bound.action, for: button)
            append(button: button, gesture: .hold, title: bound.displayTitle, kind: .action)

        case .end(let button):
            runner.end(for: button)
        }
    }

    private func boundAction(_ button: RemoteButton, _ gesture: RemoteGesture) -> BoundAction? {
        store.config.resolve(button, frontmost: pressFrontmost[button] ?? frontmostBundleID)?.mapping[gesture]
    }

    private func append(button: RemoteButton?, gesture: RemoteGesture?, title: String, kind: LogEntry.Kind) {
        log.insert(LogEntry(button: button, gesture: gesture, title: title, kind: kind), at: 0)
        if log.count > Self.logLimit { log.removeLast(log.count - Self.logLimit) }
    }
}
