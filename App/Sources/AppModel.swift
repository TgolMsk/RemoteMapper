import AppKit
import Observation
import RemoteKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case mapping, general, diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mapping: "按键映射"
        case .general: "通用"
        case .diagnostics: "权限与诊断"
        }
    }
}

/// 映射页编辑的对象：实体按键或触控手势
enum MappingMode: String, CaseIterable, Identifiable {
    case buttons, touch

    var id: String { rawValue }
    var title: String { self == .buttons ? "按键" : "触控手势" }
    var symbol: String { self == .buttons ? "circle.grid.2x2" : "hand.draw" }
}

/// 一个可绑定动作的位置
enum EditorTarget: Hashable {
    case button(RemoteButton, RemoteGesture)
    case touch(TouchGesture)

    var title: String {
        switch self {
        case .button(let button, let gesture): "\(button.displayName) · \(gesture.displayName)"
        case .touch(let gesture): "触控 · \(gesture.displayName)"
        }
    }

    var detail: String {
        switch self {
        case .button(_, let gesture): gesture.detail
        case .touch(let gesture): gesture.detail
        }
    }

    var symbol: String {
        switch self {
        case .button(let button, _): button.symbol
        case .touch(let gesture): gesture.symbol
        }
    }
}

struct TouchPulse: Equatable {
    let gesture: TouchGesture
    let id = UUID()
}

/// 正在编辑的动作
struct EditorContext: Identifiable {
    let id = UUID()
    let profileID: UUID
    let target: EditorTarget
}

@Observable
final class AppModel {
    static let shared: AppModel = ProcessInfo.processInfo.arguments.contains("--snapshot") ? .preview() : AppModel()

    let store: ConfigStore
    let engine: RemoteEngine

    var tab: SettingsTab = .mapping
    var mappingMode: MappingMode = .buttons
    var selectedButton: RemoteButton = .siri
    /// 最近一次识别出的触控手势，用于界面上的瞬时反馈
    private(set) var lastTouch: TouchPulse?
    var selectedProfileID: UUID
    var editor: EditorContext?
    var isSettingsKey = false
    private(set) var hasAccessibility = ActionRunner.hasAccessibility
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private var permissionTimer: Timer?

    init(store: ConfigStore = ConfigStore(), device: RemoteDevice = RemoteDevice(),
         touch: (any TouchSource)? = Edition.makeTouchSource(), startsEngine: Bool = true) {
        self.store = store
        engine = RemoteEngine(store: store, device: device, touch: touch)
        engine.runner.unsupportedKinds = Edition.unsupportedActions
        engine.runner.scriptExecutor = Edition.scriptExecutor
        selectedProfileID = store.config.globalProfile.id
        store.onChange = { [weak self] _ in self?.engine.configDidChange() }
        engine.isPreviewOnly = { [weak self] in self?.isSettingsKey ?? false }
        engine.onButtonDown = { [weak self] button in
            // 设置窗口在前台时，按遥控器上的键即可直接选中它
            guard let self, self.isSettingsKey else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                self.tab = .mapping
                self.mappingMode = .buttons
                self.selectedButton = button
            }
        }
        engine.onTouchGesture = { [weak self] gesture in
            guard let self else { return }
            self.lastTouch = TouchPulse(gesture: gesture)
            guard self.isSettingsKey else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                self.tab = .mapping
                self.mappingMode = .touch
            }
        }
        if startsEngine {
            engine.start()
            watchPermissions()
        }
    }

    // MARK: 配置访问

    var config: RemoteConfig {
        get { store.config }
        set { store.config = newValue }
    }

    var selectedProfile: Profile {
        config[selectedProfileID] ?? config.globalProfile
    }

    /// 当前前台 App 下实际生效的配置
    var activeProfile: Profile {
        config.appProfile(for: engine.frontmostBundleID) ?? config.globalProfile
    }

    func mapping(_ button: RemoteButton, in profileID: UUID) -> ButtonMapping? {
        config[profileID]?.mapping(for: button)
    }

    func setMapping(_ mapping: ButtonMapping?, for button: RemoteButton, in profileID: UUID) {
        guard var profile = config[profileID] else { return }
        profile.mappings[button] = (mapping?.isEmpty ?? true) ? nil : mapping
        config[profileID] = profile
    }

    func setAction(_ bound: BoundAction?, for gesture: RemoteGesture, button: RemoteButton, in profileID: UUID) {
        var mapping = mapping(button, in: profileID) ?? inheritedMapping(button, for: profileID) ?? ButtonMapping()
        mapping[gesture] = bound
        setMapping(mapping, for: button, in: profileID)
    }

    /// 某个位置在指定配置中自己的动作（不含沿用全局的部分）
    func ownAction(_ target: EditorTarget, in profileID: UUID) -> BoundAction? {
        switch target {
        case .button(let button, let gesture): mapping(button, in: profileID)?[gesture]
        case .touch(let gesture): config[profileID]?.touchMappings[gesture]
        }
    }

    /// 某个位置在指定配置中实际显示的动作：自己的，或沿用全局的
    func effectiveAction(_ target: EditorTarget, in profileID: UUID) -> BoundAction? {
        switch target {
        case .button(let button, let gesture):
            (mapping(button, in: profileID) ?? inheritedMapping(button, for: profileID))?[gesture]
        case .touch(let gesture):
            config[profileID]?.touchMappings[gesture] ?? inheritedTouch(gesture, for: profileID)
        }
    }

    func setAction(_ bound: BoundAction?, for target: EditorTarget, in profileID: UUID) {
        switch target {
        case .button(let button, let gesture):
            setAction(bound, for: gesture, button: button, in: profileID)
        case .touch(let gesture):
            guard var profile = config[profileID] else { return }
            profile.touchMappings[gesture] = bound
            config[profileID] = profile
        }
    }

    /// App 配置中未设置的触控手势沿用的全局动作
    func inheritedTouch(_ gesture: TouchGesture, for profileID: UUID) -> BoundAction? {
        guard let profile = config[profileID], !profile.isGlobal else { return nil }
        return config.globalProfile.touchMappings[gesture]
    }

    /// App 配置中未覆盖的按钮沿用的全局映射
    func inheritedMapping(_ button: RemoteButton, for profileID: UUID) -> ButtonMapping? {
        guard let profile = config[profileID], !profile.isGlobal else { return nil }
        return config.globalProfile.mapping(for: button)
    }

    func addAppProfile(bundleID: String) {
        if let existing = config.appProfile(for: bundleID) {
            selectedProfileID = existing.id
            return
        }
        let profile = Profile(name: AppInfo.name(for: bundleID), bundleIDs: [bundleID])
        config.profiles.append(profile)
        selectedProfileID = profile.id
    }

    func deleteProfile(_ id: UUID) {
        config[id] = nil
        selectedProfileID = config.globalProfile.id
    }

    // MARK: 系统

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func requestAccessibility() {
        // 沙盒中无法弹出系统授权框，直接打开系统设置让用户手动添加
        let options = ["AXTrustedCheckOptionPrompt": !Edition.isAppStore] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    /// 授权状态没有通知，定时检查；获得授权后启动媒体键拦截
    private func watchPermissions() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let trusted = ActionRunner.hasAccessibility
                if trusted != self.hasAccessibility {
                    self.hasAccessibility = trusted
                    if trusted { self.engine.startInterceptorIfPossible() }
                }
            }
        }
    }
}

// MARK: - 预览数据（截图与 SwiftUI 预览）

extension AppModel {
    static func preview(pressed: Set<RemoteButton> = [.siri], touches: [TouchContact] = []) -> AppModel {
        let store = ConfigStore(fileURL: URL(fileURLWithPath: "/dev/null"), persists: false, initial: .default)
        let device = RemoteDevice()
        device.simulate(connected: true, pressed: pressed, productName: "C08KJ2532330")
        let model = AppModel(store: store, device: device, touch: Edition.makePreviewTouchSource(contacts: touches),
                             startsEngine: false)
        model.hasAccessibility = true
        model.engine.battery.simulate(level: 82)
        let now = Date()
        let touchEntry = LogEntry(date: now, button: nil, gesture: nil, touch: .swipeRight, title: "下一个标签页", kind: .action)
        model.engine.appendPreviewLog((Edition.supportsTouch ? [touchEntry] : []) + [
            LogEntry(date: now.addingTimeInterval(-2), button: .siri, gesture: .hold, title: "按住说话", kind: .action),
            LogEntry(date: now.addingTimeInterval(-4), button: .playPause, gesture: .tap, title: "切换权限模式", kind: .action),
            LogEntry(date: now.addingTimeInterval(-9), button: .tv, gesture: .longPress, title: "切换到 Codex", kind: .action),
            LogEntry(date: now.addingTimeInterval(-15), button: .volumeUp, gesture: nil, title: "未映射 · 系统默认", kind: .passthrough),
        ], frontmost: KnownApp.iTerm)
        return model
    }
}

/// App 名称与图标查询
enum AppInfo {
    @MainActor private static var iconCache: [String: NSImage] = [:]

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else { return bundleID.components(separatedBy: ".").last ?? bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        guard let url = url(for: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = icon
        return icon
    }
}
