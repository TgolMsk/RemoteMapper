import AppKit
import RemoteKit
import SwiftUI

/// 设计规范：颜色、字体与通用修饰。
enum Theme {
    // MARK: 颜色

    /// 主强调色：电光蓝紫。深色背景上更亮，浅色背景上更深以保证对比度
    static let accent = dynamic(light: NSColor(srgbRed: 0.255, green: 0.38, blue: 0.86, alpha: 1),
                                dark: NSColor(srgbRed: 0.45, green: 0.56, blue: 1.0, alpha: 1))
    /// 舞台（左侧遥控器区域）上使用的强调色，始终是深色背景
    static let glow = Color(.sRGB, red: 0.47, green: 0.58, blue: 1.0)
    static let live = Color(.sRGB, red: 0.33, green: 0.86, blue: 0.55)
    static let warning = Color(.sRGB, red: 1.0, green: 0.62, blue: 0.25)

    static let paneBackground = dynamic(light: NSColor(srgbRed: 0.957, green: 0.957, blue: 0.965, alpha: 1),
                                        dark: NSColor(srgbRed: 0.086, green: 0.086, blue: 0.098, alpha: 1))
    static let card = dynamic(light: .white, dark: NSColor(srgbRed: 0.125, green: 0.125, blue: 0.137, alpha: 1))
    static let cardBorder = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.07))
    static let hairline = dynamic(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.06))
    static let rowHover = dynamic(light: NSColor(white: 0, alpha: 0.028), dark: NSColor(white: 1, alpha: 0.035))
    static let subtleFill = dynamic(light: NSColor(white: 0, alpha: 0.045), dark: NSColor(white: 1, alpha: 0.06))
    static let accentFill = dynamic(light: NSColor(srgbRed: 0.255, green: 0.38, blue: 0.86, alpha: 0.10),
                                    dark: NSColor(srgbRed: 0.45, green: 0.56, blue: 1.0, alpha: 0.16))

    /// 预设分组的识别色，方便在列表中快速区分工具
    static func tint(for group: Preset.Group?) -> Color {
        switch group {
        case .claudeCode: accent
        case .claudeDesktop: Color(.sRGB, red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(.sRGB, red: 0.16, green: 0.66, blue: 0.58)
        case .system: Color(.sRGB, red: 0.48, green: 0.50, blue: 0.56)
        case nil: accent
        }
    }

    static func tint(for bound: BoundAction) -> Color {
        tint(for: bound.presetID.flatMap(Preset.find)?.group)
    }

    // 舞台
    static let stageTop = Color(.sRGB, red: 0.094, green: 0.098, blue: 0.118)
    static let stageBottom = Color(.sRGB, red: 0.035, green: 0.037, blue: 0.045)

    // MARK: 字体

    static func eyebrow(_ size: CGFloat = 10.5) -> Font { .system(size: size, weight: .semibold) }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

// MARK: - 通用修饰

struct CardBackground: ViewModifier {
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.03), radius: 12, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
            }
    }
}

extension View {
    func card(padding: CGFloat = 0) -> some View { modifier(CardBackground(padding: padding)) }

    /// 小号大写标题，用于分组名
    func eyebrowStyle() -> some View {
        font(Theme.eyebrow())
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// 分组标题 + 卡片
struct SettingsGroup<Content: View>: View {
    let title: String
    var trailing: AnyView?
    @ViewBuilder let content: Content

    init(_ title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).eyebrowStyle()
                Spacer()
                trailing
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .card()
        }
    }
}

/// 卡片内的一行：标题、说明、右侧控件
struct SettingRow<Accessory: View>: View {
    let title: String
    var detail: String?
    var symbol: String?
    var showsDivider = true
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.subtleFill, in: .rect(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 16)
                accessory
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            if showsDivider {
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, symbol == nil ? 16 : 60)
            }
        }
    }
}

/// 状态胶囊：圆点 + 文字
struct StatusPill: View {
    let text: String
    let color: Color
    var pulsing = false

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if pulsing {
                    Circle().fill(color.opacity(0.35))
                        .frame(width: 12, height: 12)
                        .scaleEffect(pulse ? 1 : 0.4)
                        .opacity(pulse ? 0 : 1)
                }
                Circle().fill(color).frame(width: 6, height: 6)
            }
            .frame(width: 12, height: 12)
            Text(text).font(.system(size: 11.5, weight: .medium))
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: .capsule)
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
