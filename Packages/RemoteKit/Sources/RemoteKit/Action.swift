import Foundation

/// 遥控器手势触发的动作。JSON 中以 "type" 字段区分类型，便于手工编辑配置文件。
public indirect enum Action: Hashable, Sendable {
    /// 按一次组合键
    case keystroke(KeyCombo)
    /// 在「按住」手势期间保持按下，并按系统键盘重复速率模拟自动重复（终端里的按住说话依赖它）
    case holdKey(KeyCombo)
    /// 输入一段文字，可选输入后按回车
    case text(String, submit: Bool)
    /// 按行滚动，例如沿触控板外圈转动时滚动终端输出
    case scroll(ScrollDirection, lines: Int)
    /// 语音输入：用 Mac 的麦克风录音并在本机识别，结束后把文字输入到当前 App。
    /// 绑定到「按住」时按下开始、松开结束；绑定到其它手势时按一次开始、再按一次结束
    case dictation(submit: Bool)
    /// 打开链接，例如 claude://claude.ai/new
    case openURL(String)
    /// 启动或切换到某个 App
    case launchApp(bundleID: String)
    /// 用登录 shell（zsh -lc）执行命令
    case shell(String)
    /// 执行 AppleScript
    case appleScript(String)
    /// 操作 ChatGPT 桌面版里 dot 的语音通话：通过辅助功能点击 dot 页面上的通话按钮
    case dotCall(DotCallOperation)
    /// 鼠标按键。绑定到「按住」时按下即按住、松开即松开，配合触控鼠标移动即拖动；绑定到其它手势时单击
    case mouseButton(MouseButton)
    /// 按住滚动：按住期间在触控面上滑动改为滚动；绑定到其它手势时每按一次开关一次
    case pointerScroll
    /// 在触控手势与触控鼠标之间切换
    case toggleTouchMode
    /// 锁屏、休眠、重启、关机，或弹出电源菜单（再选择重启或关机）
    case system(SystemCommand)
    /// 依次执行多个动作
    case sequence([Action])
    /// 在组合动作中等待
    case delay(milliseconds: Int)

    public var kind: Kind {
        switch self {
        case .keystroke: .keystroke
        case .holdKey: .holdKey
        case .text: .text
        case .scroll: .scroll
        case .dictation: .dictation
        case .openURL: .openURL
        case .launchApp: .launchApp
        case .shell: .shell
        case .appleScript: .appleScript
        case .dotCall: .dotCall
        case .mouseButton: .mouseButton
        case .pointerScroll: .pointerScroll
        case .toggleTouchMode: .toggleTouchMode
        case .system: .system
        case .sequence: .sequence
        case .delay: .delay
        }
    }

    public enum Kind: String, CaseIterable, Sendable, Codable {
        case keystroke, holdKey, text, scroll, dictation, openURL, launchApp, shell, appleScript, dotCall
        case mouseButton, pointerScroll, toggleTouchMode, system, sequence, delay

        public var displayName: String {
            switch self {
            case .keystroke: "快捷键"
            case .holdKey: "按住按键"
            case .text: "输入文本"
            case .scroll: "滚动"
            case .dictation: "语音输入"
            case .openURL: "打开链接"
            case .launchApp: "打开 App"
            case .shell: "Shell 命令"
            case .appleScript: "AppleScript"
            case .dotCall: "dot 通话"
            case .mouseButton: "鼠标按键"
            case .pointerScroll: "按住滚动"
            case .toggleTouchMode: "切换触控鼠标"
            case .system: "电源与锁屏"
            case .sequence: "组合动作"
            case .delay: "等待"
            }
        }

        public var symbol: String {
            switch self {
            case .keystroke: "command"
            case .holdKey: "arrow.down.to.line"
            case .text: "text.cursor"
            case .scroll: "scroll"
            case .dictation: "mic.fill"
            case .openURL: "link"
            case .launchApp: "app.badge"
            case .shell: "terminal"
            case .appleScript: "applescript"
            case .dotCall: "phone.fill"
            case .mouseButton: "cursorarrow.click"
            case .pointerScroll: "arrow.up.and.down.and.arrow.left.and.right"
            case .toggleTouchMode: "cursorarrow.motionlines"
            case .system: "power"
            case .sequence: "list.number"
            case .delay: "hourglass"
            }
        }
    }
}

extension Action: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, key, keyCode, modifiers, text, submit, direction, lines, url, bundleID, command, source, operation, button, actions, ms
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(Kind.self, forKey: .type)
        switch type {
        case .keystroke: self = .keystroke(try KeyCombo(from: decoder))
        case .holdKey: self = .holdKey(try KeyCombo(from: decoder))
        case .text:
            self = .text(try c.decode(String.self, forKey: .text),
                         submit: try c.decodeIfPresent(Bool.self, forKey: .submit) ?? false)
        case .scroll:
            self = .scroll(try c.decode(ScrollDirection.self, forKey: .direction),
                           lines: try c.decodeIfPresent(Int.self, forKey: .lines) ?? 3)
        case .dictation:
            self = .dictation(submit: try c.decodeIfPresent(Bool.self, forKey: .submit) ?? false)
        case .openURL: self = .openURL(try c.decode(String.self, forKey: .url))
        case .launchApp: self = .launchApp(bundleID: try c.decode(String.self, forKey: .bundleID))
        case .shell: self = .shell(try c.decode(String.self, forKey: .command))
        case .appleScript: self = .appleScript(try c.decode(String.self, forKey: .source))
        case .dotCall: self = .dotCall(try c.decodeIfPresent(DotCallOperation.self, forKey: .operation) ?? .toggle)
        case .mouseButton: self = .mouseButton(try c.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left)
        case .pointerScroll: self = .pointerScroll
        case .toggleTouchMode: self = .toggleTouchMode
        case .system: self = .system(try c.decode(SystemCommand.self, forKey: .command))
        case .sequence: self = .sequence(try c.decode([Action].self, forKey: .actions))
        case .delay: self = .delay(milliseconds: try c.decode(Int.self, forKey: .ms))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .type)
        switch self {
        case .keystroke(let combo), .holdKey(let combo): try combo.encode(to: encoder)
        case .text(let text, let submit):
            try c.encode(text, forKey: .text)
            if submit { try c.encode(true, forKey: .submit) }
        case .scroll(let direction, let lines):
            try c.encode(direction, forKey: .direction)
            try c.encode(lines, forKey: .lines)
        case .dictation(let submit):
            if submit { try c.encode(true, forKey: .submit) }
        case .openURL(let url): try c.encode(url, forKey: .url)
        case .launchApp(let bundleID): try c.encode(bundleID, forKey: .bundleID)
        case .shell(let command): try c.encode(command, forKey: .command)
        case .appleScript(let source): try c.encode(source, forKey: .source)
        case .dotCall(let operation): try c.encode(operation, forKey: .operation)
        case .mouseButton(let button): try c.encode(button, forKey: .button)
        case .pointerScroll, .toggleTouchMode: break
        case .system(let command): try c.encode(command, forKey: .command)
        case .sequence(let actions): try c.encode(actions, forKey: .actions)
        case .delay(let ms): try c.encode(ms, forKey: .ms)
        }
    }
}

/// 系统电源相关的命令
public enum SystemCommand: String, CaseIterable, Codable, Sendable {
    case lockScreen, sleep, restart, shutDown
    /// 弹出提示，几秒内再长按为关机、双击为重启，其它键取消
    case powerMenu

    public var displayName: String {
        switch self {
        case .lockScreen: "锁屏"
        case .sleep: "休眠"
        case .restart: "重启"
        case .shutDown: "关机"
        case .powerMenu: "电源菜单"
        }
    }
}

public enum ScrollDirection: String, CaseIterable, Codable, Sendable {
    case up, down, left, right

    public var displayName: String {
        switch self {
        case .up: "向上"
        case .down: "向下"
        case .left: "向左"
        case .right: "向右"
        }
    }

    public var symbol: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }
}

/// 绑定到某个手势上的动作，附带可选的显示名称与图标（来自预设或用户自定义）。
public struct BoundAction: Codable, Hashable, Sendable {
    public var action: Action
    public var title: String?
    public var symbol: String?
    public var presetID: String?

    public init(_ action: Action, title: String? = nil, symbol: String? = nil, presetID: String? = nil) {
        self.action = action
        self.title = title
        self.symbol = symbol
        self.presetID = presetID
    }

    public var displayTitle: String { title?.nilIfBlank ?? action.kind.displayName }
    public var displaySymbol: String { symbol ?? action.kind.symbol }
}

public extension Action {
    /// 简短的动作说明，用于列表与日志
    var summary: String {
        switch self {
        case .keystroke(let combo), .holdKey(let combo): combo.displayString
        case .text(let text, let submit): "“\(text.prefix(24))”" + (submit ? " ↩" : "")
        case .scroll(let direction, let lines): "\(direction.displayName) \(lines) 行"
        case .dictation(let submit): submit ? "转文字后发送" : "转为文字"
        case .openURL(let url): url
        case .launchApp(let bundleID): bundleID
        case .shell(let command): command.split(separator: "\n").first.map(String.init) ?? ""
        case .appleScript(let source): source.split(separator: "\n").first.map(String.init) ?? ""
        case .dotCall(let operation): "dot · \(operation.displayName)"
        case .mouseButton(let button): "鼠标\(button.displayName)"
        case .pointerScroll: "按住时滑动即滚动"
        case .toggleTouchMode: "手势 ⇄ 鼠标"
        case .system(let command): command.displayName
        case .sequence(let actions): actions.filter { $0.kind != .delay }.map(\.summary).joined(separator: " → ")
        case .delay(let ms): "\(ms) ms"
        }
    }

    /// 鼠标点击与滚动不会把按键打进设置界面，设置窗口在前台时也照常执行，便于用遥控器操作设置界面
    var runsWhileSettingsFocused: Bool { kind == .mouseButton || kind == .pointerScroll }

    /// 组合键动作的键帽，其它类型返回 nil
    var keycaps: [String]? {
        switch self {
        case .keystroke(let combo), .holdKey(let combo):
            return combo.keycaps
        case .sequence(let actions):
            let steps = actions.filter { $0.kind != .delay }
            let combos = steps.compactMap(\.keycaps)
            return combos.count == steps.count ? combos.flatMap { $0 } : nil
        default:
            return nil
        }
    }
}

extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
