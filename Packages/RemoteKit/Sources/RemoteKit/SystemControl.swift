import AppKit
import Carbon.HIToolbox

/// 锁屏、关闭显示器、解锁、休眠、重启、关机。
enum SystemControl {
    /// 执行命令，失败时返回错误说明
    static func run(_ command: SystemCommand) async -> String? {
        switch command {
        case .lockScreen:
            lockScreen()
            return nil
        case .displaySleep:
            // 先锁屏再关显示器：不依赖「关闭显示器后需要密码」的系统设置；Mac 本身不休眠
            if !LockScreen.isLocked {
                lockScreen()
                try? await Task.sleep(for: .milliseconds(800))
            }
            return await ScriptExecutor.run("/usr/bin/pmset", ["displaysleepnow"], label: L10n.text("关闭显示器"))
        case .unlock: return await LockScreen.unlock()
        case .sleep: return send(kAESleep, name: SystemCommand.sleep.displayName)
        case .restart: return send(kAERestart, name: SystemCommand.restart.displayName)
        case .shutDown: return send(kAEShutDown, name: SystemCommand.shutDown.displayName)
        case .powerMenu: return nil
        }
    }

    /// 系统的「锁定屏幕」快捷键
    private static func lockScreen() {
        KeyboardSynth.tap(KeyCombo(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.control, .command]))
    }

    /// 给登录窗口发送系统事件，与苹果菜单里的「睡眠」「重新启动」「关机」相同：
    /// 各 App 会先被要求退出，有未保存的文稿时会提示，不会强制断电
    private static func send(_ eventID: AEEventID, name: String) -> String? {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: eventID,
                                           targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow"),
                                           returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        do {
            _ = try event.sendEvent(options: [.noReply], timeout: 10)
            return nil
        } catch {
            return L10n.format("%@失败：%@", name, error.localizedDescription)
        }
    }
}
