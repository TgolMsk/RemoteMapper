import AppKit
import ApplicationServices
import Carbon.HIToolbox
import IOKit.pwr_mgt
import os

/// 锁屏解锁：判断是否锁屏，点亮屏幕并让密码框获得焦点，再输入钥匙串里保存的登录密码。
///
/// 锁屏时遥控器的第一次按键往往只是点亮屏幕，密码框要等锁屏界面淡入后才接收输入，
/// 立即合成的按键会丢失。所以先声明一次用户活动点亮屏幕，再通过辅助功能等 loginwindow 的密码框
/// 获得焦点（迟迟没有焦点时主动聚焦或点击它），就绪后才开始输入。
public enum LockScreen {
    private static let log = Logger(subsystem: "com.ws.RemoteMapper", category: "lockscreen")

    /// 当前会话是否处于锁屏（解锁时会话字典里没有这个键）
    public static var isLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// 锁屏时输入登录密码并回车；未锁屏时什么也不做，避免把密码打进当前 App。失败时返回错误说明
    static func unlock() async -> String? {
        guard isLocked else {
            log.info("未锁屏，忽略解锁")
            return nil
        }
        let password: String?
        do { password = try UnlockPassword.read() } catch { return L10n.format("解锁失败：%@", error.localizedDescription) }
        guard let password, !password.isEmpty else { return L10n.text("未设置解锁密码：在「通用 › 锁屏解锁」中设置") }
        await focusPasswordField()
        await KeyboardSynth.typeKeystrokes(password)
        try? await Task.sleep(for: .milliseconds(60))
        KeyboardSynth.tap(.returnKey)
        log.info("已输入解锁密码并回车")
        return nil
    }

    /// 点亮屏幕并等密码框获得焦点，返回是否确认就绪；超时也会照常输入
    @discardableResult
    static func focusPasswordField(timeout: Duration = .seconds(3)) async -> Bool {
        var assertion: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity("RemoteMapper 锁屏输入" as CFString, kIOPMUserActiveLocal, &assertion)
        defer { IOPMAssertionRelease(assertion) }

        let clock = ContinuousClock()
        let start = clock.now
        // 等这么久仍没有焦点就主动处理：第一次设焦点（找不到密码框则按 Shift 唤出），第二次直接点击
        let nudges: [Duration] = [.milliseconds(500), .milliseconds(1300)]
        var nudged = 0
        while clock.now - start < timeout {
            if let focused = focusedElement(), AccessibilityTree.string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
                log.info("密码框已获得焦点，用时 \(Int((clock.now - start) / .milliseconds(1))) ms")
                // 刚获得焦点时锁屏界面可能还在动画，稍等再输入
                try? await Task.sleep(for: .milliseconds(150))
                return true
            }
            if nudged < nudges.count, clock.now - start >= nudges[nudged] {
                nudge(attempt: nudged)
                nudged += 1
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        log.error("等待密码框超时，当前焦点：\(describeFocus(), privacy: .public)")
        return false
    }

    private static func nudge(attempt: Int) {
        guard let field = passwordField() else {
            log.info("辅助功能找不到锁屏密码框，按一下 Shift 唤出")
            KeyboardSynth.tap(KeyCombo(keyCode: UInt16(kVK_Shift)))
            return
        }
        if attempt == 0,
           AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success {
            log.info("已通过辅助功能聚焦密码框")
        } else if let frame = AXNode(element: field, labels: [], isEnabled: true).frame {
            log.info("点击密码框")
            MouseSynth.click(at: CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    private static func focusedElement() -> AXUIElement? {
        guard let value = AccessibilityTree.attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// loginwindow 窗口里的密码框
    private static func passwordField() -> AXUIElement? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow")
            .first?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var queue = (AccessibilityTree.attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        var index = 0
        while index < queue.count, index < 2_000 {
            let element = queue[index]
            index += 1
            if AccessibilityTree.string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole { return element }
            queue.append(contentsOf: (AccessibilityTree.attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        }
        return nil
    }

    /// 诊断用：当前焦点元素的角色与所属进程
    private static func describeFocus() -> String {
        guard let focused = focusedElement() else { return "辅助功能读不到焦点" }
        var pid: pid_t = 0
        AXUIElementGetPid(focused, &pid)
        let app = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"
        let role = AccessibilityTree.string(focused, kAXRoleAttribute) ?? "?"
        let subrole = AccessibilityTree.string(focused, kAXSubroleAttribute) ?? "-"
        return "\(app) \(role)/\(subrole)"
    }
}
