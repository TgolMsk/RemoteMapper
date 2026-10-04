import AppKit
import Observation
import RemoteKit

/// 独立安装的 CoreAudio 组件：遥控器麦克风作为系统音频输入 Siri Remote Mic。
@Observable
final class MicrophoneBridge {
    private(set) var isInstalled = false
    private(set) var isBusy = false
    private enum MessageState {
        case systemInput, missingComponent, awaitingAuthorization, cancelled
        case installationFailed(String)
        case nativeError(String)
    }
    private var messageState: MessageState?

    /// 保存消息含义和原始输出，切换界面语言后再读取时使用当前语言。
    var message: String? {
        guard let messageState else { return nil }
        switch messageState {
        case .systemInput: return L10n.text("Siri Remote Mic 已设为系统音频输入。")
        case .missingComponent: return L10n.text("安装组件缺失，请重新下载安装 RemoteMapper。")
        case .awaitingAuthorization: return L10n.text("等待管理员授权，安装后会检查系统音频服务。")
        case .cancelled: return L10n.text("安装已取消。")
        case .installationFailed(let output): return L10n.format("安装失败：%@", Self.localizedInstallerOutput(output))
        case .nativeError(let description): return description
        }
    }

    func refresh() {
        isInstalled = AudioInputDevices.deviceID(uid: AudioInputDevices.remoteMicrophoneUID) != nil
    }

    func useAsSystemInput() {
        do {
            try AudioInputDevices.useAsDefault(uid: AudioInputDevices.remoteMicrophoneUID)
            messageState = .systemInput
        } catch { messageState = .nativeError(error.localizedDescription) }
    }

    func install() async {
        guard !isBusy else { return }
        guard let script = Bundle.main.resourceURL?.appending(path: "Microphone/install.sh"),
              FileManager.default.fileExists(atPath: script.path) else {
            messageState = .missingComponent
            return
        }
        isBusy = true
        messageState = .awaitingAuthorization
        defer { isBusy = false }
        let command = "/bin/bash " + Self.shellQuote(script.path)
        let appleScript = "do shell script \"\(Self.appleScriptQuote(command))\" with administrator privileges"
        let result = await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return (process.terminationStatus, String(decoding: output, as: UTF8.self))
            } catch { return (Int32(-1), error.localizedDescription) }
        }.value
        refresh()
        if result.0 == 0, isInstalled {
            useAsSystemInput()
        } else if result.1.contains("(-128)") {
            messageState = .cancelled
        } else {
            messageState = .installationFailed(result.1)
        }
    }

    /// 安装脚本保留稳定的终端输出，应用里显示对应的本地化说明。
    private static func localizedInstallerOutput(_ output: String) -> String {
        let knownMessages = [
            "请使用 sudo 运行，或在 RemoteMapper 中点击安装。",
            "请先将 Apple PacketLogger 安装到 /Applications。",
            "安装路径包含符号链接，已停止。",
            "系统音频服务负载过高，请稍后安装。",
            "安装未完成，已恢复原有音频组件。",
            "系统音频服务异常，将自动撤回安装。",
            "macOS 未加载遥控器麦克风，将撤回安装。",
        ]
        return knownMessages.reduce(output.trimmingCharacters(in: .whitespacesAndNewlines)) { text, key in
            text.replacingOccurrences(of: key, with: L10n.text(key))
        }
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    private static func appleScriptQuote(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
