import AppKit
import ApplicationServices

/// 执行动作。键盘类动作需要辅助功能权限；Shell 与 AppleScript 由注入的 scriptExecutor 在子进程中运行。
public final class ActionRunner {
    /// 动作失败时的说明，由上层写入事件日志
    public var onError: (String) -> Void = { _ in }

    private var holds: [RemoteButton: HoldSession] = [:]
    /// 当前版本不支持的动作类型（App Store 版不执行 Shell 与 AppleScript）
    public var unsupportedKinds: Set<Action.Kind> = []
    /// 执行 Shell 与 AppleScript，返回错误说明；为 nil 时这两类动作不可用
    public var scriptExecutor: ((Action) async -> String?)?
    /// 语音输入
    public var dictation: VoiceDictation?
    /// 由「按住」开始的语音输入属于哪个按钮；单击切换开始的为 nil
    private var dictationOwner: RemoteButton?
    private var dictationSubmit = false
    /// 触控鼠标：鼠标按键、拖动与滚动
    public var pointer: TouchPointer?
    /// 切换触控手势 / 触控鼠标，由引擎修改配置
    public var onToggleTouchMode: () -> Void = {}
    /// 由「按住」按下的鼠标键属于哪个遥控器按钮
    private var mouseHolds: [RemoteButton: MouseButton] = [:]
    private var scrollOwner: RemoteButton?

    public init() {}

    public static var hasAccessibility: Bool { AXIsProcessTrusted() }

    public func perform(_ action: Action) {
        Task { await execute(action) }
    }

    /// 「按住」开始：holdKey 保持按下，语音输入开始录音，鼠标键按住，其它动作在开始时执行一次
    public func begin(_ action: Action, for button: RemoteButton) {
        switch action {
        case .dictation(let submit):
            startDictation(submit: submit, owner: button)
            return
        case .mouseButton(let mouse):
            guard !unsupportedKinds.contains(action.kind), requireAccessibility(), let pointer else { return }
            if let previous = mouseHolds.removeValue(forKey: button) { pointer.release(previous) }
            mouseHolds[button] = mouse
            pointer.press(mouse)
            return
        case .pointerScroll:
            guard !unsupportedKinds.contains(action.kind), let pointer else { return }
            scrollOwner = button
            pointer.isScrolling = true
            return
        default:
            break
        }
        guard case .holdKey(let combo) = action else {
            perform(action)
            return
        }
        guard requireAccessibility() else { return }
        holds.removeValue(forKey: button)?.end()
        holds[button] = KeyboardSynth.beginHold(combo)
    }

    /// 实体按键松开：由长按开始的语音输入在这里结束（长按触发时手指仍按着键，应当松开即结束）
    public func buttonReleased(_ button: RemoteButton) {
        if dictationOwner == button { finishDictation() }
    }

    public func end(for button: RemoteButton) {
        holds.removeValue(forKey: button)?.end()
        if dictationOwner == button { finishDictation() }
        if let mouse = mouseHolds.removeValue(forKey: button) { pointer?.release(mouse) }
        if scrollOwner == button {
            scrollOwner = nil
            pointer?.isScrolling = false
        }
    }

    public func endAll() {
        if dictation?.isActive == true { dictation?.cancel() }
        dictationOwner = nil
        for session in holds.values { session.end() }
        holds.removeAll()
        mouseHolds.removeAll()
        scrollOwner = nil
        pointer?.reset()
    }

    private func execute(_ action: Action) async {
        if unsupportedKinds.contains(action.kind) {
            onError("此版本不支持「\(action.kind.displayName)」动作")
            return
        }
        switch action {
        case .keystroke(let combo), .holdKey(let combo):
            guard requireAccessibility() else { return }
            KeyboardSynth.tap(combo)

        case .text(let text, let submit):
            guard requireAccessibility() else { return }
            KeyboardSynth.type(text)
            if submit {
                try? await Task.sleep(for: .milliseconds(30))
                KeyboardSynth.tap(.returnKey)
            }

        case .dictation(let submit):
            // 单击等手势：按一次开始，再按一次结束
            if dictation?.isActive == true, dictationOwner == nil {
                finishDictation()
            } else if dictation?.isActive != true {
                startDictation(submit: submit, owner: nil)
            }

        case .scroll(let direction, let lines):
            guard requireAccessibility() else { return }
            KeyboardSynth.scroll(direction, lines: lines)

        case .openURL(let string):
            guard let url = URL(string: string), url.scheme != nil else {
                onError("无效的链接：\(string)")
                return
            }
            if !NSWorkspace.shared.open(url) { onError("没有 App 能打开 \(string)") }

        case .launchApp(let bundleID):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                onError("未找到 App：\(bundleID)")
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            do {
                try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } catch {
                onError("无法打开 \(bundleID)：\(error.localizedDescription)")
            }

        case .shell, .appleScript:
            // 执行外部命令的代码在 RemoteKitScripts 中，仅官网版注入
            guard let scriptExecutor else {
                onError("此版本不支持「\(action.kind.displayName)」动作")
                return
            }
            if let message = await scriptExecutor(action) { onError(message) }

        case .dotCall(let operation):
            if let message = await DotCall.perform(operation) { onError(message) }

        case .mouseButton(let mouse):
            guard requireAccessibility() else { return }
            pointer?.click(mouse)

        case .pointerScroll:
            // 非「按住」手势：每按一次开关一次
            scrollOwner = nil
            pointer?.isScrolling.toggle()

        case .toggleTouchMode:
            onToggleTouchMode()

        case .sequence(let actions):
            for step in actions { await execute(step) }

        case .delay(let ms):
            try? await Task.sleep(for: .milliseconds(ms))
        }
    }

    private func startDictation(submit: Bool, owner: RemoteButton?) {
        guard let dictation else {
            onError("语音输入不可用")
            return
        }
        dictationOwner = owner
        dictationSubmit = submit
        dictation.endsOnRelease = owner != nil
        dictation.start()
    }

    /// 结束录音，把识别出的文字输入到当前 App
    private func finishDictation() {
        let submit = dictationSubmit
        dictationOwner = nil
        Task {
            guard let text = await dictation?.stop(), requireAccessibility() else { return }
            KeyboardSynth.type(text)
            if submit {
                try? await Task.sleep(for: .milliseconds(30))
                KeyboardSynth.tap(.returnKey)
            }
        }
    }

    private func requireAccessibility() -> Bool {
        if Self.hasAccessibility { return true }
        onError("需要「辅助功能」权限才能模拟按键")
        return false
    }
}
