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

                SettingsGroup("触控") {
                    SettingRow(title: "启用触控手势", detail: "在遥控器触控板上滑动或沿外圈转动来触发动作。", symbol: "hand.draw") {
                        Toggle("启用触控手势", isOn: $model.config.touch.isEnabled).toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                    }
                    TimingSlider(title: "滑动距离", detail: "手指移动超过触控面的这个比例才算滑动。数值越小越灵敏，也越容易误触。",
                                 value: $model.config.touch.swipeDistance, range: 0.15...0.6, tint: Theme.accent,
                                 format: { String(format: "%.0f%%", $0 * 100) })
                    TimingSlider(title: "转动步进", detail: "沿外圈每转过这个角度触发一次。绑定滚动时，数值越小滚得越快。",
                                 value: $model.config.touch.rotationStep, range: 10...90, tint: Theme.live, showsDivider: false,
                                 format: { String(format: "%.0f°", $0) }, step: 5)
                }

                SettingsGroup("启动") {
                    SettingRow(title: "登录时自动启动", detail: "RemoteMapper 只常驻在菜单栏，不占用程序坞。",
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
