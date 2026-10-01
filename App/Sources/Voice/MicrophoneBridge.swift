import AppKit
import Observation
import RemoteKit

/// 独立安装的 CoreAudio 组件；App Store 版只使用已安装的标准音频输入。
@Observable
final class MicrophoneBridge {
    private(set) var isInstalled = false
    private(set) var isBusy = false
    private(set) var message: String?

    func refresh() {
        isInstalled = AudioInputDevices.deviceID(uid: AudioInputDevices.remoteMicrophoneUID) != nil
    }

    func useAsSystemInput() {
        do {
            try AudioInputDevices.useAsDefault(uid: AudioInputDevices.remoteMicrophoneUID)
            message = "Siri Remote Mic 已设为系统音频输入。"
        } catch { message = error.localizedDescription }
    }

    #if !APP_STORE
    func install() async {
        guard !isBusy else { return }
        guard let script = Bundle.main.resourceURL?.appending(path: "Microphone/install.sh"),
              FileManager.default.fileExists(atPath: script.path) else {
            message = "安装组件缺失，请重新构建官网版 RemoteMapper。"
            return
        }
        isBusy = true
        message = "等待管理员授权，安装后会检查系统音频服务。"
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
            message = "安装已取消。"
        } else {
            message = "安装失败：\(result.1.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    private static func appleScriptQuote(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    #endif
}
