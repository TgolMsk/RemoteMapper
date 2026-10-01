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
                SettingsGroup("映射") {
                    SettingRow(title: "启用映射", detail: "关闭后遥控器恢复系统默认行为，菜单栏中也可以快速切换。", symbol: "power") {
                        Toggle("启用映射", isOn: $model.config.isEnabled).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                    }
                    SettingRow(title: "接管系统媒体键",
                               detail: "音量、静音、播放键被映射时，拦截它们原本的系统功能。需要辅助功能权限。",
                               symbol: "speaker.wave.2", showsDivider: false) {
                        Toggle("接管系统媒体键", isOn: $model.config.interceptSystemKeys).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                    }
                }

                SettingsGroup("手势判定") {
                    TimingDiagram(longPress: model.config.longPressThreshold, doubleTap: model.config.doubleTapInterval)
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                    TimingSlider(title: "长按时长", detail: "按住超过这个时长判定为「长按」。",
                                 value: $model.config.longPressThreshold, range: 0.25...1.0, tint: Theme.accent)
                    TimingSlider(title: "双击间隔", detail: "两次按下的间隔小于它判定为「双击」。绑定了双击的按键，单击会延迟这么久。",
                                 value: $model.config.doubleTapInterval, range: 0.15...0.5, tint: Theme.live, showsDivider: false)
                }

                VoiceSettingsGroup()

                if Edition.supportsTouch {
                SettingsGroup("触控") {
                    SettingRow(title: "启用触控", detail: "关闭后触控板既不触发手势，也不移动光标。", symbol: "hand.draw") {
                        Toggle("启用触控", isOn: $model.config.touch.isEnabled).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                    }
                    SettingRow(title: "触控板用途",
                               detail: model.config.touch.mode == .pointer
                                   ? "单指移动光标，右侧上下滑或沿外圈转动即滚动；侧面 Siri 键单击为确定、双击切换为整面滚轮。按键可在映射页的「鼠标模式」配置中修改。"
                                   : "滑动或沿外圈转动来触发映射的动作。",
                               symbol: model.config.touch.mode == .pointer ? "cursorarrow.motionlines" : "hand.point.up.left") {
                        Picker("触控板用途", selection: $model.config.touch.mode) {
                            ForEach(TouchMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    if model.config.touch.mode == .pointer {
                        TimingSlider(title: "光标速度", detail: "手指慢时精细定位，快时一次划得更远。滚轮的速度也随之变化。",
                                     value: $model.config.touch.pointerSpeed, range: 0.3...3, tint: Theme.accent,
                                     format: { String(format: "%.1f×", $0) }, step: 0.1)
                        SettingRow(title: "右侧滚动区", detail: "在触控板右侧上下滑动即滚动，内容跟着手指走，松手后带惯性；横着划仍是移动光标。",
                                   symbol: "arrow.up.and.down.square") {
                            Toggle("右侧滚动区", isOn: $model.config.touch.sideScroll).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                        }
                        if model.config.touch.sideScroll {
                            TimingSlider(title: "滚动区宽度", detail: "占触控板宽度的比例，左边其余部分移动光标。",
                                         value: $model.config.touch.sideScrollWidth, range: 0.2...0.45, tint: Theme.live,
                                         format: { String(format: "%.0f%%", $0 * 100) }, step: 0.01)
                        }
                        SettingRow(title: "外圈转动滚动", detail: "沿触控板外圈顺时针转动向下滚动、逆时针向上，从右侧滚动区起手时按滚动区处理。",
                                   symbol: "arrow.clockwise.circle") {
                            Toggle("外圈转动滚动", isOn: $model.config.touch.ringScroll).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                        }
                        if model.config.touch.ringScroll {
                            TimingSlider(title: "外圈宽度", detail: "越窄，中间移动光标的区域越大；从外圈往里划仍是移动光标，只有沿圆周转动才滚动。",
                                         value: $model.config.touch.ringWidth, range: 0.06...0.2, tint: Theme.live,
                                         format: { String(format: "%.1f mm", $0 * 27.8) }, step: 0.01)
                        }
                        SettingRow(title: "轻点点按", detail: "轻点触控板即左键单击。关闭时只有绑定的按键会点击。",
                                   symbol: "hand.tap", showsDivider: false) {
                            Toggle("轻点点按", isOn: $model.config.touch.tapToClick).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                        }
                    } else {
                        TimingSlider(title: "滑动距离", detail: "手指移动超过触控面的这个比例才算滑动。数值越小越灵敏，也越容易误触。",
                                     value: $model.config.touch.swipeDistance, range: 0.15...0.6, tint: Theme.accent,
                                     format: { String(format: "%.0f%%", $0 * 100) })
                        TimingSlider(title: "转动步进", detail: "沿外圈每转过这个角度触发一次。绑定滚动时，数值越小滚得越快。",
                                     value: $model.config.touch.rotationStep, range: 10...90, tint: Theme.live, showsDivider: false,
                                     format: { String(format: "%.0f°", $0) }, step: 5)
                    }
                }
                }

                SettingsGroup("启动") {
                    SettingRow(title: "登录时自动启动", detail: "\(Edition.name) 只常驻在菜单栏，不占用程序坞。",
                               symbol: "sunrise", showsDivider: false) {
                        Toggle("登录时自动启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                    }
                }

                SettingsGroup("配置文件") {
                    SettingRow(title: "config.json", detail: model.store.fileURL.path(percentEncoded: false),
                               symbol: "doc.text") {
                        HStack(spacing: 8) {
                            Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([model.store.fileURL]) }
                            Button("重新载入") { model.store.reload() }
                        }
                    }
                    if let error = model.store.lastError {
                        SettingRow(title: "配置有误", detail: error, symbol: "exclamationmark.triangle") { EmptyView() }
                    }
                    SettingRow(title: "恢复默认配置", detail: "清除所有自定义映射与 App 专属配置。",
                               symbol: "arrow.counterclockwise", showsDivider: false) {
                        Button("恢复默认…") { confirmsReset = true }
                    }
                }

                Text("配置文件在外部修改后会自动载入，可以直接让 Claude 或 Codex 帮你编辑映射。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.never)
        .confirmationDialog("恢复默认配置？", isPresented: $confirmsReset) {
            Button("恢复默认", role: .destructive) { model.store.resetToDefault() }
        } message: {
            Text("所有自定义映射与 App 专属配置都会被清除。")
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
    var format: (Double) -> String = { String(format: "%.2f 秒", $0) }
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

                label("双击窗口 \(format(doubleTap))", color: Theme.live, x: doubleX, width: w, y: 0)
                label("长按 ≥ \(format(longPress))", color: Theme.accent, x: longX, width: w, y: trackY + 14)

                marker(at: doubleX, color: Theme.live)
                marker(at: longX, color: Theme.accent)

                Text("按下").font(.system(size: 10.5)).foregroundStyle(.tertiary).offset(y: trackY + 14)
                Text(format(span)).font(Theme.mono(10.5)).foregroundStyle(.tertiary)
                    .frame(width: w, alignment: .trailing).offset(y: trackY + 14)
            }
        }
        .frame(height: trackY + 30)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: longPress)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: doubleTap)
    }

    private func format(_ seconds: Double) -> String { String(format: "%.2fs", seconds) }

    private func label(_ text: String, color: Color, x: CGFloat, width: CGFloat, y: CGFloat) -> some View {
        let labelWidth: CGFloat = 110
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
struct VoiceSettingsGroup: View {
    @Environment(AppModel.self) private var model
    @State private var devices: [AudioInputDevice] = []
    @State private var defaultDevice: AudioInputDevice?

    private static let languages: [(id: String?, name: String)] = [
        (nil, "跟随系统"), ("zh-CN", "中文（普通话）"), ("zh-TW", "中文（台湾）"), ("zh-HK", "粤语（香港）"),
        ("en-US", "English (US)"), ("ja-JP", "日本語"),
    ]

    var body: some View {
        @Bindable var model = model
        let dictation = model.engine.dictation
        SettingsGroup("语音输入") {
            SettingRow(title: "录音来源", detail: "选择遥控器内置麦克风，或使用连接到 Mac 的麦克风。", symbol: "appletvremote.gen4") {
                Picker("录音来源", selection: $model.config.voice.usesRemoteMicrophone) {
                    Text("遥控器麦克风").tag(true)
                    Text("Mac 音频输入").tag(false)
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
                            Label("系统输入", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.live)
                        } else {
                            Button("设为系统输入") { model.microphoneBridge.useAsSystemInput() }
                        }
                    } else {
                        #if !APP_STORE
                        Button("安装并设为系统输入") { Task { await model.microphoneBridge.install() } }
                        #else
                        Text("需安装官网版音频组件").font(.system(size: 12)).foregroundStyle(.secondary)
                        #endif
                    }
                }
            } else {
                SettingRow(title: "麦克风",
                           detail: devices.isEmpty ? "未检测到麦克风：请连接 AirPods、耳机或 USB 麦克风。" : "按住遥控器说话时使用的录音设备。",
                           symbol: devices.isEmpty ? "mic.slash" : "mic") {
                    Picker("麦克风", selection: $model.config.voice.inputDeviceUID) {
                        Text("系统默认（\(defaultDevice?.name ?? "无")）").tag(String?.none)
                        if !devices.isEmpty { Divider() }
                        ForEach(devices) { device in
                            Text(device.name).tag(String?.some(device.uid))
                        }
                        if let uid = model.config.voice.inputDeviceUID, !devices.contains(where: { $0.uid == uid }) {
                            Text("已断开的麦克风").tag(String?.some(uid))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingRow(title: "识别语言", detail: "完全在本机识别，语音不会上传。", symbol: "character.bubble") {
                Picker("识别语言", selection: $model.config.voice.localeIdentifier) {
                    ForEach(Self.languages, id: \.name) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "语音模型", detail: modelDetail(dictation.modelState), symbol: "square.and.arrow.down") {
                switch dictation.modelState {
                case .installed:
                    Label("已安装", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.live)
                case .downloading(let progress):
                    ProgressView(value: progress).frame(width: 120)
                case .notInstalled, .unknown:
                    Button("下载") { Task { await dictation.installModel() } }
                case .unsupported:
                    Text("不支持").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            SettingRow(title: "显示识别浮窗", detail: "录音时在屏幕底部实时显示识别结果。",
                       symbol: "rectangle.bottomthird.inset.filled", showsDivider: false) {
                Toggle("显示识别浮窗", isOn: $model.config.voice.showsHUD)
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
        if model.microphoneBridge.isInstalled { return "按住 Siri 键说话，其他 App 也可选择此输入；松开后静音。" }
        return "安装需要管理员授权，并会短暂重启系统音频。需已安装 Apple PacketLogger。"
    }

    private func modelDetail(_ state: VoiceDictation.ModelState) -> String {
        switch state {
        case .installed: "当前语言的识别模型已就绪。"
        case .downloading(let progress): "正在下载… \(Int(progress * 100))%"
        case .notInstalled: "首次使用需要下载当前语言的识别模型。"
        case .unsupported: "此 Mac 不支持所选语言的本机识别。"
        case .unknown: "正在检查…"
        }
    }
}
