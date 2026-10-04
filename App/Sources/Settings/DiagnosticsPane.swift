import AVFoundation
import AppKit
import RemoteKit
import SwiftUI

struct DiagnosticsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SettingsGroup(L10n.text("权限")) {
                    PermissionRow(title: L10n.text("辅助功能"),
                                  detail: L10n.text("模拟按键、按住说话、拦截系统媒体键都依赖此权限。"),
                                  symbol: "accessibility",
                                  granted: model.hasAccessibility,
                                  action: model.requestAccessibility)
                    MicrophonePermissionRow()
                    SettingRow(title: L10n.text("自动化（Apple 事件）"),
                               detail: L10n.text("仅在执行 AppleScript 控制其它 App 时，由系统按需询问。"),
                               symbol: "applescript", showsDivider: false) {
                        Text(L10n.text("按需授权")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }

                SettingsGroup(L10n.text("遥控器")) {
                    let device = model.engine.device
                    InfoRow(label: L10n.text("状态"), value: statusText(device.status), valueColor: device.isConnected ? Theme.live : nil)
                    InfoRow(label: L10n.text("设备"), value: device.productName ?? "—")
                    InfoRow(label: L10n.text("厂商 / 产品"), value: "0x004C / 0x0315", mono: true)
                    BatteryRow()
                    InfoRow(label: L10n.text("最近一帧报告"),
                            value: device.lastReport.isEmpty ? "—" : RemoteReport.hex(device.lastReport),
                            mono: true, showsDivider: false)
                }

                if let touch = model.engine.touch {
                SettingsGroup(L10n.text("触控面"), trailing: AnyView(
                    Text(L10n.text("系统触控驱动")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                )) {
                    InfoRow(label: L10n.text("状态"), value: touchStatus(touch.status), valueColor: touch.isRunning ? Theme.live : nil)
                    InfoRow(label: L10n.text("尺寸"), value: touch.surfaceSize.map { String(format: "%.2f × %.2f mm", $0.width, $0.height) } ?? "—",
                            mono: true)
                    InfoRow(label: L10n.text("当前触点"), value: contactText(touch.contacts), mono: true)
                    InfoRow(label: L10n.text("最近识别"), value: model.lastTouch?.gesture.displayName ?? "—", showsDivider: false)
                }
                }

                SettingsGroup(L10n.text("按键位图"), trailing: AnyView(
                    Text(L10n.text("报告 0xFB · 13 位")).font(Theme.mono(10.5)).foregroundStyle(.tertiary)
                )) {
                    BitmapGrid(pressed: model.engine.device.pressed)
                        .padding(18)
                }

                SettingsGroup(L10n.text("系统媒体键拦截")) {
                    SettingRow(title: model.engine.interceptorRunning ? L10n.text("运行中") : L10n.text("未运行"),
                               detail: model.engine.interceptorRunning
                                   ? L10n.text("被映射的音量、静音、播放键不会再触发系统默认功能。")
                                   : L10n.text("获得辅助功能权限后自动启动。"),
                               symbol: "shield.lefthalf.filled", showsDivider: false) {
                        Circle().fill(model.engine.interceptorRunning ? Theme.live : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.never)
    }

    private func touchStatus(_ status: TouchSourceStatus) -> String {
        switch status {
        case .idle: L10n.text("等待遥控器连接")
        case .notFound: L10n.text("未找到触控面")
        case .running: L10n.text("运行中")
        case .unavailable(let message): message
        }
    }

    /// y 轴向上：手指移向遥控器顶端时 y 增大，可据此核对方向
    private func contactText(_ contacts: [TouchContact]) -> String {
        guard !contacts.isEmpty else { return "—" }
        return contacts.map { String(format: "x %.2f  y %.2f", $0.x, $0.y) }.joined(separator: "   ")
    }

    private func statusText(_ status: RemoteDevice.Status) -> String {
        switch status {
        case .idle: L10n.text("未启动")
        case .searching: L10n.text("等待连接")
        case .connected: L10n.text("已连接")
        case .failed(let message): message
        }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        SettingRow(title: title, detail: detail, symbol: symbol) {
            if granted {
                Label(L10n.text("已授权"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.live)
            } else {
                Button(L10n.text("前往授权"), action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.warning)
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color?
    var mono = false
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(value)
                    .font(mono ? Theme.mono(12) : .system(size: 13, weight: .medium))
                    .foregroundStyle(valueColor ?? .primary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            if showsDivider { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 18) }
        }
    }
}

/// 13 个按钮位的实时状态，用于核对位序与按键是否对应
struct BitmapGrid: View {
    let pressed: Set<RemoteButton>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 13), spacing: 6) {
                ForEach(RemoteButton.allCases) { button in
                    let isOn = pressed.contains(button)
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.subtleFill))
                            .frame(height: 30)
                            .overlay(Text("\(button.bit)").font(Theme.mono(11, weight: .semibold))
                                .foregroundStyle(isOn ? .white : .secondary))
                            .shadow(color: isOn ? Theme.accent.opacity(0.5) : .clear, radius: 6)
                        Text(button.shortName)
                            .font(.system(size: 10))
                            .foregroundStyle(isOn ? Theme.accent : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .animation(.easeOut(duration: 0.1), value: isOn)
                }
            }
            Text(L10n.text("按下遥控器按键，对应的位应当亮起。若名称与实际按键不符，说明位序需要校正。"))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }
}

/// 电量：读取状态、数值与更新时间；没有蓝牙权限时提供授权入口
struct BatteryRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let battery = model.engine.battery
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(L10n.text("电量")).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                if let level = battery.level, battery.status == .available || battery.status == .idle {
                    if let date = battery.lastUpdate {
                        Text(date, format: .relative(presentation: .named))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                    }
                    BatteryBadge(level: level)
                } else if battery.status == .unauthorized {
                    Text(L10n.text("没有蓝牙权限")).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.warning)
                    Button(L10n.text("前往授权")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!)
                    }
                } else {
                    Text(statusText(battery.status))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(battery.status == .reading ? .secondary : Theme.warning)
                    if battery.status != .reading && battery.status != .bluetoothOff {
                        Button(L10n.text("重试")) { battery.refresh() }
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            if battery.status == .searching, !battery.candidates.isEmpty {
                Text(L10n.format("已连接且提供电池服务的设备：%@", battery.candidates.joined(separator: ", ")))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 18)
        }
    }

    private func statusText(_ status: BatteryMonitor.Status) -> String {
        switch status {
        case .idle: "—"
        case .unauthorized: L10n.text("没有蓝牙权限")
        case .bluetoothOff: L10n.text("蓝牙已关闭")
        case .searching: L10n.text("未在已连接的蓝牙设备中找到遥控器")
        case .notSupported: L10n.text("遥控器未提供电池服务")
        case .reading: L10n.text("读取中…")
        case .available: "—"
        case .failed(let message): message
        }
    }
}

struct MicrophonePermissionRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingRow(title: L10n.text("麦克风"), detail: L10n.text("语音输入时录音，识别在本机完成。"), symbol: "mic") {
            switch model.microphoneAccess {
            case .authorized:
                Label(L10n.text("已授权"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.live)
            case .notDetermined:
                Text(L10n.text("首次使用时询问")).font(.system(size: 12)).foregroundStyle(.secondary)
            default:
                Button(L10n.text("前往授权")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.warning)
            }
        }
    }
}
