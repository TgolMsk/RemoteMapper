import AppKit
import ApplicationServices

/// 执行动作。键盘类动作需要辅助功能权限；Shell 与 AppleScript 在子进程中运行，不阻塞主线程。
public final class ActionRunner {
    /// 动作失败时的说明，由上层写入事件日志
    public var onError: (String) -> Void = { _ in }

    private var holds: [RemoteButton: HoldSession] = [:]

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

        case .shell(let command):
            await run("/bin/zsh", ["-lc", command], label: "Shell")

        case .appleScript(let source):
            await run("/usr/bin/osascript", ["-e", source], label: "AppleScript")

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

    private func run(_ executable: String, _ arguments: [String], label: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            onError("\(label) 启动失败：\(error.localizedDescription)")
            return
        }
        let status = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        }
        guard status != 0 else { return }
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        onError("\(label) 退出码 \(status)" + (message.isEmpty ? "" : "：\(message.prefix(120))"))
    }
}
