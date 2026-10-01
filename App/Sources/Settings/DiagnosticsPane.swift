import AppKit
import RemoteKit
import SwiftUI

struct DiagnosticsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SettingsGroup("权限") {
                    PermissionRow(title: "辅助功能",
                                  detail: "模拟按键、按住说话、拦截系统媒体键都依赖此权限。",
                                  symbol: "accessibility",
                                  granted: model.hasAccessibility,
                                  action: model.requestAccessibility)
                    SettingRow(title: "自动化（Apple 事件）",
                               detail: "仅在执行 AppleScript 控制其它 App 时，由系统按需询问。",
                               symbol: "applescript", showsDivider: false) {
                        Text("按需授权").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }

                SettingsGroup("遥控器") {
                    let device = model.engine.device
                    InfoRow(label: "状态", value: statusText(device.status), valueColor: device.isConnected ? Theme.live : nil)
                    InfoRow(label: "设备", value: device.productName ?? "—")
                    InfoRow(label: "厂商 / 产品", value: "0x004C / 0x0315", mono: true)
                    InfoRow(label: "最近一帧报告",
                            value: device.lastReport.isEmpty ? "—" : RemoteReport.hex(device.lastReport),
                            mono: true, showsDivider: false)
                }

                SettingsGroup("按键位图", trailing: AnyView(
                    Text("报告 0xFB · 13 位").font(Theme.mono(10.5)).foregroundStyle(.tertiary)
                )) {
                    BitmapGrid(pressed: model.engine.device.pressed)
                        .padding(18)
                }

                SettingsGroup("系统媒体键拦截") {
                    SettingRow(title: model.engine.interceptorRunning ? "运行中" : "未运行",
                               detail: model.engine.interceptorRunning
                                   ? "被映射的音量、静音、播放键不会再触发系统默认功能。"
                                   : "获得辅助功能权限后自动启动。",
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

    private func statusText(_ status: RemoteDevice.Status) -> String {
        switch status {
        case .idle: "未启动"
        case .searching: "等待连接"
        case .connected: "已连接"
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
                Label("已授权", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.live)
            } else {
                Button("前往授权", action: action)
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
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(mono ? Theme.mono(12) : .system(size: 13, weight: .medium))
                    .foregroundStyle(valueColor ?? .primary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
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
            Text("按下遥控器按键，对应的位应当亮起。若名称与实际按键不符，说明位序需要校正。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }
}
