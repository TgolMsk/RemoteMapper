// dotcall.swift
// 在命令行里控制 ChatGPT 桌面版 dot 的语音通话；App 内的同一功能见 RemoteKit/DotCall.swift。
// ChatGPT 改版后先用 dump / status 核对按钮标签，再同步更新两处的标签。
// 编译：make dotcall（输出 build/dotcall）
//
// 用法：
//   dotcall status    只定位按钮，不点击（默认）
//   dotcall start     呼叫 dot
//   dotcall hangup    挂断（呼叫中/通话中都可）
//   dotcall toggle    有「Hang up」就挂断，否则呼叫
//   dotcall mute      切换 dot 通话麦克风静音
//   dotcall locate    切到 dot 页面并报告按钮，不点击
//   dotcall dump      列出 ChatGPT 窗口里所有按钮的无障碍标签（排查用）
//   dotcall dumpall   列出所有带标签的界面元素，不限角色（排查用）
//   dotcall daemon [--key ctrl+opt+d] [--mute-key ctrl+opt+m]
//                     常驻并注册全局热键：--key 呼叫/挂断，--mute-key 切换静音
//
// 选项：
//   --no-open         找不到按钮时不自动切到 dot 页面
//   --dot 名字         指定 dot 名字（默认读取 ~/.codex 里的主 dot）
//
// 需要给运行它的进程（终端 / 快捷指令 / Raycast 等）授予「辅助功能」权限。

import AppKit
import ApplicationServices
import Carbon.HIToolbox

let bundleID = "com.openai.codex"

// 按钮的无障碍标签：中文界面下 Start call / Hang up 目前没有翻译，会是英文
let startLabels: Set<String> = ["start call", "call", "拨打电话", "呼叫"]
let hangupLabels: Set<String> = ["hang up", "挂断", "结束通话"]
let muteLabels: Set<String> = ["mute microphone", "unmute microphone", "将麦克风静音", "取消麦克风静音"]

struct Found {
    let element: AXUIElement
    let role: String
    let labels: [String]
}

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}

func str(_ e: AXUIElement, _ name: String) -> String? {
    guard let s = attr(e, name) as? String else { return nil }
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

func children(_ e: AXUIElement) -> [AXUIElement] {
    (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func labels(of e: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute]
        .compactMap { str(e, $0) }
}

/// 排查用：列出所有带标签的元素（任意角色）
func collectAll(_ axApp: AXUIElement, limit: Int = 80_000) -> [Found] {
    var queue: [AXUIElement] = (attr(axApp, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    var result: [Found] = []
    var i = 0
    while i < queue.count && i < limit {
        let e = queue[i]; i += 1
        let ls = labels(of: e)
        if !ls.isEmpty { result.append(Found(element: e, role: str(e, kAXRoleAttribute) ?? "?", labels: ls)) }
        queue.append(contentsOf: children(e))
    }
    return result
}

/// 广度优先遍历 ChatGPT 所有窗口，收集按钮类元素
func collectButtons(_ axApp: AXUIElement, limit: Int = 60_000) -> [Found] {
    var queue: [AXUIElement] = (attr(axApp, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    var result: [Found] = []
    var visited = 0
    var i = 0
    while i < queue.count && visited < limit {
        let e = queue[i]; i += 1; visited += 1
        let role = str(e, kAXRoleAttribute) ?? ""
        if role == "AXButton" || role == "AXCheckBox" || role == "AXMenuItem" {
            let ls = labels(of: e)
            if !ls.isEmpty { result.append(Found(element: e, role: role, labels: ls)) }
        }
        queue.append(contentsOf: children(e))
    }
    return result
}

func match(_ buttons: [Found], _ wanted: Set<String>) -> Found? {
    buttons.first { b in b.labels.contains { wanted.contains($0.lowercased()) } }
}

func actionNames(_ e: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyActionNames(e, &names)
    return (names as? [String]) ?? []
}

func frame(_ e: AXUIElement) -> CGRect? {
    var pos = CGPoint.zero, size = CGSize.zero
    guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return nil }
    AXValueGetValue(p as! AXValue, .cgPoint, &pos)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return size.width > 0 && size.height > 0 ? CGRect(origin: pos, size: size) : nil
}

/// 等热键的修饰键松开，否则按住 ⌃ 时的点击会变成右键
func waitForModifiersReleased(timeout: TimeInterval = 1.5) {
    let mask: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
    let deadline = Date().addingTimeInterval(timeout)
    while !CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty && Date() < deadline {
        usleep(30_000)
    }
}

/// 在屏幕坐标处合成一次左键点击，点完把鼠标放回原处
func click(at point: CGPoint) {
    waitForModifiersReleased()
    let original = CGEvent(source: nil)?.location ?? point
    let src = CGEventSource(stateID: .privateState)
    func post(_ type: CGEventType, _ at: CGPoint) {
        guard let ev = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: at, mouseButton: .left) else { return }
        ev.flags = []  // 明确不带任何修饰键
        ev.post(tap: .cghidEventTap)
    }
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        post(type, point)
        usleep(40_000)
    }
    post(.mouseMoved, original)
}

/// Chromium 给这些按钮暴露的动作里没有 AXPress，只能退回到真实鼠标点击
func press(_ f: Found) -> Bool {
    if actionNames(f.element).contains(kAXPressAction as String) {
        return AXUIElementPerformAction(f.element, kAXPressAction as CFString) == .success
    }
    guard let chatGPT = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
    chatGPT.activate()
    AXUIElementPerformAction(f.element, "AXScrollToVisible" as CFString)
    usleep(250_000)
    guard let r = frame(f.element) else { return false }
    let point = CGPoint(x: r.midX, y: r.midY)
    // 没切到前台或被别的窗口挡住时宁可不点，避免点到其它 App
    guard isTopmost(point, pid: chatGPT.processIdentifier) else { return false }
    click(at: point)
    return true
}

/// 该位置最上层的界面元素是否属于这个 App
func isTopmost(_ point: CGPoint, pid: pid_t) -> Bool {
    var element: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
          let element else { return false }
    var owner: pid_t = 0
    return AXUIElementGetPid(element, &owner) == .success && owner == pid
}

func fail(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

// ---- 全局热键守护进程 ----

/// 解析 "ctrl+opt+d" 这类写法为 Carbon 键码和修饰键
func parseHotkey(_ spec: String) -> (UInt32, UInt32)? {
    let keys: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]
    var mods: Int = 0
    var code: Int?
    for part in spec.lowercased().split(separator: "+").map(String.init) {
        switch part {
        case "cmd", "command": mods |= cmdKey
        case "opt", "option", "alt": mods |= optionKey
        case "ctrl", "control": mods |= controlKey
        case "shift": mods |= shiftKey
        default: code = keys[part]
        }
    }
    guard let code, mods != 0 else { return nil }
    return (UInt32(code), UInt32(mods))
}

var hotkeyActions: [UInt32: String] = [:]

func runSelf(_ action: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    p.arguments = [action]
    try? p.run()
}

func runDaemon(_ args: [String]) -> Never {
    func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    let bindings = [("toggle", value("--key") ?? "ctrl+opt+d"), ("mute", value("--mute-key"))]
    // 启动时就申请一次辅助功能权限，免得第一次按热键才弹窗
    _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)

    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
        var hk = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
        if let action = hotkeyActions[hk.id] { runSelf(action) }
        return noErr
    }, 1, &spec, nil, nil)

    var id: UInt32 = 0
    for (action, key) in bindings {
        guard let key else { continue }
        guard let (code, mods) = parseHotkey(key) else { fail("无法解析热键: \(key)") }
        id += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(code, mods, EventHotKeyID(signature: OSType(0x444F5443), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { fail("注册热键失败（可能被占用）: \(key)") }
        hotkeyActions[id] = action
        print("已注册 \(key) → \(action)")
    }
    NSApplication.shared.setActivationPolicy(.prohibited)
    NSApplication.shared.run()
    exit(0)
}

// ---- main ----

let args = Array(CommandLine.arguments.dropFirst())
let action = args.first { !$0.hasPrefix("--") } ?? "status"
let allowOpen = !args.contains("--no-open")

if action == "daemon" { runDaemon(args) }

guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) else {
    fail("没有辅助功能权限：请在 系统设置 → 隐私与安全性 → 辅助功能 中允许当前运行它的程序", code: 2)
}

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    fail("ChatGPT 没有在运行", code: 3)
}

let axApp = AXUIElementCreateApplication(app.processIdentifier)
// Electron/Chromium 默认不生成网页内容的无障碍树，需要手动打开
AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)

/// dot 的显示名：优先 --dot 参数，否则从 ~/.codex/.codex-global-state.json 读取主 dot
func dotName() -> String? {
    if let i = args.firstIndex(of: "--dot"), i + 1 < args.count { return args[i + 1] }
    let path = NSHomeDirectory() + "/.codex/.codex-global-state.json"
    guard let data = FileManager.default.contents(atPath: path),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let state = root["electron-persisted-atom-state"] as? [String: Any],
          let sel = ((state["primary-aeon-selection-v1"] as? [String: Any])?["response"] as? [String: Any])?["selection"] as? [String: Any],
          let threadID = sel["thread_id"] as? String,
          let profiles = (state["cloud-aeon-sidebar-cache-v1"] as? [String: Any])?["profilesByThreadId"] as? [String: Any],
          let profile = profiles[threadID] as? [String: Any]
    else { return nil }
    return profile["display_name"] as? String
}

/// 侧边栏里的 dot 条目，标签形如「嗨宝」或「嗨宝 Call in progress」
func sidebarRow(_ buttons: [Found], _ name: String) -> Found? {
    buttons.first { b in b.role == "AXButton" && b.labels.contains { $0 == name || $0.hasPrefix(name + " ") } }
}

func poll(_ wanted: Set<String>, _ seconds: TimeInterval) -> Found? {
    let deadline = Date().addingTimeInterval(seconds)
    repeat {
        if let f = match(collectButtons(axApp), wanted) { return f }
        Thread.sleep(forTimeInterval: 0.3)
    } while Date() < deadline
    return nil
}

/// 打开 dot 页面：先点侧边栏条目，侧边栏里没有就走 codex://dots
func openDotPage() {
    app.activate()
    if let name = dotName() {
        if let row = sidebarRow(collectButtons(axApp), name) { _ = press(row); return }
    }
    NSWorkspace.shared.open(URL(string: "codex://dots")!)
    Thread.sleep(forTimeInterval: 1.5)
    if let name = dotName(), let row = sidebarRow(collectButtons(axApp), name) { _ = press(row) }
}

/// 先在当前界面找，找不到就打开 dot 页面再找
func find(_ wanted: Set<String>, timeout: TimeInterval = 0.6) -> Found? {
    if let f = poll(wanted, timeout) { return f }
    guard allowOpen else { return nil }
    openDotPage()
    return poll(wanted, 6)
}

func inCallFromSidebar(_ buttons: [Found]) -> Bool {
    buttons.contains { $0.labels.contains { $0.contains("Call in progress") || $0.contains("通话中") } }
}

func describe(_ f: Found?) -> String {
    guard let f else { return "未找到" }
    return "\(f.role) \(f.labels)"
}

switch action {
case "dump":
    for b in collectButtons(axApp) { print("\(b.role)\t\(b.labels.joined(separator: " | "))") }

case "dumpall":
    for b in collectAll(axApp) { print("\(b.role)\t\(b.labels.joined(separator: " | "))") }

case "status", "locate":
    // status 只读当前界面；locate 会先切到 dot 页面，但同样不点呼叫/挂断
    if action == "locate" {
        openDotPage()
        _ = poll(startLabels.union(hangupLabels), 6)
    }
    let buttons = collectButtons(axApp)
    let hang = match(buttons, hangupLabels)
    print("dot 名字:  \(dotName() ?? "未知")")
    print("侧边栏条目: \(describe(dotName().flatMap { sidebarRow(buttons, $0) }))")
    print("呼叫按钮:  \(describe(match(buttons, startLabels)))")
    print("挂断按钮:  \(describe(hang))")
    print("静音按钮:  \(describe(match(buttons, muteLabels)))")
    print("通话状态:  \(hang != nil || inCallFromSidebar(buttons) ? "呼叫中/通话中" : "未在通话")")

case "start":
    if let h = match(collectButtons(axApp), hangupLabels) { print("已经在通话中: \(describe(h))"); exit(0) }
    guard let f = find(startLabels) else { fail("没找到呼叫按钮（dot 页面未显示？）", code: 4) }
    print(press(f) ? "已呼叫" : "点击失败")

case "hangup":
    guard let f = find(hangupLabels) else { fail("没找到挂断按钮（当前没有 dot 通话？）", code: 4) }
    print(press(f) ? "已挂断" : "点击失败")

case "toggle":
    let buttons = collectButtons(axApp)
    if let h = match(buttons, hangupLabels) {
        print(press(h) ? "已挂断" : "点击失败")
    } else if inCallFromSidebar(buttons) {
        // 正在通话但 dot 页面没打开：切过去再挂断
        guard let h = find(hangupLabels) else { fail("通话中，但没找到挂断按钮", code: 4) }
        print(press(h) ? "已挂断" : "点击失败")
    } else if let f = find(startLabels) {
        print(press(f) ? "已呼叫" : "点击失败")
    } else {
        fail("呼叫/挂断按钮都没找到", code: 4)
    }

case "mute":
    guard let f = find(muteLabels, timeout: 1) else { fail("没找到静音按钮（当前没有 dot 通话？）", code: 4) }
    print(press(f) ? "已切换静音: \(f.labels.first ?? "")" : "点击失败")

default:
    fail("未知动作: \(action)；可用 status/start/hangup/toggle/mute/dump")
}
