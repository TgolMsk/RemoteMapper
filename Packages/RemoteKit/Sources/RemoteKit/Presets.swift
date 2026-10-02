import Carbon.HIToolbox
import Foundation

public enum KnownApp {
    public static let claudeDesktop = "com.anthropic.claudefordesktop"
    public static let codex = "com.openai.codex"
    public static let iTerm = "com.googlecode.iterm2"
    public static let terminal = "com.apple.Terminal"
}

/// 面向开发工具的预设动作。
public struct Preset: Identifiable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case voice, mouse, claudeCode, claudeDesktop, codex, dot, system

        public var displayName: String {
            switch self {
            case .voice: "语音输入"
            case .mouse: "触控鼠标"
            case .claudeCode: "Claude Code · 终端"
            case .claudeDesktop: "Claude 桌面版"
            case .codex: "Codex"
            case .dot: "ChatGPT · dot"
            case .system: "系统"
            }
        }
    }

    public let id: String
    public let group: Group
    public let title: String
    public let detail: String
    public let symbol: String
    public let action: Action
    /// 预设更适合绑定的手势，例如按住说话应绑定到「按住」
    public let preferredGesture: RemoteGesture?

    public var bound: BoundAction { BoundAction(action, title: title, symbol: symbol, presetID: id) }

    public static func find(_ id: String) -> Preset? { all.first { $0.id == id } }

    public static let all: [Preset] = [
        // 语音输入：本机识别，不依赖任何 App 自带的语音功能
        Preset(id: "voice.dictation", group: .voice, title: "语音输入",
               detail: "按住说话，松开后把识别出的文字输入到当前 App", symbol: "mic.fill",
               action: .dictation(submit: false), preferredGesture: .hold),
        Preset(id: "voice.dictationSubmit", group: .voice, title: "语音输入并发送",
               detail: "按住说话，松开后输入文字并按 ↩ 发送", symbol: "paperplane.fill",
               action: .dictation(submit: true), preferredGesture: .hold),

        // 触控鼠标：在「通用 › 触控」中把用途切换为「鼠标」后，单指在触控面上移动光标
        Preset(id: "mouse.left", group: .mouse, title: "鼠标左键",
               detail: "按下即按住，配合触控移动可拖动；快速按两下即双击", symbol: "cursorarrow.click",
               action: .mouseButton(.left), preferredGesture: .hold),
        Preset(id: "mouse.right", group: .mouse, title: "鼠标右键",
               detail: "打开右键菜单；按住时配合触控移动可右键拖动", symbol: "contextualmenu.and.cursorarrow",
               action: .mouseButton(.right), preferredGesture: .hold),
        Preset(id: "mouse.middle", group: .mouse, title: "鼠标中键",
               detail: "例如在浏览器中用新标签页打开链接", symbol: "computermouse",
               action: .mouseButton(.middle), preferredGesture: .hold),
        Preset(id: "mouse.scroll", group: .mouse, title: "按住滚动",
               detail: "按住时在触控面上滑动即滚动，内容跟随手指", symbol: "arrow.up.and.down.and.arrow.left.and.right",
               action: .pointerScroll, preferredGesture: .hold),
        Preset(id: "mouse.scrollToggle", group: .mouse, title: "切换滚轮",
               detail: "在光标与滚轮之间切换；滚轮时在触控面上滑动即翻页，松手后带惯性", symbol: "scroll",
               action: .pointerScroll, preferredGesture: .doubleTap),
        Preset(id: "mouse.toggleMode", group: .mouse, title: "切换触控鼠标",
               detail: "在触控手势与鼠标之间切换", symbol: "cursorarrow.motionlines",
               action: .toggleTouchMode, preferredGesture: nil),

        // Claude Code：默认键位来自 https://code.claude.com/docs/en/keybindings
        Preset(id: "claudeCode.voice", group: .claudeCode, title: "按住说话",
               detail: "按住 Space 说话、松开结束，需先执行 /voice 开启",
               symbol: "waveform", action: .holdKey(.space), preferredGesture: .hold),
        Preset(id: "claudeCode.submit", group: .claudeCode, title: "发送",
               detail: "↩ 提交当前输入", symbol: "arrow.up.circle.fill",
               action: .keystroke(.returnKey), preferredGesture: nil),
        Preset(id: "claudeCode.cancel", group: .claudeCode, title: "中断回复",
               detail: "esc 打断 Claude 当前的输出", symbol: "stop.circle.fill",
               action: .keystroke(.escape), preferredGesture: nil),
        Preset(id: "claudeCode.cycleMode", group: .claudeCode, title: "切换权限模式",
               detail: "⇧⇥ 在默认 / 自动接受 / 计划模式间循环", symbol: "shield.lefthalf.filled",
               action: .keystroke(KeyCombo(keyCode: UInt16(kVK_Tab), modifiers: .shift)), preferredGesture: nil),
        Preset(id: "claudeCode.interrupt", group: .claudeCode, title: "终止操作",
               detail: "⌃C 取消当前操作", symbol: "xmark.octagon.fill",
               action: .keystroke(KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifiers: .control)), preferredGesture: nil),
        Preset(id: "claudeCode.historyPrevious", group: .claudeCode, title: "上一条历史",
               detail: "↑ 回到上一条输入", symbol: "clock.arrow.circlepath",
               action: .keystroke(.upArrow), preferredGesture: nil),

        // Claude 桌面版：快速输入需在 App 设置中开启，https://support.claude.com/en/articles/12626668
        Preset(id: "claudeDesktop.activate", group: .claudeDesktop, title: "切换到 Claude",
               detail: "启动或切换到 Claude 桌面版", symbol: "bubble.left.and.text.bubble.right.fill",
               action: .launchApp(bundleID: KnownApp.claudeDesktop), preferredGesture: nil),
        Preset(id: "claudeDesktop.newChat", group: .claudeDesktop, title: "新建对话",
               detail: "打开 claude://claude.ai/new", symbol: "square.and.pencil",
               action: .openURL("claude://claude.ai/new"), preferredGesture: nil),
        Preset(id: "claudeDesktop.quickEntry", group: .claudeDesktop, title: "快速输入",
               detail: "模拟连按两次 ⌥ 唤出快速输入框", symbol: "character.cursor.ibeam",
               action: .sequence([.keystroke(.option), .delay(milliseconds: 70), .keystroke(.option)]),
               preferredGesture: nil),

        // Codex
        Preset(id: "codex.activate", group: .codex, title: "切换到 Codex",
               detail: "启动或切换到 Codex", symbol: "chevron.left.forwardslash.chevron.right",
               action: .launchApp(bundleID: KnownApp.codex), preferredGesture: nil),
        Preset(id: "codex.open", group: .codex, title: "打开 codex://",
               detail: "通过 URL Scheme 唤起 Codex", symbol: "link",
               action: .openURL("codex://"), preferredGesture: nil),

        // ChatGPT dot：没有官方接口，通过辅助功能点击 dot 页面上的通话按钮
        Preset(id: "dot.toggleCall", group: .dot, title: "呼叫 / 挂断 dot",
               detail: "没有通话时呼叫 dot，通话中再按一次挂断", symbol: "phone.arrow.up.right.fill",
               action: .dotCall(.toggle), preferredGesture: nil),
        Preset(id: "dot.hangUp", group: .dot, title: "挂断 dot",
               detail: "结束当前与 dot 的通话", symbol: "phone.down.fill",
               action: .dotCall(.hangUp), preferredGesture: nil),
        Preset(id: "dot.toggleMute", group: .dot, title: "dot 通话静音",
               detail: "切换通话中的麦克风静音", symbol: "mic.slash.fill",
               action: .dotCall(.toggleMute), preferredGesture: nil),

        // 系统
        Preset(id: "system.iTerm", group: .system, title: "切换到 iTerm",
               detail: "启动或切换到 iTerm", symbol: "apple.terminal.fill",
               action: .launchApp(bundleID: KnownApp.iTerm), preferredGesture: nil),
        Preset(id: "system.previousApp", group: .system, title: "上一个 App",
               detail: "⌘⇥ 切回刚才使用的 App", symbol: "arrow.left.arrow.right",
               action: .keystroke(KeyCombo(keyCode: UInt16(kVK_Tab), modifiers: .command)), preferredGesture: nil),
        Preset(id: "system.missionControl", group: .system, title: "调度中心",
               detail: "⌃↑ 查看所有窗口", symbol: "rectangle.3.group",
               action: .keystroke(KeyCombo(keyCode: UInt16(kVK_UpArrow), modifiers: .control)), preferredGesture: nil),
        Preset(id: "system.appExpose", group: .system, title: "应用窗口",
               detail: "⌃↓ 查看当前 App 的所有窗口", symbol: "rectangle.stack",
               action: .keystroke(KeyCombo(keyCode: UInt16(kVK_DownArrow), modifiers: .control)), preferredGesture: nil),
        Preset(id: "system.spaceLeft", group: .system, title: "左侧桌面",
               detail: "⌃← 切换到左边的桌面空间", symbol: "rectangle.lefthalf.inset.filled.arrow.left",
               action: .keystroke(KeyCombo(keyCode: UInt16(kVK_LeftArrow), modifiers: .control)), preferredGesture: nil),
        Preset(id: "system.spaceRight", group: .system, title: "右侧桌面",
               detail: "⌃→ 切换到右边的桌面空间", symbol: "rectangle.righthalf.inset.filled.arrow.right",
               action: .keystroke(KeyCombo(keyCode: UInt16(kVK_RightArrow), modifiers: .control)), preferredGesture: nil),
        Preset(id: "system.previousTab", group: .system, title: "上一个标签页",
               detail: "⌘⇧[ 适用于 iTerm、终端与浏览器", symbol: "chevron.left.square",
               action: .keystroke(KeyCombo(keyCode: UInt16(kVK_ANSI_LeftBracket), modifiers: [.command, .shift])),
               preferredGesture: nil),
        Preset(id: "system.nextTab", group: .system, title: "下一个标签页",
               detail: "⌘⇧] 适用于 iTerm、终端与浏览器", symbol: "chevron.right.square",
               action: .keystroke(KeyCombo(keyCode: UInt16(kVK_ANSI_RightBracket), modifiers: [.command, .shift])),
               preferredGesture: nil),
        Preset(id: "system.scrollUp", group: .system, title: "向上滚动",
               detail: "滚动 3 行，适合绑定到转动", symbol: "chevron.up.2",
               action: .scroll(.up, lines: 3), preferredGesture: nil),
        Preset(id: "system.scrollDown", group: .system, title: "向下滚动",
               detail: "滚动 3 行，适合绑定到转动", symbol: "chevron.down.2",
               action: .scroll(.down, lines: 3), preferredGesture: nil),
        // 电源：锁屏与休眠可直接触发；重启与关机只通过电源菜单二次选择，避免误触
        Preset(id: "system.lockScreen", group: .system, title: "锁屏",
               detail: "⌃⌘Q 锁定屏幕", symbol: "lock.fill",
               action: .system(.lockScreen), preferredGesture: nil),
        Preset(id: "system.sleep", group: .system, title: "休眠",
               detail: "让 Mac 进入睡眠", symbol: "moon.zzz.fill",
               action: .system(.sleep), preferredGesture: nil),
        Preset(id: "system.powerMenu", group: .system, title: "电源菜单",
               detail: "屏幕提示后，再长按为关机、双击为重启，其它键取消", symbol: "power",
               action: .system(.powerMenu), preferredGesture: .longPress),
        Preset(id: "system.spotlight", group: .system, title: "聚焦搜索",
               detail: "⌘Space 打开 Spotlight", symbol: "magnifyingglass",
               action: .keystroke(KeyCombo(keyCode: UInt16(kVK_Space), modifiers: .command)), preferredGesture: nil),
    ]
}
