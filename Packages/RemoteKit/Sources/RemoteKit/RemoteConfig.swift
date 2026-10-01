import Foundation

/// 一组按键映射。bundleIDs 为空的是全局配置；否则只在这些 App 位于前台时生效，
/// 未在其中设置的按钮会回落到全局配置。
public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var bundleIDs: [String]
    public var mappings: [RemoteButton: ButtonMapping]

    public init(id: UUID = UUID(), name: String, bundleIDs: [String] = [], mappings: [RemoteButton: ButtonMapping] = [:]) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.mappings = mappings
    }

    public var isGlobal: Bool { bundleIDs.isEmpty }

    public func mapping(for button: RemoteButton) -> ButtonMapping? {
        mappings[button].flatMap { $0.isEmpty ? nil : $0 }
    }

    private enum CodingKeys: String, CodingKey { case id, name, bundleIDs, mappings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        bundleIDs = try c.decodeIfPresent([String].self, forKey: .bundleIDs) ?? []
        mappings = try c.decodeIfPresent([RemoteButton: ButtonMapping].self, forKey: .mappings) ?? [:]
    }
}

public struct RemoteConfig: Codable, Hashable, Sendable {
    public var version: Int
    public var isEnabled: Bool
    /// 映射了音量、静音、播放键时，拦截它们原本的系统媒体键行为
    public var interceptSystemKeys: Bool
    public var longPressThreshold: Double
    public var doubleTapInterval: Double
    public var profiles: [Profile]

    public init(version: Int = 1, isEnabled: Bool = true, interceptSystemKeys: Bool = true,
                longPressThreshold: Double = 0.45, doubleTapInterval: Double = 0.28, profiles: [Profile]) {
        self.version = version
        self.isEnabled = isEnabled
        self.interceptSystemKeys = interceptSystemKeys
        self.longPressThreshold = longPressThreshold
        self.doubleTapInterval = doubleTapInterval
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

    /// 前台 App 对应的专属配置
    public func appProfile(for bundleID: String?) -> Profile? {
        guard let bundleID else { return nil }
        return profiles.first { !$0.isGlobal && $0.bundleIDs.contains(bundleID) }
    }

    /// 解析某个按钮在当前前台 App 下实际生效的映射及其来源配置
    public func resolve(_ button: RemoteButton, frontmost bundleID: String?) -> (mapping: ButtonMapping, profile: Profile)? {
        if let app = appProfile(for: bundleID), let mapping = app.mapping(for: button) {
            return (mapping, app)
        }
        let global = globalProfile
        return global.mapping(for: button).map { ($0, global) }
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
        case version, isEnabled, interceptSystemKeys, longPressThreshold, doubleTapInterval, profiles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = RemoteConfig(profiles: [])
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? defaults.version
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        interceptSystemKeys = try c.decodeIfPresent(Bool.self, forKey: .interceptSystemKeys) ?? defaults.interceptSystemKeys
        longPressThreshold = try c.decodeIfPresent(Double.self, forKey: .longPressThreshold) ?? defaults.longPressThreshold
        doubleTapInterval = try c.decodeIfPresent(Double.self, forKey: .doubleTapInterval) ?? defaults.doubleTapInterval
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
            .siri: ButtonMapping(tap: preset("claudeDesktop.quickEntry")),
            .tv: ButtonMapping(tap: preset("claudeDesktop.activate"),
                               doubleTap: preset("system.iTerm"),
                               longPress: preset("codex.activate")),
        ])

        let terminal = Profile(name: "终端", bundleIDs: [KnownApp.iTerm, KnownApp.terminal], mappings: [
            .siri: ButtonMapping(hold: preset("claudeCode.voice")),
            .playPause: ButtonMapping(tap: preset("claudeCode.cycleMode"), longPress: preset("claudeCode.interrupt")),
            .back: ButtonMapping(tap: preset("claudeCode.cancel")),
            .select: ButtonMapping(tap: preset("claudeCode.submit")),
        ])

        return RemoteConfig(profiles: [global, terminal])
    }
}
