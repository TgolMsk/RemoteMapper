import RemoteKit
import SwiftUI

/// 左侧舞台：深色背景上的遥控器主视觉、选中部件的标注、实时事件流。
struct StageView: View {
    @Environment(AppModel.self) private var model

    private let remoteWidth: CGFloat = 156
    private let remoteTop: CGFloat = 128
    /// 事件流区域的高度，遥控器在它上方淡出
    private let tickerHeight: CGFloat = 150

    var body: some View {
        let device = model.engine.device
        GeometryReader { proxy in
            let geometry = RemoteGeometry(width: remoteWidth)
            let origin = CGPoint(x: ((proxy.size.width - remoteWidth) / 2).rounded(), y: remoteTop)
            ZStack(alignment: .topLeading) {
                StageBackground(isLit: !device.pressed.isEmpty, focus: CGPoint(x: proxy.size.width / 2, y: origin.y + geometry.padCenter.y))

                RemoteIllustration(geometry: geometry, pressed: device.pressed, selected: model.selectedButton) { button in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        model.tab = .mapping
                        model.selectedButton = button
                    }
                }
                .mask(alignment: .top) {
                    // 最下排按键之下开始淡出，在事件流之前完全消失；上方留出余量，避免裁掉机身阴影
                    let margin: CGFloat = 80
                    let fadeStart = geometry.width * 2.42 + margin
                    let fadeEnd = max(fadeStart + 40, proxy.size.height - tickerHeight - origin.y - 8 + margin)
                    let height = geometry.size.height + margin
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: min(fadeStart / height, 1)),
                        .init(color: .black.opacity(0), location: min(fadeEnd / height, 1)),
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(width: geometry.size.width + 160, height: height)
                    .offset(y: -margin)
                }
                .offset(x: origin.x, y: origin.y)

                Callout(button: model.selectedButton, geometry: geometry, origin: origin, stageWidth: proxy.size.width)
                    .id(model.selectedButton)
                    .transition(.opacity)

                header
                    .padding(.horizontal, 28)
                    .padding(.top, 54)

                EventTicker(entries: Array(model.engine.log.prefix(3)))
                    .frame(width: proxy.size.width - 56, height: tickerHeight - 28, alignment: .topLeading)
                    .offset(x: 28, y: proxy.size.height - tickerHeight)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        let device = model.engine.device
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Siri Remote")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if device.isConnected {
                    StatusPill(text: "已连接", color: Theme.live, pulsing: true)
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    StatusPill(text: "等待连接", color: .white.opacity(0.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Text(deviceLine)
                .font(Theme.mono(11))
                .foregroundStyle(.white.opacity(0.38))
        }
    }

    private var deviceLine: String {
        let device = model.engine.device
        switch device.status {
        case .failed(let message): return message
        case .connected: return "\(device.productName ?? "Siri Remote") · BLE · 004C:0315"
        default: return "请在 系统设置 › 蓝牙 中连接遥控器"
        }
    }
}

// MARK: - 背景

struct StageBackground: View {
    let isLit: Bool
    let focus: CGPoint

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.stageTop, Theme.stageBottom], startPoint: .top, endPoint: .bottom)
            // 顶部聚光
            RadialGradient(colors: [.white.opacity(0.09), .clear], center: .init(x: 0.5, y: 0.12), startRadius: 0, endRadius: 360)
            // 遥控器背后的环境光，按下按键时被点亮
            RadialGradient(colors: [Theme.glow.opacity(0.32), Theme.glow.opacity(0.10), .clear],
                           center: .center, startRadius: 0, endRadius: 230)
                .frame(width: 460, height: 460)
                .scaleEffect(x: 1, y: 0.85)
                .opacity(isLit ? 1 : 0.38)
                .position(focus)
            // 底部压暗，承托事件流
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            Grain().opacity(0.6)
        }
        .animation(.easeOut(duration: isLit ? 0.12 : 0.6), value: isLit)
        .ignoresSafeArea()
    }
}

/// 细颗粒噪点，打破大面积渐变的塑料感
struct Grain: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 42)
            let count = Int(size.width * size.height / 70)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...size.width, using: &generator)
                let y = CGFloat.random(in: 0...size.height, using: &generator)
                let alpha = Double.random(in: 0.02...0.07, using: &generator)
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(alpha)))
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

// MARK: - 标注

/// 从选中部件引出的标注线与说明
struct Callout: View {
    @Environment(AppModel.self) private var model
    let button: RemoteButton
    let geometry: RemoteGeometry
    let origin: CGPoint
    let stageWidth: CGFloat

    private let labelWidth: CGFloat = 104

    var body: some View {
        let side = CalloutSide(button)
        let anchor = geometry.calloutAnchor(of: button, side: side)
        let start = CGPoint(x: origin.x + anchor.x, y: origin.y + anchor.y)
        let remoteEdge = side == .right ? origin.x + geometry.size.width : origin.x
        let labelX = side == .right ? remoteEdge + 26 : remoteEdge - 26 - labelWidth
        let lineEnd = side == .right ? labelX - 6 : labelX + labelWidth + 6

        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: start)
                path.addLine(to: CGPoint(x: lineEnd, y: start.y))
            }
            .stroke(Theme.glow.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            .shadow(color: .black.opacity(0.5), radius: 1)

            Circle()
                .fill(Theme.glow)
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .shadow(color: Theme.glow, radius: 6)
                .position(start)

            label
                .frame(width: labelWidth, alignment: side == .right ? .leading : .trailing)
                .position(x: labelX + labelWidth / 2, y: start.y)
        }
        .allowsHitTesting(false)
    }

    private var label: some View {
        let side = CalloutSide(button)
        let mapping = model.mapping(button, in: model.selectedProfileID) ?? model.inheritedMapping(button, for: model.selectedProfileID)
        let alignment: HorizontalAlignment = side == .right ? .leading : .trailing
        return VStack(alignment: alignment, spacing: 3) {
            Text(button.displayName)
                .font(Theme.eyebrow(10))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.5))
            if let mapping, let primary = RemoteGesture.allCases.lazy.compactMap({ g in mapping[g].map { (g, $0) } }).first {
                Text(primary.1.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(side == .right ? .leading : .trailing)
                Text(mapping.boundGestures.count > 1
                     ? RemoteGesture.allCases.filter { mapping[$0] != nil }.map(\.displayName).joined(separator: " · ")
                     : primary.0.displayName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                Text("未映射")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("保持系统默认")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

// MARK: - 事件流

struct EventTicker: View {
    let entries: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("实时事件")
                    .font(Theme.eyebrow())
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            }
            if entries.isEmpty {
                Text("按下遥控器上的任意键，它会在这里出现，并在右侧被选中。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        EventRow(entry: entry)
                            .opacity(1 - Double(index) * 0.22)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: entries.map(\.id))
            }
        }
    }
}

struct EventRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                .font(Theme.mono(10.5))
                .foregroundStyle(.white.opacity(0.32))
            Image(systemName: entry.button?.symbol ?? "exclamationmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.08)))
            Text(source)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
            Text(entry.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(titleColor)
                .lineLimit(1)
            if entry.kind == .preview {
                Text("预览")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.glow)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Theme.glow.opacity(0.15), in: .capsule)
            }
        }
    }

    private var source: String {
        let name = entry.button?.shortName ?? "系统"
        return entry.gesture.map { "\(name) · \($0.displayName)" } ?? name
    }

    private var titleColor: Color {
        switch entry.kind {
        case .action, .preview: .white.opacity(0.92)
        case .passthrough: .white.opacity(0.5)
        case .error: Theme.warning
        }
    }
}
