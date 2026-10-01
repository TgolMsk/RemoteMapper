import AppKit
import RemoteKit
import SwiftUI

/// 菜单栏弹出面板
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        let device = model.engine.device
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppGlyph(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RemoteMapper").font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 5) {
                        Circle().fill(device.isConnected ? Theme.live : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                        Text(device.isConnected ? "遥控器已连接" : "等待遥控器连接")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("启用映射", isOn: $model.config.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(Theme.accent)
            }
            .padding(16)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("当前配置").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text(model.config.isEnabled ? model.activeProfile.name : "已暂停")
                        .font(.system(size: 12, weight: .semibold))
                }
                if let entry = model.engine.log.first {
                    HStack(spacing: 8) {
                        Image(systemName: entry.button?.symbol ?? "exclamationmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(Theme.subtleFill, in: .circle)
                        Text(entry.title).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 5)) { context in
                            Text(relativeTime(entry.date, now: context.date))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(16)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            VStack(spacing: 2) {
                MenuRow(title: "打开设置…", shortcut: "⌘,") {
                    openWindow(id: SettingsWindow.id)
                    NSApp.activate()
                }
                .keyboardShortcut(",")
                MenuRow(title: "退出 RemoteMapper", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(6)
        }
        .frame(width: 300)
    }

    private func relativeTime(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 5 { return "刚刚" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

struct MenuRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                Text(shortcut).font(.system(size: 12)).foregroundStyle(isHovered ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(isHovered ? .white : .primary)
            .background(isHovered ? Theme.accent : .clear, in: .rect(cornerRadius: 7, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// App 图标的矢量版本：深色方块中的遥控器触控板与发光扇区
struct AppGlyph: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            Circle()
                .fill(Color(white: 0.04))
                .frame(width: size * 0.62, height: size * 0.62)
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
            RingSegment(direction: 0, span: 80, innerRatio: 0.48)
                .fill(Theme.glow)
                .frame(width: size * 0.62, height: size * 0.62)
                .shadow(color: Theme.glow, radius: size * 0.08)
            Circle()
                .fill(Color(white: 0.11))
                .frame(width: size * 0.26, height: size * 0.26)
        }
        .frame(width: size, height: size)
    }
}
