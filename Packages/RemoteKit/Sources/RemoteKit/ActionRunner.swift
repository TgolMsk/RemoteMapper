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

    public init() {}

    public static var hasAccessibility: Bool { AXIsProcessTrusted() }

    public func perform(_ action: Action) {
        Task { await execute(action) }
    }

    /// 「按住」开始：holdKey 保持按下，其它动作在开始时执行一次
    public func begin(_ action: Action, for button: RemoteButton) {
        guard case .holdKey(let combo) = action else {
            perform(action)
            return
        }
        guard requireAccessibility() else { return }
        holds.removeValue(forKey: button)?.end()
        holds[button] = KeyboardSynth.beginHold(combo)
    }

    public func end(for button: RemoteButton) {
        holds.removeValue(forKey: button)?.end()
    }

    public func endAll() {
        for session in holds.values { session.end() }
        holds.removeAll()
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

        case .sequence(let actions):
            for step in actions { await execute(step) }

        case .delay(let ms):
            try? await Task.sleep(for: .milliseconds(ms))
        }
    }

    private func requireAccessibility() -> Bool {
        if Self.hasAccessibility { return true }
        onError("需要「辅助功能」权限才能模拟按键")
        return false
    }
}
