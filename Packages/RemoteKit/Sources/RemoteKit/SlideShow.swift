import AppKit
import ApplicationServices
import os
import UniformTypeIdentifiers

/// 打开指定的演示文稿并从头全屏放映。
///
/// 锁屏时先解锁（或等用户自己解锁），再把文稿交给它的默认 App 打开；用辅助功能确认前台窗口
/// 已经是这份文稿后，才发送该 App 的「从头放映」快捷键。冷启动 WPS 要好几秒，固定等待不可靠。
public enum SlideShow {
    private static let log = Logger(subsystem: "com.ws.RemoteMapper", category: "slideshow")

    /// 可以选择或拖入的演示文稿类型
    public static let fileExtensions = ["pptx", "ppt", "ppsx", "pps", "key", "dps", "dpt"]

    public static func isPresentation(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if fileExtensions.contains(url.pathExtension.lowercased()) { return true }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .presentation) == true
    }

    /// 存进配置的路径：用 ~ 开头，手写配置时更易读
    public static func storedPath(for url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// 支持自动放映的 App 及其「从头放映」预设
    static func startPreset(forApp bundleID: String) -> Preset? {
        switch bundleID {
        case KnownApp.wps, KnownApp.powerPoint: Preset.find("presentation.fromBeginning")
        case KnownApp.keynote: Preset.find("presentation.keynotePlay")
        default: nil
        }
    }

    /// 默认用来打开这类文件的 App（按扩展名判断，文件不存在也能查）
    public static func defaultApp(forPath path: String) -> (bundleID: String, name: String, supportsAutoPlay: Bool)? {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let type = UTType(filenameExtension: url.pathExtension),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: type),
              let bundleID = Bundle(url: appURL)?.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
        return (bundleID, name, startPreset(forApp: bundleID) != nil)
    }

    /// 失败时返回错误说明
    static func play(path: String, unlock: Bool) async -> String? {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if LockScreen.isLocked {
            // 没保存解锁密码时退回为等用户自己解锁（例如用 Touch ID）
            let autoUnlock = unlock && UnlockPassword.isSet
            if autoUnlock, let message = await LockScreen.unlock() { return message }
            if autoUnlock { log.info("已输入解锁密码，等待解锁完成") } else { log.info("屏幕已锁定，等待解锁") }
            guard await waitUntilUnlocked(timeout: autoUnlock ? .seconds(8) : .seconds(60)) else {
                return L10n.format("屏幕仍处于锁定状态，未放映 %@", url.lastPathComponent)
            }
            // 解锁动画结束、桌面恢复后再打开
            try? await Task.sleep(for: .milliseconds(800))
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
            return L10n.format("没有 App 能打开 %@", url.lastPathComponent)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let app: NSRunningApplication
        do {
            app = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        } catch {
            return L10n.format("无法打开 %@：%@", url.lastPathComponent, error.localizedDescription)
        }
        guard let shortcut = startPreset(forApp: bundleID).flatMap(\.action.keyCombo) else {
            return L10n.format("%@ 已打开，但 %@ 不支持自动放映", url.lastPathComponent, bundleID)
        }
        log.info("已用 \(bundleID, privacy: .public) 打开文稿，等待窗口就绪")
        guard await waitForDocument(app, named: url.deletingPathExtension().lastPathComponent) else {
            return L10n.format("等待 %@ 打开超时，未放映", url.lastPathComponent)
        }
        // 窗口刚出现时内容可能还在加载，稍等再放映
        try? await Task.sleep(for: .milliseconds(800))
        KeyboardSynth.tap(shortcut)
        log.info("已发送从头放映 \(shortcut.displayString, privacy: .public)")
        return nil
    }

    private static func waitUntilUnlocked(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while LockScreen.isLocked {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return true
    }

    /// 等 App 到前台、焦点窗口标题包含文稿名。有的 App 窗口标题不带文件名（例如只显示 App 名），
    /// 所以 App 在前台持续一段时间后也视为就绪
    private static func waitForDocument(_ app: NSRunningApplication, named name: String,
                                        timeout: Duration = .seconds(25)) async -> Bool {
        let clock = ContinuousClock()
        let start = clock.now
        var frontSince: ContinuousClock.Instant?
        var lastTitle: String?
        var reactivated = false
        while clock.now - start < timeout {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                let title = focusedWindowTitle(app.processIdentifier)
                if title != lastTitle {
                    lastTitle = title
                    log.info("前台窗口：\(title ?? "（读不到标题）", privacy: .public)")
                }
                if let title, title.localizedCaseInsensitiveContains(name) { return true }
                frontSince = frontSince ?? clock.now
                if let frontSince, clock.now - frontSince > .seconds(6) {
                    log.info("窗口标题里没有文稿名，App 已在前台 6 秒，按就绪处理")
                    return true
                }
            } else {
                frontSince = nil
                // 打开时被别的窗口抢了前台，再激活一次
                if !reactivated, clock.now - start > .seconds(3) {
                    reactivated = true
                    app.activate()
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private static func focusedWindowTitle(_ pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        guard let window = AccessibilityTree.attribute(app, kAXFocusedWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return AccessibilityTree.string(window as! AXUIElement, kAXTitleAttribute)
    }
}

extension Action {
    /// 单个快捷键动作的组合键
    var keyCombo: KeyCombo? {
        if case .keystroke(let combo) = self { return combo }
        return nil
    }
}
