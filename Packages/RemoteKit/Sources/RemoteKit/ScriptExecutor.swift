import Foundation

/// 在子进程中执行 Shell 命令与 AppleScript，不阻塞主线程。
enum ScriptExecutor {
    /// 执行动作，失败时返回错误说明
    static func run(_ action: Action) async -> String? {
        switch action {
        case .shell(let command): await run("/bin/zsh", ["-lc", command], label: "Shell")
        case .appleScript(let source): await run("/usr/bin/osascript", ["-e", source], label: "AppleScript")
        default: nil
        }
    }

    /// 运行可执行文件，非零退出码时返回带错误输出的说明
    static func run(_ executable: String, _ arguments: [String], label: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return "\(label) 启动失败：\(error.localizedDescription)"
        }
        let status = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        }
        guard status != 0 else { return nil }
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(label) 退出码 \(status)" + (message.isEmpty ? "" : "：\(message.prefix(120))")
    }
}
