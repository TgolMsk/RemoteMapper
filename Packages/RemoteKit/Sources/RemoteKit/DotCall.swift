import AppKit
import ApplicationServices

/// ChatGPT 桌面版 dot 语音通话的操作
public enum DotCallOperation: String, CaseIterable, Codable, Sendable {
    /// 没有通话时呼叫，通话中挂断
    case toggle
    case start
    case hangUp
    /// 切换通话中的麦克风静音
    case toggleMute

    public var displayName: String {
        switch self {
        case .toggle: "呼叫 / 挂断"
        case .start: "呼叫"
        case .hangUp: "挂断"
        case .toggleMute: "切换静音"
        }
    }
}

/// 操作 ChatGPT 桌面版（com.openai.codex）里 dot 的语音通话。
///
/// ChatGPT 没有为 dot 通话提供 URL Scheme、AppleScript 或命令行接口（codex://dots 只能打开主页），
/// 只能通过辅助功能找到 dot 页面上的通话按钮。这些按钮在无障碍树里没有 AXPress 动作，
/// 所以先读出按钮位置再合成一次鼠标点击，点完把鼠标位置和前台 App 恢复原样。
/// 依赖界面文案（中文界面下 Start call / Hang up 目前未翻译），已在 ChatGPT 26.928 上实测。
nonisolated public enum DotCall {
    static let startLabels: Set<String> = ["start call", "call", "拨打电话", "呼叫"]
    static let hangUpLabels: Set<String> = ["hang up", "挂断", "结束通话"]
    static let muteLabels: Set<String> = ["mute microphone", "unmute microphone", "将麦克风静音", "取消麦克风静音"]

    /// 执行操作，失败时返回错误说明。无障碍树遍历较慢，放在主线程之外进行
    @concurrent public static func perform(_ operation: DotCallOperation) async -> String? {
        guard AXIsProcessTrusted() else { return "需要「辅助功能」权限才能操作 ChatGPT" }
        // 有些 App（例如 Electron 应用）在前台时读不到系统焦点，这时用 NSWorkspace 的记录
        let previous = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier } ?? focusedPID()
        guard let pid = await chatGPTProcess(launchIfNeeded: operation == .start || operation == .toggle) else {
            return "ChatGPT 没有在运行"
        }
        let message = await run(operation, pid: pid)
        // 操作过程中切到了 ChatGPT 的话，切回原来的 App
        if let previous, previous != pid, focusedPID() == pid {
            try? await Task.sleep(for: .milliseconds(200))
            await activate(previous, waitForFocus: false)
        }
        return message
    }

    private static func run(_ operation: DotCallOperation, pid: pid_t) async -> String? {
        let tree = AccessibilityTree(pid: pid)
        let name = primaryDotName()
        var nodes = tree.buttons()
        var decision = decide(operation, nodes, dotName: name)
        if case .missing = decision {
            // 当前界面不是 dot 页面：切过去再找
            await openDotPage(tree, nodes: nodes, dotName: name, pid: pid)
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(300))
                nodes = tree.buttons()
                decision = decide(operation, nodes, dotName: name)
                if case .missing = decision { continue }
                break
            }
        }
        switch decision {
        case .alreadyDone:
            return nil
        case .noCall:
            return "当前没有 dot 通话"
        case .missing:
            return operation == .start || operation == .toggle ? "没有在 ChatGPT 里找到 dot 的呼叫按钮" : "当前没有 dot 通话"
        case .press(let node):
            return await click(node, pid: pid) ? nil : "ChatGPT 窗口没有切到前台或被遮挡，未点击"
        }
    }

    // MARK: - 决策

    enum Decision {
        case press(AXNode)
        case alreadyDone
        /// 侧边栏能看到 dot 且没有显示通话中，不必再切到 dot 页面去找
        case noCall
        /// 当前界面上找不到需要的按钮，需要切到 dot 页面
        case missing
    }

    static func decide(_ operation: DotCallOperation, _ nodes: [AXNode], dotName: String?) -> Decision {
        let hangUp = nodes.first { matches($0.labels, hangUpLabels) }
        let start = nodes.first { $0.isEnabled && matches($0.labels, startLabels) }
        let inCallRow = nodes.contains { isCallInProgress($0.labels) }
        let idleRow = dotName.map { name in nodes.contains { isSidebarRow($0.labels, dotName: name) && !isCallInProgress($0.labels) } } ?? false
        switch operation {
        case .toggle:
            if let hangUp { return .press(hangUp) }
            // 侧边栏显示通话中但挂断按钮还没渲染出来时继续等，别去点呼叫
            if inCallRow { return .missing }
            return start.map(Decision.press) ?? .missing
        case .start:
            if hangUp != nil || inCallRow { return .alreadyDone }
            return start.map(Decision.press) ?? .missing
        case .hangUp:
            if let hangUp { return .press(hangUp) }
            return idleRow ? .noCall : .missing
        case .toggleMute:
            if let mute = nodes.first(where: { matches($0.labels, muteLabels) }) { return .press(mute) }
            return idleRow ? .noCall : .missing
        }
    }

    static func matches(_ labels: [String], _ wanted: Set<String>) -> Bool {
        labels.contains { wanted.contains($0.lowercased()) }
    }

    /// 侧边栏里的 dot 条目，标签形如「嗨宝」或「嗨宝 Call in progress」
    static func isSidebarRow(_ labels: [String], dotName: String) -> Bool {
        labels.contains { $0 == dotName || $0.hasPrefix(dotName + " ") }
    }

    static func isCallInProgress(_ labels: [String]) -> Bool {
        labels.contains { $0.hasSuffix(" Call in progress") || $0.hasSuffix(" 通话中") }
    }

    // MARK: - 打开 dot 页面

    /// 优先点侧边栏里的 dot 条目；侧边栏里找不到时打开 codex://dots
    private static func openDotPage(_ tree: AccessibilityTree, nodes: [AXNode], dotName name: String?, pid: pid_t) async {
        tree.unminimizeWindows()
        func row(_ nodes: [AXNode]) -> AXNode? {
            nodes.first { node in
                isCallInProgress(node.labels) || name.map { isSidebarRow(node.labels, dotName: $0) } == true
            }
        }
        if let row = row(nodes) {
            _ = await click(row, pid: pid)
            return
        }
        await MainActor.run { _ = NSWorkspace.shared.open(URL(string: "codex://dots")!) }
        try? await Task.sleep(for: .milliseconds(1500))
        if let row = row(tree.buttons()) { _ = await click(row, pid: pid) }
    }

    /// 主 dot 的显示名，来自 ChatGPT 写在 ~/.codex 的界面状态缓存
    static func primaryDotName() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/.codex-global-state.json")
        return (try? Data(contentsOf: url)).flatMap(primaryDotName(fromGlobalState:))
    }

    static func primaryDotName(fromGlobalState data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = root["electron-persisted-atom-state"] as? [String: Any],
              let response = (state["primary-aeon-selection-v1"] as? [String: Any])?["response"] as? [String: Any],
              let threadID = (response["selection"] as? [String: Any])?["thread_id"] as? String,
              let profiles = (state["cloud-aeon-sidebar-cache-v1"] as? [String: Any])?["profilesByThreadId"] as? [String: Any],
              let profile = profiles[threadID] as? [String: Any]
        else { return nil }
        return profile["display_name"] as? String
    }

    // MARK: - App 与点击

    private static func chatGPTProcess(launchIfNeeded: Bool) async -> pid_t? {
        if let pid = await runningPID() { return pid }
        guard launchIfNeeded else { return nil }
        await MainActor.run { _ = NSWorkspace.shared.open(URL(string: "codex://dots")!) }
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(300))
            if let pid = await runningPID(), !AccessibilityTree(pid: pid).windows.isEmpty { return pid }
        }
        return await runningPID()
    }

    private static func runningPID() async -> pid_t? {
        await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: KnownApp.codex).first?.processIdentifier
        }
    }

    /// 当前拥有焦点的 App。NSWorkspace.frontmostApplication 依赖 run loop 刷新，在后台任务里可能是旧值
    static func focusedPID() -> pid_t? {
        guard let app = AccessibilityTree.attribute(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute) else {
            return nil
        }
        var pid: pid_t = 0
        return AXUIElementGetPid(app as! AXUIElement, &pid) == .success ? pid : nil
    }

    /// 切到前台；点击前要等它真正拿到焦点，否则点击会落在挡在前面的窗口上
    private static func activate(_ pid: pid_t, waitForFocus: Bool = true) async {
        await MainActor.run { _ = NSRunningApplication(processIdentifier: pid)?.activate() }
        guard waitForFocus else { return }
        var attempts = 0
        while attempts < 16, focusedPID() != pid {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// 该位置最上层的界面元素是否属于这个 App
    private static func isTopmost(_ point: CGPoint, pid: pid_t) -> Bool {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              let element else { return false }
        var owner: pid_t = 0
        return AXUIElementGetPid(element, &owner) == .success && owner == pid
    }

    private static func click(_ node: AXNode, pid: pid_t) async -> Bool {
        await activate(pid)
        AXUIElementPerformAction(node.element, "AXScrollToVisible" as CFString)
        try? await Task.sleep(for: .milliseconds(150))
        guard let frame = node.frame else { return false }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        // 没切到前台或被别的窗口挡住时宁可不点，避免点到其它 App
        guard isTopmost(point, pid: pid) else { return false }
        await MouseSynth.waitForModifiersReleased()
        MouseSynth.click(at: point)
        return true
    }
}

// MARK: - 无障碍树

nonisolated struct AXNode {
    let element: AXUIElement
    let labels: [String]
    let isEnabled: Bool

    /// 屏幕坐标（左上角为原点，与 CGEvent 一致）
    var frame: CGRect? {
        var origin = CGPoint.zero, size = CGSize.zero
        guard let p = AccessibilityTree.attribute(element, kAXPositionAttribute),
              let s = AccessibilityTree.attribute(element, kAXSizeAttribute) else { return nil }
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return size.width > 0 && size.height > 0 ? CGRect(origin: origin, size: size) : nil
    }
}

nonisolated struct AccessibilityTree {
    let app: AXUIElement

    init(pid: pid_t) {
        app = AXUIElementCreateApplication(pid)
        // Electron/Chromium 默认不生成网页内容的无障碍树，需要手动打开
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    var windows: [AXUIElement] { (Self.attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] }

    /// 广度优先收集所有窗口里带标签的按钮（带 aria-pressed 的按钮在无障碍树里是 AXCheckBox）
    func buttons(limit: Int = 60_000) -> [AXNode] {
        var queue = windows
        var result: [AXNode] = []
        var index = 0
        while index < queue.count && index < limit {
            let element = queue[index]
            index += 1
            let role = Self.string(element, kAXRoleAttribute)
            if role == kAXButtonRole || role == kAXCheckBoxRole {
                let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute]
                    .compactMap { Self.string(element, $0) }
                if !labels.isEmpty {
                    let enabled = Self.attribute(element, kAXEnabledAttribute) as? Bool ?? true
                    result.append(AXNode(element: element, labels: labels, isEnabled: enabled))
                }
            }
            queue.append(contentsOf: (Self.attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        }
        return result
    }

    func unminimizeWindows() {
        for window in windows where Self.attribute(window, kAXMinimizedAttribute) as? Bool == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        guard let text = (attribute(element, name) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }
}

// MARK: - 鼠标

nonisolated enum MouseSynth {
    /// 等用户松开修饰键，否则按住 ⌃ 时的点击会变成右键
    static func waitForModifiersReleased() async {
        let mask: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        var attempts = 0
        while attempts < 50, !CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    /// 在屏幕坐标处合成一次不带修饰键的左键点击，点完把鼠标放回原处
    static func click(at point: CGPoint) {
        let original = CGEvent(source: nil)?.location ?? point
        let source = CGEventSource(stateID: .privateState)
        func post(_ type: CGEventType, _ location: CGPoint) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                      mouseCursorPosition: location, mouseButton: .left) else { return }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            post(type, point)
            usleep(40_000)
        }
        post(.mouseMoved, original)
    }
}
