import AppKit
import RemoteKit
import SwiftUI

struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsReset = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                InterfaceLanguageGroup()

                SettingsGroup(L10n.text("映射")) {
                    SettingRow(title: L10n.text("启用映射"), detail: L10n.text("关闭后遥控器恢复系统默认行为，菜单栏中也可以快速切换。"), symbol: "power") {
                        Toggle(L10n.text("启用映射"), isOn: $model.config.isEnabled).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                    }
                    SettingRow(title: L10n.text("接管系统媒体键"),
                               detail: L10n.text("独占遥控器按键：映射了的键不再触发系统功能（电源键不再弹出关机对话框），未映射的音量、静音、播放键仍按系统默认。关闭后遥控器恢复原生行为。"),
                               symbol: "speaker.wave.2", showsDivider: false) {
                        Toggle(L10n.text("接管系统媒体键"), isOn: $model.config.interceptSystemKeys).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                    }
                }

                SettingsGroup(L10n.text("手势判定")) {
                    TimingDiagram(longPress: model.config.longPressThreshold, doubleTap: model.config.doubleTapInterval)
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                    TimingSlider(title: L10n.text("长按时长"), detail: L10n.text("按住超过这个时长判定为「长按」。"),
                                 value: $model.config.longPressThreshold, range: 0.25...1.0, tint: Theme.accent)
                    TimingSlider(title: L10n.text("双击间隔"), detail: L10n.text("两次按下的间隔小于它判定为「双击」。绑定了双击的按键，单击会延迟这么久。"),
                                 value: $model.config.doubleTapInterval, range: 0.15...0.5, tint: Theme.live, showsDivider: false)
                }

                VoiceSettingsGroup()

                SettingsGroup(L10n.text("触控")) {
                    SettingRow(title: L10n.text("启用触控"), detail: L10n.text("关闭后触控板既不触发手势，也不移动光标。"), symbol: "hand.draw") {
                        Toggle(L10n.text("启用触控"), isOn: $model.config.touch.isEnabled).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                    }
                    SettingRow(title: L10n.text("触控板用途"),
                               detail: model.config.touch.mode == .pointer
                                   ? L10n.text("单指移动光标，右侧上下滑或沿外圈转动即滚动；侧面 Siri 键单击为确定、双击切换为整面滚轮。按键可在映射页的「鼠标模式」配置中修改。")
                                   : L10n.text("滑动或沿外圈转动来触发映射的动作。"),
                               symbol: model.config.touch.mode == .pointer ? "cursorarrow.motionlines" : "hand.point.up.left") {
                        Picker(L10n.text("触控板用途"), selection: $model.config.touch.mode) {
                            ForEach(TouchMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    if model.config.touch.mode == .pointer {
                        TimingSlider(title: L10n.text("光标速度"), detail: L10n.text("手指慢时精细定位，快时一次划得更远。滚轮的速度也随之变化。"),
                                     value: $model.config.touch.pointerSpeed, range: 0.3...3, tint: Theme.accent,
                                     format: { L10n.format("%.1f×", $0) }, step: 0.1)
                        SettingRow(title: L10n.text("右侧滚动区"), detail: L10n.text("在触控板右侧上下滑动即滚动，内容跟着手指走，松手后带惯性；横着划仍是移动光标。"),
                                   symbol: "arrow.up.and.down.square") {
                            Toggle(L10n.text("右侧滚动区"), isOn: $model.config.touch.sideScroll).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                        }
                        if model.config.touch.sideScroll {
                            TimingSlider(title: L10n.text("滚动区宽度"), detail: L10n.text("占触控板宽度的比例，左边其余部分移动光标。"),
                                         value: $model.config.touch.sideScrollWidth, range: 0.2...0.45, tint: Theme.live,
                                         format: { L10n.format("%.0f%%", $0 * 100) }, step: 0.01)
                        }
                        SettingRow(title: L10n.text("外圈转动滚动"), detail: L10n.text("沿触控板外圈顺时针转动向下滚动、逆时针向上，从右侧滚动区起手时按滚动区处理。"),
                                   symbol: "arrow.clockwise.circle") {
                            Toggle(L10n.text("外圈转动滚动"), isOn: $model.config.touch.ringScroll).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                        }
                        if model.config.touch.ringScroll {
                            TimingSlider(title: L10n.text("外圈宽度"), detail: L10n.text("越窄，中间移动光标的区域越大；从外圈往里划仍是移动光标，只有沿圆周转动才滚动。"),
                                         value: $model.config.touch.ringWidth, range: 0.06...0.2, tint: Theme.live,
                                         format: { L10n.format("%.1f mm", $0 * 27.8) }, step: 0.01)
                        }
                        SettingRow(title: L10n.text("轻点点按"), detail: L10n.text("轻点触控板即左键单击。关闭时只有绑定的按键会点击。"),
                                   symbol: "hand.tap", showsDivider: false) {
                            Toggle(L10n.text("轻点点按"), isOn: $model.config.touch.tapToClick).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                        }
                    } else {
                        TimingSlider(title: L10n.text("滑动距离"), detail: L10n.text("手指移动超过触控面的这个比例才算滑动。数值越小越灵敏，也越容易误触。"),
                                     value: $model.config.touch.swipeDistance, range: 0.15...0.6, tint: Theme.accent,
                                     format: { L10n.format("%.0f%%", $0 * 100) })
                        TimingSlider(title: L10n.text("转动步进"), detail: L10n.text("沿外圈每转过这个角度触发一次。绑定滚动时，数值越小滚得越快。"),
                                     value: $model.config.touch.rotationStep, range: 10...90, tint: Theme.live, showsDivider: false,
                                     format: { L10n.format("%.0f°", $0) }, step: 5)
                    }
                }

                UnlockSettingsGroup()

                SettingsGroup(L10n.text("启动")) {
                    SettingRow(title: L10n.text("登录时自动启动"), detail: L10n.text("RemoteMapper 只常驻在菜单栏，不占用程序坞。"),
                               symbol: "sunrise", showsDivider: false) {
                        Toggle(L10n.text("登录时自动启动"), isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                    }
                }

                SettingsGroup(L10n.text("配置文件")) {
                    SettingRow(title: "config.json", detail: model.store.fileURL.path(percentEncoded: false),
                               symbol: "doc.text") {
                        HStack(spacing: 8) {
                            Button(L10n.text("在访达中显示")) { NSWorkspace.shared.activateFileViewerSelecting([model.store.fileURL]) }
                            Button(L10n.text("重新载入")) { model.store.reload() }
                        }
                    }
                    if let error = model.store.lastError {
                        SettingRow(title: L10n.text("配置有误"), detail: error, symbol: "exclamationmark.triangle") { EmptyView() }
                    }
                    SettingRow(title: L10n.text("恢复默认配置"), detail: L10n.text("清除所有自定义映射与 App 专属配置。"),
                               symbol: "arrow.counterclockwise", showsDivider: false) {
                        Button(L10n.text("恢复默认…")) { confirmsReset = true }
                    }
                }

                Text(L10n.text("配置文件在外部修改后会自动载入，可以直接让 Claude 或 Codex 帮你编辑映射。"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.never)
        .confirmationDialog(L10n.text("恢复默认配置？"), isPresented: $confirmsReset) {
            Button(L10n.text("恢复默认"), role: .destructive) { model.store.resetToDefault() }
        } message: {
            Text(L10n.text("所有自定义映射与 App 专属配置都会被清除。"))
        }
    }
}

/// 界面语言切换立即生效；独立于识别语言和配置文件。
struct InterfaceLanguageGroup: View {
    var body: some View {
        @Bindable var languages = LanguageSettings.shared
        SettingsGroup(L10n.text("语言")) {
            SettingRow(title: L10n.text("界面语言"), detail: L10n.text("立即生效；不影响语音识别语言和自定义映射。"),
                       symbol: "globe", showsDivider: false) {
                Picker(L10n.text("界面语言"), selection: $languages.selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 190)
            }
        }
    }
}

struct TimingSlider: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tint: Color
    var showsDivider = true
    var format: (Double) -> String = { L10n.format("%.2f 秒", $0) }
    /// 拖动时的取值精度
    var step = 0.01

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text(title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(format(value))
                        .font(Theme.mono(12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: value))
                }
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                    .tint(tint)
                    .controlSize(.small)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            if showsDivider { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 18) }
        }
    }
}

/// 一次按压的时间轴：双击窗口（上方标注）与长按起点（下方标注）
struct TimingDiagram: View {
    let longPress: Double
    let doubleTap: Double

    private let span = 1.2
    private let trackY: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let longX = w * longPress / span
            let doubleX = w * doubleTap / span
            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.subtleFill).frame(width: w, height: 6).offset(y: trackY - 3)
                Capsule().fill(Theme.live.opacity(0.65)).frame(width: max(doubleX, 6), height: 6).offset(y: trackY - 3)
                Capsule().fill(Theme.accent.opacity(0.85)).frame(width: max(w - longX, 6), height: 6).offset(x: longX, y: trackY - 3)

                label(L10n.format("双击窗口 %@", format(doubleTap)), color: Theme.live, x: doubleX, width: w, y: 0)
                label(L10n.format("长按 ≥ %@", format(longPress)), color: Theme.accent, x: longX, width: w, y: trackY + 14)

                marker(at: doubleX, color: Theme.live)
                marker(at: longX, color: Theme.accent)

                Text(L10n.text("按下")).font(.system(size: 10.5)).foregroundStyle(.tertiary).offset(y: trackY + 14)
                Text(format(span)).font(Theme.mono(10.5)).foregroundStyle(.tertiary)
                    .frame(width: w, alignment: .trailing).offset(y: trackY + 14)
            }
        }
        .frame(height: trackY + 30)
        .environment(\.layoutDirection, .leftToRight)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: longPress)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: doubleTap)
    }

    private func format(_ seconds: Double) -> String { L10n.format("%.2fs", seconds) }

    private func label(_ text: String, color: Color, x: CGFloat, width: CGFloat, y: CGFloat) -> some View {
        let labelWidth: CGFloat = 170
        let left = min(max(x - labelWidth / 2, 34), width - labelWidth - 34)
        return Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: labelWidth)
            .offset(x: left, y: y)
    }

    private func marker(at x: CGFloat, color: Color) -> some View {
        Circle()
            .fill(Theme.card)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(color, lineWidth: 3))
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .offset(x: x - 7, y: trackY - 7)
    }
}

/// 语音输入设置：麦克风、识别语言、语音模型、浮窗
/// 「解锁屏幕」用的登录密码：保存到钥匙串，界面上只显示是否已设置
struct UnlockSettingsGroup: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        SettingsGroup(L10n.text("锁屏解锁")) {
            SettingRow(title: model.hasUnlockPassword ? L10n.text("登录密码已保存") : L10n.text("登录密码"),
                       detail: error ?? (model.hasUnlockPassword
                           ? L10n.text("保存在钥匙串中。锁屏时按下绑定了「解锁屏幕」的键即可解锁；拿到遥控器的人也能解锁这台 Mac。")
                           : L10n.text("保存到钥匙串后，在按键映射中给某个键绑定「解锁屏幕」预设。未锁屏时按下不会输入任何内容。")),
                       symbol: model.hasUnlockPassword ? "lock.open.fill" : "lock", showsDivider: false) {
                HStack(spacing: 8) {
                    SecureField(model.hasUnlockPassword ? L10n.text("新密码") : L10n.text("Mac 登录密码"), text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(save)
                    Button(model.hasUnlockPassword ? L10n.text("更新") : L10n.text("保存"), action: save)
                        .disabled(draft.isEmpty)
                    if model.hasUnlockPassword {
                        Button(L10n.text("清除"), role: .destructive) {
                            error = model.setUnlockPassword(nil)
                        }
                    }
                }
            }
        }
    }

    private func save() {
        guard !draft.isEmpty else { return }
        error = model.setUnlockPassword(draft)
        draft = ""
    }
}

struct VoiceSettingsGroup: View {
    @Environment(AppModel.self) private var model
    @State private var devices: [AudioInputDevice] = []
    @State private var defaultDevice: AudioInputDevice?

    private static var languages: [(id: String?, name: String)] { [
        (nil, L10n.text("跟随系统")), ("zh-CN", L10n.text("中文（普通话）")), ("zh-TW", L10n.text("中文（台湾）")), ("zh-HK", L10n.text("粤语（香港）")),
        ("en-US", "English (US)"), ("ja-JP", L10n.text("日本語")),
    ] }

    var body: some View {
        @Bindable var model = model
        let dictation = model.engine.dictation
        SettingsGroup(L10n.text("语音输入")) {
            SettingRow(title: L10n.text("录音来源"), detail: L10n.text("选择遥控器内置麦克风，或使用连接到 Mac 的麦克风。"), symbol: "appletvremote.gen4") {
                Picker(L10n.text("录音来源"), selection: $model.config.voice.usesRemoteMicrophone) {
                    Text(L10n.text("遥控器麦克风")).tag(true)
                    Text(L10n.text("Mac 音频输入")).tag(false)
                }.labelsHidden().fixedSize()
            }
            if model.config.voice.usesRemoteMicrophone {
                SettingRow(title: "Siri Remote Mic",
                           detail: remoteDetail,
                           symbol: model.microphoneBridge.isInstalled ? "mic.fill" : "mic.slash") {
                    if model.microphoneBridge.isBusy {
                        ProgressView().controlSize(.small)
                    } else if model.microphoneBridge.isInstalled {
                        if defaultDevice?.uid == AudioInputDevices.remoteMicrophoneUID {
                            Label(L10n.text("系统输入"), systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.live)
                        } else {
                            Button(L10n.text("设为系统输入")) { model.microphoneBridge.useAsSystemInput() }
                        }
                    } else {
                        Button(L10n.text("安装并设为系统输入")) { Task { await model.microphoneBridge.install() } }
                    }
                }
            } else {
                SettingRow(title: L10n.text("麦克风"),
                           detail: devices.isEmpty ? L10n.text("未检测到麦克风：请连接 AirPods、耳机或 USB 麦克风。") : L10n.text("按住遥控器说话时使用的录音设备。"),
                           symbol: devices.isEmpty ? "mic.slash" : "mic") {
                    Picker(L10n.text("麦克风"), selection: $model.config.voice.inputDeviceUID) {
                        Text(L10n.format("系统默认（%@）", defaultDevice?.name ?? L10n.text("无"))).tag(String?.none)
                        if !devices.isEmpty { Divider() }
                        ForEach(devices) { device in
                            Text(device.name).tag(String?.some(device.uid))
                        }
                        if let uid = model.config.voice.inputDeviceUID, !devices.contains(where: { $0.uid == uid }) {
                            Text(L10n.text("已断开的麦克风")).tag(String?.some(uid))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingRow(title: L10n.text("识别语言"), detail: L10n.text("完全在本机识别，语音不会上传。"), symbol: "character.bubble") {
                Picker(L10n.text("识别语言"), selection: $model.config.voice.localeIdentifier) {
                    ForEach(Self.languages, id: \.name) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: L10n.text("语音模型"), detail: modelDetail(dictation.modelState), symbol: "square.and.arrow.down") {
                switch dictation.modelState {
                case .installed:
                    Label(L10n.text("已安装"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.live)
                case .downloading(let progress):
                    ProgressView(value: progress).frame(width: 120)
                case .notInstalled, .unknown:
                    Button(L10n.text("下载")) { Task { await dictation.installModel() } }
                case .unsupported:
                    Text(L10n.text("不支持")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            SettingRow(title: L10n.text("显示识别浮窗"), detail: L10n.text("录音时在屏幕底部实时显示识别结果。"),
                       symbol: "rectangle.bottomthird.inset.filled", showsDivider: false) {
                Toggle(L10n.text("显示识别浮窗"), isOn: $model.config.voice.showsHUD)
                    .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
            }
        }
        .task {
            // 麦克风可能随时插拔（AirPods 连接、USB 麦克风插入），定时刷新
            while !Task.isCancelled {
                devices = AudioInputDevices.all()
                defaultDevice = AudioInputDevices.defaultDevice
                model.microphoneBridge.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task { await dictation.refreshModelState() }
    }

    private var remoteDetail: String {
        if let message = model.microphoneBridge.message { return message }
        if model.microphoneBridge.isInstalled { return L10n.text("按住 Siri 键说话，其他 App 也可选择此输入；松开后静音。") }
        return L10n.text("安装需要管理员授权，并会短暂重启系统音频。需已安装 Apple PacketLogger。")
    }

    private func modelDetail(_ state: VoiceDictation.ModelState) -> String {
        switch state {
        case .installed: L10n.text("当前语言的识别模型已就绪。")
        case .downloading(let progress): L10n.format("正在下载… %d%%", Int(progress * 100))
        case .notInstalled: L10n.text("首次使用需要下载当前语言的识别模型。")
        case .unsupported: L10n.text("此 Mac 不支持所选语言的本机识别。")
        case .unknown: L10n.text("正在检查…")
        }
    }
}
