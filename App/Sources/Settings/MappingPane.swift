import AppKit
import RemoteKit
import SwiftUI

/// 「按键映射」页：配置切换、选中按键的四种手势绑定。
struct MappingPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !model.hasAccessibility { AccessibilityBanner() }
                ProfileStrip()
                if model.selectedProfile.isPointerMode { PointerModeSwitch() }
                MappingModeSwitch()
                switch model.mappingMode {
                case .buttons:
                    ButtonHeader(button: model.selectedButton)
                    GestureCard(button: model.selectedButton)
                    OptionsCard(button: model.selectedButton)
                case .touch:
                    TouchHeader()
                    if model.selectedProfile.isPointerMode {
                        Text(L10n.text("鼠标模式下触控板用于移动光标，没有触控手势。在「按键」中设置鼠标模式下各个键的作用。"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(padding: 18)
                    } else {
                        TouchCard()
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 36)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.selectedButton)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.selectedProfileID)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.mappingMode)
        }
        .scrollIndicators(.never)
    }
}

// MARK: - 权限提示

struct AccessibilityBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.warning.gradient, in: .rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("需要「辅助功能」权限")).font(.system(size: 13, weight: .semibold))
                Text(L10n.text("授权后才能模拟按键、拦截系统媒体键。打开链接、运行命令不受影响。"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.text("前往授权")) { model.requestAccessibility() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.warning)
        }
        .padding(14)
        .background(Theme.warning.opacity(0.10), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.warning.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - 配置切换

struct ProfileStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selected = model.selectedProfile
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("配置")).eyebrowStyle().padding(.horizontal, 4)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.config.profiles) { profile in
                        ProfilePill(profile: profile,
                                    isSelected: profile.id == model.selectedProfileID,
                                    isActive: profile.id == model.activeProfile.id && model.config.isEnabled)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.selectedProfileID = profile.id }
                            }
                            .contextMenu {
                                if !profile.isGlobal, !profile.isPointerMode {
                                    Button(L10n.format("删除「%@」配置", String(profile.displayName)), role: .destructive) { model.deleteProfile(profile.id) }
                                }
                            }
                    }
                    AddProfileButton()
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.never)

            Text(profileCaption(selected))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .contentTransition(.opacity)
        }
    }

    private func profileCaption(_ profile: Profile) -> String {
        if profile.isGlobal { return L10n.text("在任何 App 中生效。App 专属配置中未设置的按键，也会沿用这里的设置。") }
        if profile.isPointerMode {
            return L10n.text("触控板用途为「鼠标」时生效，优先于 App 专属配置；这里未设置的按键沿用原来的映射。")
                + (model.config.touch.mode == .pointer ? "" : L10n.text("当前为手势模式，未生效。"))
        }
        let names = profile.bundleIDs.map(AppInfo.name(for:)).joined(separator: "、")
        return L10n.format("当 %@ 位于前台时生效，未设置的按键沿用全局。", String(names))
    }
}

struct ProfilePill: View {
    let profile: Profile
    let isSelected: Bool
    let isActive: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            icon.frame(width: 18, height: 18)
            Text(profile.displayName)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
            if isActive {
                Circle().fill(Theme.live).frame(width: 6, height: 6)
                    .help(L10n.text("当前生效中"))
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 13)
        .frame(height: 32)
        .background {
            Capsule().fill(isSelected ? Theme.accentFill : (isHovered ? Theme.rowHover : Theme.card))
        }
        .overlay {
            Capsule().strokeBorder(isSelected ? Theme.accent.opacity(0.55) : Theme.cardBorder, lineWidth: isSelected ? 1 : 0.5)
        }
        .foregroundStyle(isSelected ? Theme.accent : .primary)
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    @ViewBuilder private var icon: some View {
        if profile.isGlobal {
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .semibold))
        } else if profile.isPointerMode {
            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 12, weight: .semibold))
        } else if let bundleID = profile.bundleIDs.first, let image = AppInfo.icon(for: bundleID) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: "app.dashed")
        }
    }
}

struct AddProfileButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            let candidates = runningApps
            if !candidates.isEmpty {
                SwiftUI.Section(L10n.text("正在运行")) {
                    ForEach(candidates, id: \.bundleIdentifier) { app in
                        Button {
                            withAnimation { model.addAppProfile(bundleID: app.bundleIdentifier!) }
                        } label: {
                            if let icon = app.icon { Image(nsImage: resized(icon)) }
                            Text(app.localizedName ?? app.bundleIdentifier!)
                        }
                    }
                }
            }
            Divider()
            Button(L10n.text("从「应用程序」中选择…")) { chooseApp() }
        } label: {
            Label(L10n.text("App 专属配置"), systemImage: "plus")
                .font(.system(size: 12.5, weight: .medium))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 13)
        .frame(height: 32)
        .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Color.secondary.opacity(0.35)))
        .contentShape(Capsule())
    }

    private var runningApps: [NSRunningApplication] {
        let existing = Set(model.config.profiles.flatMap(\.bundleIDs))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier && !existing.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func resized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        withAnimation { model.addAppProfile(bundleID: bundleID) }
    }
}

// MARK: - 按键标题

struct ButtonHeader: View {
    @Environment(AppModel.self) private var model
    let button: RemoteButton

    private static let order: [RemoteButton] = [.siri, .power, .up, .right, .down, .left, .select, .back, .tv,
                                                 .playPause, .volumeUp, .volumeDown, .mute]

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            KeyGlyph(button: button, size: 58)
            VStack(alignment: .leading, spacing: 7) {
                Text(button.displayName)
                    .font(.system(size: 24, weight: .semibold))
                    .contentTransition(.opacity)
                HStack(spacing: 6) {
                    Tag(text: "HID \(button.hidUsage)", mono: true)
                    Tag(text: "bit \(button.bit)", mono: true)
                    scopeTag
                }
            }
            Spacer()
            HStack(spacing: 6) {
                stepButton("chevron.left", offset: -1)
                stepButton("chevron.right", offset: 1)
            }
        }
    }

    @ViewBuilder private var scopeTag: some View {
        let profile = model.selectedProfile
        if !profile.isGlobal {
            if model.mapping(button, in: profile.id) != nil {
                Tag(text: L10n.format("%@ 专属", String(profile.displayName)), tint: Theme.accent)
            } else {
                Tag(text: profile.isPointerMode ? L10n.text("沿用原映射") : L10n.text("沿用全局"))
            }
        }
    }

    private func stepButton(_ symbol: String, offset: Int) -> some View {
        Button {
            let index = Self.order.firstIndex(of: button)!
            let next = Self.order[(index + offset + Self.order.count) % Self.order.count]
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { model.selectedButton = next }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Theme.card, in: .circle)
                .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 0.5))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(offset < 0 ? L10n.text("上一个按键") : L10n.text("下一个按键"))
    }
}

/// 与遥控器上一致的黑色按键图标
struct KeyGlyph: View {
    let symbol: String
    var size: CGFloat

    init(symbol: String, size: CGFloat) {
        self.symbol = symbol
        self.size = size
    }

    init(button: RemoteButton, size: CGFloat) {
        self.init(symbol: button.symbol, size: size)
    }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

struct Tag: View {
    let text: String
    var mono = false
    var tint: Color?

    var body: some View {
        Text(text)
            .font(mono ? Theme.mono(10.5, weight: .medium) : .system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint ?? .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((tint.map { $0.opacity(0.12) } ?? Theme.subtleFill), in: .rect(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - 手势

struct GestureCard: View {
    @Environment(AppModel.self) private var model
    let button: RemoteButton

    /// 遥控器上刚触发的手势，对应行短暂高亮
    @State private var firing: RemoteGesture?

    var body: some View {
        let profileID = model.selectedProfileID
        let own = model.mapping(button, in: profileID)
        let inherited = own == nil ? model.inheritedMapping(button, for: profileID) : nil
        let mapping = own ?? inherited
        let holdTakesOver = mapping?.hold != nil

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("手势")).eyebrowStyle()
                Spacer()
                if inherited != nil {
                    Text(L10n.text("显示的是全局设置，编辑后将为此 App 单独保存"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(RemoteGesture.allCases) { gesture in
                    let isBlocked = holdTakesOver && gesture != .hold
                    BindingRow(title: gesture.displayName, detail: gesture.detail, symbol: gesture.symbol,
                               bound: isBlocked ? nil : mapping?[gesture],
                               isInherited: inherited != nil,
                               isBlocked: isBlocked,
                               isFiring: firing == gesture,
                               showsDivider: gesture != RemoteGesture.allCases.last) {
                        model.editor = EditorContext(profileID: profileID, target: .button(button, gesture))
                    } onClear: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            model.setAction(nil, for: gesture, button: button, in: profileID)
                        }
                    } onDropFile: { url in
                        model.bindSlides(url, to: .button(button, gesture), in: profileID)
                    }
                }
            }
            .card()
        }
        .onChange(of: model.engine.log.first?.id) {
            guard let entry = model.engine.log.first, entry.button == button, let gesture = entry.gesture else { return }
            withAnimation(.easeOut(duration: 0.12)) { firing = gesture }
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.5)) { if firing == gesture { firing = nil } }
            }
        }
    }
}

/// 一个可绑定动作的行：图标、名称、说明，右侧为动作摘要或「添加动作」。
/// 把演示文稿拖到行上即绑定为「放映演示文稿」
struct BindingRow: View {
    let title: String
    let detail: String
    let symbol: String
    let bound: BoundAction?
    let isInherited: Bool
    let isBlocked: Bool
    var isFiring = false
    let showsDivider: Bool
    let onEdit: () -> Void
    let onClear: () -> Void
    /// 拖入文件，接受时返回 true
    let onDropFile: (URL) -> Bool

    @State private var isHovered = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(bound != nil ? Theme.accent : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(bound != nil ? Theme.accentFill : Theme.subtleFill, in: .rect(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 20)
                trailing
            }
            .padding(.horizontal, 16)
            .frame(height: 66)
            .background(isFiring || isDropTargeted ? Theme.accentFill : (isHovered && !isBlocked ? Theme.rowHover : .clear))
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture { if !isBlocked { onEdit() } }
            .dropDestination(for: URL.self) { urls, _ in
                guard !isBlocked, let url = urls.first else { return false }
                return onDropFile(url)
            } isTargeted: { isDropTargeted = $0 && !isBlocked }
            .opacity(isBlocked ? 0.45 : 1)

            if showsDivider {
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 62)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder private var trailing: some View {
        if isDropTargeted {
            Label(L10n.text("松开即绑定：放映这份文稿"), systemImage: "play.rectangle.on.rectangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
        } else if isBlocked {
            Text(L10n.text("已由「按住」接管")).font(.system(size: 12)).foregroundStyle(.secondary)
        } else if let bound {
            HStack(spacing: 10) {
                BindingChip(bound: bound, isInherited: isInherited)
                if !isInherited {
                    Button(action: onClear) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(Theme.subtleFill, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0)
                    .help(L10n.text("移除"))
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                Text(L10n.text("添加动作")).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isHovered ? Theme.accent : Color.secondary.opacity(0.8))
        }
    }
}

/// 动作摘要：图标 + 名称 + 键帽或说明
struct BindingChip: View {
    let bound: BoundAction
    var isInherited = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: bound.displaySymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.tint(for: bound))
                .frame(width: 24, height: 24)
                .background(Theme.tint(for: bound).opacity(0.14), in: .rect(cornerRadius: 7, style: .continuous))
            Text(bound.displayTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            if let keycaps = bound.action.keycaps {
                KeycapRow(keys: keycaps)
            } else {
                Text(bound.action.summary)
                    .font(Theme.mono(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 150, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if isInherited { Tag(text: L10n.text("全局")) }
        }
        .opacity(isInherited ? 0.6 : 1)
    }
}

// MARK: - 选项

struct OptionsCard: View {
    @Environment(AppModel.self) private var model
    let button: RemoteButton

    var body: some View {
        let profileID = model.selectedProfileID
        let own = model.mapping(button, in: profileID)
        let mapping = own ?? model.inheritedMapping(button, for: profileID)
        let canRepeat = mapping.map { $0.tap != nil && $0.boundGestures == [.tap] } ?? false
        let isAppProfile = !model.selectedProfile.isGlobal

        SettingsGroup(L10n.text("选项")) {
            SettingRow(title: L10n.text("按住时连续触发"),
                       detail: canRepeat ? L10n.text("按住不放时按键盘重复速率连续触发「单击」，适合方向键。")
                                         : L10n.text("仅在只设置了「单击」时可用。"),
                       symbol: "repeat",
                       showsDivider: button.isSystemMediaKey || (isAppProfile && own != nil)) {
                Toggle(L10n.text("按住时连续触发"), isOn: Binding(
                    get: { mapping?.repeatWhileHeld ?? false },
                    set: { value in
                        guard var updated = mapping else { return }
                        updated.repeatWhileHeld = value
                        model.setMapping(updated, for: button, in: profileID)
                    }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .disabled(!canRepeat)
            }
            if button.isSystemMediaKey {
                SettingRow(title: L10n.text("系统媒体键"),
                           detail: L10n.text("映射后会拦截该键原本的音量 / 播放功能；不设置任何手势则保持系统默认。"),
                           symbol: "speaker.wave.2",
                           showsDivider: isAppProfile && own != nil) {
                    EmptyView()
                }
            }
            if isAppProfile && own != nil {
                SettingRow(title: L10n.text("恢复为全局设置"),
                           detail: L10n.format("移除此按键在「%@」中的专属设置。", String(model.selectedProfile.displayName)),
                           symbol: "arrow.uturn.backward",
                           showsDivider: false) {
                    Button(L10n.text("恢复")) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            model.setMapping(nil, for: button, in: profileID)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 按键 / 触控切换

struct MappingModeSwitch: View {
    @Environment(AppModel.self) private var model
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MappingMode.allCases) { mode in
                let isSelected = model.mappingMode == mode
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { model.mappingMode = mode }
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Theme.accent : .secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.card)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "mode", in: namespace)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.subtleFill, in: .rect(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - 触控手势

/// 选中鼠标模式配置时直接显示开关，不必去「通用」里找
struct PointerModeSwitch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let isOn = model.config.touch.mode == .pointer
        SettingsGroup(L10n.text("鼠标模式")) {
            SettingRow(title: L10n.text("启用鼠标模式"),
                       detail: L10n.text("单指移动光标，右侧上下滑或沿外圈转动即滚动；侧面 Siri 键单击为确定、双击切换为整面滚轮。"),
                       symbol: "cursorarrow.motionlines", showsDivider: false) {
                Toggle(L10n.text("启用鼠标模式"), isOn: Binding(get: { isOn }, set: { model.config.touch.mode = $0 ? .pointer : .gestures }))
                    .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
            }
        }
    }
}

struct TouchHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = model.engine.touch?.status ?? .unavailable(L10n.text("此版本不支持"))
        let surfaceSize = model.engine.touch?.surfaceSize
        HStack(alignment: .center, spacing: 16) {
            KeyGlyph(symbol: "hand.draw", size: 58)
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("触控手势")).font(.system(size: 24, weight: .semibold))
                HStack(spacing: 6) {
                    if let size = surfaceSize {
                        Tag(text: String(format: "%.1f × %.1f mm", size.width, size.height), mono: true)
                    }
                    switch status {
                    case .running: Tag(text: L10n.text("触控面已识别"), tint: Theme.live)
                    case .notFound: Tag(text: L10n.text("未找到触控面"), tint: Theme.warning)
                    case .unavailable(let message): Tag(text: message, tint: Theme.warning)
                    case .idle: Tag(text: L10n.text("等待遥控器连接"))
                    }
                    if !model.config.touch.isEnabled {
                        Tag(text: L10n.text("已在通用设置中关闭"), tint: Theme.warning)
                    } else if model.config.touch.mode == .pointer {
                        Tag(text: L10n.text("鼠标模式中，手势暂不触发"), tint: Theme.warning)
                    }
                }
            }
            Spacer()
        }
    }
}

struct TouchCard: View {
    @Environment(AppModel.self) private var model
    @State private var firing: TouchGesture?

    var body: some View {
        let profileID = model.selectedProfileID
        let isAppProfile = !model.selectedProfile.isGlobal
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("滑动")).eyebrowStyle()
                Spacer()
                Text(L10n.text("快速滑过后抬起；按压触控板时不会触发"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            rows([.swipeUp, .swipeDown, .swipeLeft, .swipeRight], profileID: profileID, isAppProfile: isAppProfile)

            HStack {
                Text(L10n.text("转动")).eyebrowStyle()
                Spacer()
                Text(L10n.format("每转过 %@° 触发一次，可在「通用」中调整", String(Int(model.config.touch.rotationStep))))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 16)
            rows([.rotateClockwise, .rotateCounterclockwise], profileID: profileID, isAppProfile: isAppProfile)
        }
        .onChange(of: model.lastTouch) {
            guard let gesture = model.lastTouch?.gesture else { return }
            withAnimation(.easeOut(duration: 0.1)) { firing = gesture }
            Task {
                try? await Task.sleep(for: .milliseconds(gesture.isRotation ? 250 : 450))
                withAnimation(.easeOut(duration: 0.5)) { if firing == gesture { firing = nil } }
            }
        }
    }

    private func rows(_ gestures: [TouchGesture], profileID: UUID, isAppProfile: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(gestures) { gesture in
                let own = model.ownAction(.touch(gesture), in: profileID)
                let inherited = own == nil ? model.inheritedTouch(gesture, for: profileID) : nil
                BindingRow(title: gesture.displayName, detail: gesture.detail, symbol: gesture.symbol,
                           bound: own ?? inherited,
                           isInherited: inherited != nil,
                           isBlocked: false,
                           isFiring: firing == gesture,
                           showsDivider: gesture != gestures.last) {
                    model.editor = EditorContext(profileID: profileID, target: .touch(gesture))
                } onClear: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        model.setAction(nil, for: .touch(gesture), in: profileID)
                    }
                } onDropFile: { url in
                    model.bindSlides(url, to: .touch(gesture), in: profileID)
                }
            }
        }
        .card()
    }
}
