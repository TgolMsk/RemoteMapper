import Foundation

/// 一组按键映射。bundleIDs 为空的是全局配置；否则只在这些 App 位于前台时生效，
/// 未在其中设置的按钮会回落到全局配置。鼠标模式配置在触控板用作鼠标时优先于以上两者。
public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var bundleIDs: [String]
    /// 鼠标模式专属：触控板用途为「鼠标」时，其中设置的按键优先生效
    public var isPointerMode: Bool
    public var mappings: [RemoteButton: ButtonMapping]
    /// 触控手势的映射，每个手势对应一个动作
    public var touchMappings: [TouchGesture: BoundAction]

    public init(id: UUID = UUID(), name: String, bundleIDs: [String] = [], isPointerMode: Bool = false,
                mappings: [RemoteButton: ButtonMapping] = [:], touchMappings: [TouchGesture: BoundAction] = [:]) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.isPointerMode = isPointerMode
        self.mappings = mappings
        self.touchMappings = touchMappings
    }

    public var isGlobal: Bool { bundleIDs.isEmpty && !isPointerMode }

    public func mapping(for button: RemoteButton) -> ButtonMapping? {
        mappings[button].flatMap { $0.isEmpty ? nil : $0 }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, bundleIDs, mappings
        case isPointerMode = "pointerMode"
        case touchMappings = "touch"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        bundleIDs = try c.decodeIfPresent([String].self, forKey: .bundleIDs) ?? []
        isPointerMode = try c.decodeIfPresent(Bool.self, forKey: .isPointerMode) ?? false
        mappings = try c.decodeIfPresent([RemoteButton: ButtonMapping].self, forKey: .mappings) ?? [:]
        touchMappings = try c.decodeIfPresent([TouchGesture: BoundAction].self, forKey: .touchMappings) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(bundleIDs, forKey: .bundleIDs)
        if isPointerMode { try c.encode(true, forKey: .isPointerMode) }
        try c.encode(mappings, forKey: .mappings)
        if !touchMappings.isEmpty { try c.encode(touchMappings, forKey: .touchMappings) }
    }
}

public struct RemoteConfig: Codable, Hashable, Sendable {
    public var version: Int
    public var isEnabled: Bool
    /// 映射了音量、静音、播放键时，拦截它们原本的系统媒体键行为
    public var interceptSystemKeys: Bool
    public var longPressThreshold: Double
    public var doubleTapInterval: Double
    public var touch: TouchSettings
    public var voice: VoiceSettings
    public var profiles: [Profile]

    public static let currentVersion = 4

    public init(version: Int = RemoteConfig.currentVersion, isEnabled: Bool = true, interceptSystemKeys: Bool = true,
                longPressThreshold: Double = 0.45, doubleTapInterval: Double = 0.28, touch: TouchSettings = TouchSettings(),
                voice: VoiceSettings = VoiceSettings(), profiles: [Profile]) {
        self.version = version
        self.isEnabled = isEnabled
        self.interceptSystemKeys = interceptSystemKeys
        self.longPressThreshold = longPressThreshold
        self.doubleTapInterval = doubleTapInterval
        self.touch = touch
        self.voice = voice
        self.profiles = profiles
        ensureGlobalProfile()
    }

    public var globalProfile: Profile {
        get { profiles.first(where: \.isGlobal)! }
        set {
            if let index = profiles.firstIndex(where: \.isGlobal) { profiles[index] = newValue }
        }
    }

    public var gestureTiming: GestureTiming {
        GestureTiming(longPress: longPressThreshold, doubleTap: doubleTapInterval)
    }

    /// 是否有任何按键或触控手势绑定了语音输入
    public var usesDictation: Bool {
        func isDictation(_ action: Action) -> Bool {
            if case .dictation = action { return true }
            if case .sequence(let steps) = action { return steps.contains(where: isDictation) }
            return false
        }
        return profiles.contains { profile in
            profile.mappings.values.contains { mapping in RemoteGesture.allCases.contains { mapping[$0].map { isDictation($0.action) } ?? false } }
                || profile.touchMappings.values.contains { isDictation($0.action) }
        }
    }

    /// 鼠标模式配置
    public var pointerProfile: Profile? { profiles.first(where: \.isPointerMode) }

    /// 触控板当前是否用作鼠标
    public var isPointerModeActive: Bool { touch.isEnabled && touch.mode == .pointer }

    /// 前台 App 对应的专属配置
    public func appProfile(for bundleID: String?) -> Profile? {
        guard let bundleID else { return nil }
        return profiles.first { !$0.isGlobal && $0.bundleIDs.contains(bundleID) }
    }

    /// 解析某个按钮在当前前台 App 下实际生效的映射及其来源配置
    public func resolve(_ button: RemoteButton, frontmost bundleID: String?) -> (mapping: ButtonMapping, profile: Profile)? {
        if isPointerModeActive, let pointer = pointerProfile, let mapping = pointer.mapping(for: button) {
            return (mapping, pointer)
        }
        if let app = appProfile(for: bundleID), let mapping = app.mapping(for: button) {
            return (mapping, app)
        }
        let global = globalProfile
        return global.mapping(for: button).map { ($0, global) }
    }

    /// 解析触控手势在当前前台 App 下实际生效的动作及其来源配置
    public func resolve(_ gesture: TouchGesture, frontmost bundleID: String?) -> (action: BoundAction, profile: Profile)? {
        if let app = appProfile(for: bundleID), let action = app.touchMappings[gesture] {
            return (action, app)
        }
        let global = globalProfile
        return global.touchMappings[gesture].map { ($0, global) }
    }

    /// 旧版本配置升级（只填补空缺，不覆盖已有设置）：v1 → v2 补上默认的触控手势映射，v2 → v3 补上鼠标模式配置，
    /// v3 → v4 补上演示配置（已有 WPS 或 PowerPoint 的专属配置时不补）
    @discardableResult
    public mutating func migrate() -> Bool {
        guard version < Self.currentVersion else { return false }
        if version < 2 {
            let defaults = RemoteConfig.default
            for index in profiles.indices where profiles[index].touchMappings.isEmpty {
                let profile = profiles[index]
                let template = profile.isGlobal
                    ? defaults.globalProfile
                    : defaults.profiles.first { !$0.isGlobal && !Set($0.bundleIDs).isDisjoint(with: profile.bundleIDs) }
                profiles[index].touchMappings = template?.touchMappings ?? [:]
            }
        }
        if version < 3, pointerProfile == nil {
            profiles.append(RemoteConfig.defaultPointerProfile)
        }
        if version < 4 {
            let presentation = RemoteConfig.defaultPresentationProfile
            if !profiles.contains(where: { !Set($0.bundleIDs).isDisjoint(with: presentation.bundleIDs) }) {
                // 放在鼠标模式配置之前，与新装时的顺序一致
                profiles.insert(presentation, at: profiles.firstIndex(where: \.isPointerMode) ?? profiles.endIndex)
            }
        }
        version = Self.currentVersion
        return true
    }

    public subscript(profileID: UUID) -> Profile? {
        get { profiles.first { $0.id == profileID } }
        set {
            guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
            if let newValue { profiles[index] = newValue } else if !profiles[index].isGlobal { profiles.remove(at: index) }
        }
    }

    private mutating func ensureGlobalProfile() {
        if !profiles.contains(where: \.isGlobal) {
            profiles.insert(Profile(name: "全局"), at: 0)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version, isEnabled, interceptSystemKeys, longPressThreshold, doubleTapInterval, touch, voice, profiles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = RemoteConfig(profiles: [])
        // 没有版本号的手写配置视为最新格式
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        interceptSystemKeys = try c.decodeIfPresent(Bool.self, forKey: .interceptSystemKeys) ?? defaults.interceptSystemKeys
        longPressThreshold = try c.decodeIfPresent(Double.self, forKey: .longPressThreshold) ?? defaults.longPressThreshold
        doubleTapInterval = try c.decodeIfPresent(Double.self, forKey: .doubleTapInterval) ?? defaults.doubleTapInterval
        touch = try c.decodeIfPresent(TouchSettings.self, forKey: .touch) ?? defaults.touch
        voice = try c.decodeIfPresent(VoiceSettings.self, forKey: .voice) ?? defaults.voice
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        ensureGlobalProfile()
    }
}

public extension RemoteConfig {
    /// 首次启动时的默认映射：方向键与确认/返回走通用导航，其余键面向 Claude / Codex 开发流程。
    static var `default`: RemoteConfig {
        func preset(_ id: String) -> BoundAction { Preset.find(id)!.bound }
        func key(_ combo: KeyCombo, _ title: String, _ symbol: String) -> BoundAction {
            BoundAction(.keystroke(combo), title: title, symbol: symbol)
        }

        let global = Profile(name: "全局", mappings: [
            .up: ButtonMapping(tap: key(.upArrow, "方向键", "arrow.up"), repeatWhileHeld: true),
            .down: ButtonMapping(tap: key(.downArrow, "方向键", "arrow.down"), repeatWhileHeld: true),
            .left: ButtonMapping(tap: key(.leftArrow, "方向键", "arrow.left"), repeatWhileHeld: true),
            .right: ButtonMapping(tap: key(.rightArrow, "方向键", "arrow.right"), repeatWhileHeld: true),
            .select: ButtonMapping(tap: key(.returnKey, "确认", "return")),
            .back: ButtonMapping(tap: key(.escape, "返回", "escape")),
            .siri: ButtonMapping(hold: preset("voice.dictation")),
            .tv: ButtonMapping(tap: preset("claudeDesktop.activate"),
                               doubleTap: preset("system.iTerm"),
                               longPress: preset("codex.activate")),
        ], touchMappings: [
            // 与 Mac 触控板的多指手势保持一致
            .swipeUp: preset("system.missionControl"),
            .swipeDown: preset("system.appExpose"),
            .swipeLeft: preset("system.spaceLeft"),
            .swipeRight: preset("system.spaceRight"),
            .rotateClockwise: preset("system.scrollDown"),
            .rotateCounterclockwise: preset("system.scrollUp"),
        ])

        let terminal = Profile(name: "终端", bundleIDs: [KnownApp.iTerm, KnownApp.terminal], mappings: [
            .siri: ButtonMapping(hold: preset("voice.dictation")),
            .playPause: ButtonMapping(tap: preset("claudeCode.cycleMode"), longPress: preset("claudeCode.interrupt")),
            .back: ButtonMapping(tap: preset("claudeCode.cancel")),
            .select: ButtonMapping(tap: preset("claudeCode.submit")),
        ], touchMappings: [
            .swipeLeft: preset("system.previousTab"),
            .swipeRight: preset("system.nextTab"),
        ])

        return RemoteConfig(profiles: [global, terminal, defaultPresentationProfile, defaultPointerProfile])
    }

    /// 演示配置（WPS、PowerPoint 放映快捷键相同）：播放键单击从当前页放映、长按从头放映，
    /// 按下触控板翻到下一页，返回键结束放映，触控板左右滑动翻页。
    /// 方向键沿用全局的映射，放映时本来就是翻页。WPS 的文字、表格与演示是同一个 App，
    /// 所以只映射在文稿里也无害的键：黑屏、白屏这类字母键不放进来
    static var defaultPresentationProfile: Profile {
        func preset(_ id: String) -> BoundAction { Preset.find(id)!.bound }
        return Profile(name: "演示", bundleIDs: [KnownApp.wps, KnownApp.powerPoint], mappings: [
            .playPause: ButtonMapping(tap: preset("presentation.fromCurrent"), longPress: preset("presentation.fromBeginning")),
            .select: ButtonMapping(tap: preset("presentation.next")),
            .back: ButtonMapping(tap: preset("presentation.end")),
        ], touchMappings: [
            .swipeLeft: preset("presentation.previous"),
            .swipeRight: preset("presentation.next"),
        ])
    }

    /// 鼠标模式的默认映射：侧面 Siri 键单击为确定（左键单击）、双击在光标与滚轮之间切换；
    /// 按下触控板为左键（可双击、按住可拖动），返回键为右键。
    /// 触控板四周按下在系统里是方向键，鼠标模式下拇指常停在右侧滚动区或外圈，所以四周按下也当左键。
    /// 触控面只支持单指，拇指在触控面上时按不到其它键，所以滚轮用开关而不是按住
    static var defaultPointerProfile: Profile {
        func preset(_ id: String) -> BoundAction { Preset.find(id)!.bound }
        var confirm = preset("mouse.left")
        confirm.title = "确定"
        return Profile(name: "鼠标模式", isPointerMode: true, mappings: [
            .select: ButtonMapping(hold: preset("mouse.left")),
            .up: ButtonMapping(hold: preset("mouse.left")),
            .down: ButtonMapping(hold: preset("mouse.left")),
            .left: ButtonMapping(hold: preset("mouse.left")),
            .right: ButtonMapping(hold: preset("mouse.left")),
            .siri: ButtonMapping(tap: confirm, doubleTap: preset("mouse.scrollToggle")),
            .back: ButtonMapping(tap: preset("mouse.right")),
        ])
    }
}
