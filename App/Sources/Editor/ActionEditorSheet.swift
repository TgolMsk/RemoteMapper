import AppKit
import RemoteKit
import SwiftUI

/// 编辑器左侧的分类
enum EditorKind: String, CaseIterable, Identifiable {
    case preset, keystroke, holdKey, text, launchApp, openURL, shell, appleScript, sequence

    var id: String { rawValue }

    static let custom: [EditorKind] = [.keystroke, .holdKey, .text, .launchApp, .openURL, .shell, .appleScript]

    var title: String {
        switch self {
        case .preset: "开发工具预设"
        case .sequence: "组合动作"
        default: actionKind.displayName
        }
    }

    var symbol: String {
        switch self {
        case .preset: "sparkles"
        default: actionKind.symbol
        }
    }

    var actionKind: Action.Kind {
        switch self {
        case .preset, .sequence: .sequence
        case .keystroke: .keystroke
        case .holdKey: .holdKey
        case .text: .text
        case .launchApp: .launchApp
        case .openURL: .openURL
        case .shell: .shell
        case .appleScript: .appleScript
        }
    }
}

struct ActionEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let context: EditorContext

    @State private var kind: EditorKind = .preset
    @State private var presetID: String?
    @State private var combo: KeyCombo?
    @State private var text = ""
    @State private var submit = true
    @State private var url = ""
    @State private var bundleID = ""
    @State private var command = ""
    @State private var script = ""
    @State private var sequence: [Action] = []
    @State private var title = ""
    @State private var existing: BoundAction?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Theme.hairline).frame(width: 1)
                ScrollView {
                    detail
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer
        }
        .frame(width: 760, height: 600)
        .background(Theme.paneBackground)
        .onAppear(perform: load)
    }

    // MARK: 布局

    private var header: some View {
        HStack(spacing: 14) {
            KeyGlyph(button: context.button, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(context.button.displayName) · \(context.gesture.displayName)")
                    .font(.system(size: 16, weight: .semibold))
                Text(context.gesture.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let profile = model.config[context.profileID] {
                Tag(text: profile.isGlobal ? "全局" : "\(profile.name) 专属", tint: profile.isGlobal ? nil : Theme.accent)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            sidebarItem(.preset)
            Text("自定义")
                .eyebrowStyle()
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, 6)
            ForEach(EditorKind.custom) { sidebarItem($0) }
            if !sequence.isEmpty && presetID == nil { sidebarItem(.sequence) }
            Spacer()
        }
        .padding(12)
        .frame(width: 196)
        .background(Theme.subtleFill.opacity(0.5))
    }

    private func sidebarItem(_ item: EditorKind) -> some View {
        let isSelected = kind == item
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { kind = item }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                Text(item.title).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .foregroundStyle(isSelected ? Theme.accent : .primary)
            .background(isSelected ? Theme.accentFill : .clear, in: .rect(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var detail: some View {
        switch kind {
        case .preset: presetGrid
        case .keystroke:
            DetailIntro(title: "快捷键", text: "按一次组合键。点击下方区域后，直接在键盘上按下想要发送的按键。")
            KeyRecorder(combo: $combo)
        case .holdKey:
            DetailIntro(title: "按住按键", text: "绑定到「按住」时，遥控器按住期间保持按下，并按系统键盘重复速率发送重复事件；终端里的「按住空格说话」依赖这一点。绑定到其它手势时等同于按一次。")
            KeyRecorder(combo: $combo)
            if context.gesture != .hold { GestureHint(text: "此动作最适合绑定到「按住」手势。") }
        case .text:
            DetailIntro(title: "输入文本", text: "以 Unicode 方式直接输入，不受当前输入法影响。可用于发送常用指令，例如「继续」。")
            CodeField(text: $text, placeholder: "要输入的文字", monospaced: false)
            Toggle("输入后按 ↩ 发送", isOn: $submit).toggleStyle(.checkbox).padding(.top, 4)
        case .launchApp:
            DetailIntro(title: "打开 App", text: "启动 App，或在已运行时切换到它的窗口。")
            AppPicker(bundleID: $bundleID)
        case .openURL:
            DetailIntro(title: "打开链接", text: "支持网页链接与 App 的 URL Scheme。")
            TextField("例如 claude://claude.ai/new", text: $url)
                .textFieldStyle(.plain)
                .font(Theme.mono(13))
                .padding(12)
                .background(Theme.card, in: .rect(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 0.5))
            HStack(spacing: 6) {
                ForEach(["claude://claude.ai/new", "codex://", "https://claude.ai"], id: \.self) { suggestion in
                    Button(suggestion) { url = suggestion }
                        .buttonStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.subtleFill, in: .capsule)
                }
            }
            .padding(.top, 8)
        case .shell:
            DetailIntro(title: "Shell 命令", text: "在登录 shell（zsh -lc）中后台执行，PATH 与终端一致。非零退出码会显示在实时事件里。")
            CodeField(text: $command, placeholder: "例如 open -a iTerm ~/Project", monospaced: true)
        case .appleScript:
            DetailIntro(title: "AppleScript", text: "通过 osascript 执行。首次控制其它 App 时，系统会请求「自动化」授权。")
            CodeField(text: $script, placeholder: "tell application \"iTerm\" to activate", monospaced: true)
        case .sequence:
            DetailIntro(title: "组合动作", text: "依次执行多个步骤。组合动作目前需在配置文件中编辑。")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(sequence.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(Theme.mono(11)).foregroundStyle(.tertiary).frame(width: 16)
                        Image(systemName: step.kind.symbol).foregroundStyle(.secondary).frame(width: 18)
                        Text(step.kind.displayName).font(.system(size: 12.5, weight: .medium))
                        Text(step.summary).font(Theme.mono(11.5)).foregroundStyle(.secondary)
                    }
                }
            }
            .card(padding: 16)
        }
    }

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Preset.Group.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.displayName).eyebrowStyle()
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Preset.all.filter { $0.group == group }) { preset in
                            PresetCard(preset: preset, isSelected: presetID == preset.id, gesture: context.gesture)
                                .onTapGesture(count: 2) {
                                    presetID = preset.id
                                    save()
                                }
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { presetID = preset.id }
                                }
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            TextField(kind == .preset ? "显示名称（默认使用预设名称）" : "显示名称（可选）", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            Spacer()
            if existing != nil {
                Button("移除动作", role: .destructive) {
                    model.setAction(nil, for: context.gesture, button: context.button, in: context.profileID)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
                .padding(.trailing, 8)
            }
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("保存", action: save)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(draft == nil)
        }
        .controlSize(.large)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: 数据

    /// 由当前表单组成的动作；信息不完整时为 nil
    private var draft: BoundAction? {
        let customTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        func bound(_ action: Action) -> BoundAction {
            BoundAction(action, title: customTitle.isEmpty ? nil : customTitle,
                        symbol: existing?.presetID == nil ? existing?.symbol : nil)
        }
        switch kind {
        case .preset:
            guard let preset = presetID.flatMap(Preset.find) else { return nil }
            var result = preset.bound
            if !customTitle.isEmpty { result.title = customTitle }
            return result
        case .keystroke: return combo.map { bound(.keystroke($0)) }
        case .holdKey: return combo.map { bound(.holdKey($0)) }
        case .text: return text.isEmpty ? nil : bound(.text(text, submit: submit))
        case .launchApp: return bundleID.isEmpty ? nil : bound(.launchApp(bundleID: bundleID))
        case .openURL:
            let trimmed = url.trimmingCharacters(in: .whitespaces)
            return URL(string: trimmed)?.scheme == nil ? nil : bound(.openURL(trimmed))
        case .shell: return command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : bound(.shell(command))
        case .appleScript: return script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : bound(.appleScript(script))
        case .sequence: return sequence.isEmpty ? nil : bound(.sequence(sequence))
        }
    }

    private func save() {
        guard let draft else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            model.setAction(draft, for: context.gesture, button: context.button, in: context.profileID)
        }
        dismiss()
    }

    private func load() {
        let own = model.mapping(context.button, in: context.profileID)
        let current = (own ?? model.inheritedMapping(context.button, for: context.profileID))?[context.gesture]
        existing = own?[context.gesture]
        guard let current else {
            kind = .preset
            return
        }
        if let id = current.presetID, let preset = Preset.find(id), preset.action == current.action {
            kind = .preset
            presetID = id
            title = current.title == preset.title ? "" : (current.title ?? "")
            return
        }
        title = current.title ?? ""
        switch current.action {
        case .keystroke(let value): kind = .keystroke; combo = value
        case .holdKey(let value): kind = .holdKey; combo = value
        case .text(let value, let shouldSubmit): kind = .text; text = value; submit = shouldSubmit
        case .launchApp(let value): kind = .launchApp; bundleID = value
        case .openURL(let value): kind = .openURL; url = value
        case .shell(let value): kind = .shell; command = value
        case .appleScript(let value): kind = .appleScript; script = value
        case .sequence(let steps): kind = .sequence; sequence = steps
        case .delay: kind = .preset
        }
    }
}

// MARK: - 子组件

struct DetailIntro: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 16)
    }
}

struct GestureHint: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "lightbulb")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.top, 12)
    }
}

struct CodeField: View {
    @Binding var text: String
    let placeholder: String
    let monospaced: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(monospaced ? Theme.mono(12.5) : .system(size: 13.5))
                .scrollContentBackground(.hidden)
                .padding(10)
            if text.isEmpty {
                Text(placeholder)
                    .font(monospaced ? Theme.mono(12.5) : .system(size: 13.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 150)
        .background(Theme.card, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 0.5))
    }
}

struct PresetCard: View {
    let preset: Preset
    let isSelected: Bool
    let gesture: RemoteGesture

    @State private var isHovered = false

    private var tint: Color { Theme.tint(for: preset.group) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: preset.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.72)], startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(preset.title).font(.system(size: 13, weight: .semibold))
                    if let preferred = preset.preferredGesture, preferred != gesture {
                        Text("建议\(preferred.displayName)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Theme.warning)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Theme.warning.opacity(0.14), in: .capsule)
                    }
                }
                Text(preset.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.card, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : (isHovered ? Theme.accent.opacity(0.3) : Theme.cardBorder),
                              lineWidth: isSelected ? 1.6 : 0.5)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white, Theme.accent)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// 选择 App：推荐的开发工具 + 正在运行的 App + 从「应用程序」选择
struct AppPicker: View {
    @Binding var bundleID: String

    private var suggestions: [String] {
        [KnownApp.claudeDesktop, KnownApp.codex, KnownApp.iTerm, KnownApp.terminal, "com.apple.dt.Xcode"]
            .filter { AppInfo.url(for: $0) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if !bundleID.isEmpty, let icon = AppInfo.icon(for: bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 44, height: 44)
                } else {
                    Image(systemName: "app.dashed").font(.system(size: 30)).foregroundStyle(.tertiary).frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(bundleID.isEmpty ? "尚未选择" : AppInfo.name(for: bundleID))
                        .font(.system(size: 14, weight: .semibold))
                    Text(bundleID.isEmpty ? "从下方选择，或浏览「应用程序」文件夹" : bundleID)
                        .font(Theme.mono(11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("浏览…", action: choose)
            }
            .card(padding: 14)

            Text("常用").eyebrowStyle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(suggestions, id: \.self) { id in
                    let isSelected = id == bundleID
                    Button { bundleID = id } label: {
                        VStack(spacing: 6) {
                            if let icon = AppInfo.icon(for: id) {
                                Image(nsImage: icon).resizable().frame(width: 36, height: 36)
                            }
                            Text(AppInfo.name(for: id)).font(.system(size: 11)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? Theme.accentFill : Theme.card, in: .rect(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accent : Theme.cardBorder, lineWidth: isSelected ? 1.5 : 0.5))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        bundleID = id
    }
}
