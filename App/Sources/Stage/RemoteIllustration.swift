import RemoteKit
import SwiftUI

/// 遥控器各部件的位置，全部以机身宽度为单位，参照第二/三代 Siri Remote 的比例。
struct RemoteGeometry {
    let width: CGFloat

    var size: CGSize { CGSize(width: width, height: width * 3.78) }
    var cornerRadius: CGFloat { width * 0.30 }

    var padCenter: CGPoint { point(0.5, 0.70) }
    var padDiameter: CGFloat { width * 0.84 }
    var innerDiameter: CGFloat { width * 0.40 }
    var keyDiameter: CGFloat { width * 0.30 }
    var powerDiameter: CGFloat { width * 0.12 }
    var volumeSize: CGSize { CGSize(width: width * 0.30, height: width * 0.68) }
    var volumeCenter: CGPoint { point(0.715, 2.0) }
    var siriSize: CGSize { CGSize(width: 4, height: width * 0.34) }

    func center(of button: RemoteButton) -> CGPoint {
        let ringMid = (padDiameter + innerDiameter) / 4
        switch button {
        case .power: return point(0.775, 0.13)
        case .select: return padCenter
        case .up: return CGPoint(x: padCenter.x, y: padCenter.y - ringMid)
        case .down: return CGPoint(x: padCenter.x, y: padCenter.y + ringMid)
        case .left: return CGPoint(x: padCenter.x - ringMid, y: padCenter.y)
        case .right: return CGPoint(x: padCenter.x + ringMid, y: padCenter.y)
        case .back: return point(0.285, 1.43)
        case .tv: return point(0.715, 1.43)
        case .playPause: return point(0.285, 1.81)
        case .mute: return point(0.285, 2.19)
        case .volumeUp: return point(0.715, 1.81)
        case .volumeDown: return point(0.715, 2.19)
        case .siri: return CGPoint(x: width + 1, y: width * 0.94)
        }
    }

    /// 标注线的起点：部件边缘朝向标注一侧的位置
    func calloutAnchor(of button: RemoteButton, side: CalloutSide) -> CGPoint {
        let c = center(of: button)
        let dx: CGFloat
        switch button {
        case .power: dx = powerDiameter / 2
        case .select: dx = innerDiameter / 2
        case .up, .down: dx = 0
        case .left, .right: dx = 0
        case .volumeUp, .volumeDown: dx = volumeSize.width / 2
        case .siri: dx = siriSize.width / 2
        default: dx = keyDiameter / 2
        }
        return CGPoint(x: c.x + (side == .right ? dx : -dx), y: c.y)
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * width, y: y * width) }
}

enum CalloutSide {
    case left, right

    init(_ button: RemoteButton) {
        switch button {
        case .back, .playPause, .mute, .left: self = .left
        default: self = .right
        }
    }
}

/// 可交互的遥控器插画：按下时发光，点击选中部件。
struct RemoteIllustration: View {
    let geometry: RemoteGeometry
    let pressed: Set<RemoteButton>
    /// 触控模式下没有选中的按键
    let selected: RemoteButton?
    let onSelect: (RemoteButton) -> Void

    @State private var hovered: RemoteButton?

    var body: some View {
        ZStack(alignment: .topLeading) {
            AluminumBody(cornerRadius: geometry.cornerRadius)
                .frame(width: geometry.size.width, height: geometry.size.height)

            siriButton
            key(.power, diameter: geometry.powerDiameter, symbolScale: 0.42)
            ClickPad(geometry: geometry, pressed: pressed, selected: selected, hovered: $hovered, onSelect: onSelect)
                .frame(width: geometry.padDiameter, height: geometry.padDiameter)
                .position(geometry.padCenter)
            key(.back)
            key(.tv)
            key(.playPause)
            key(.mute)
            VolumeRocker(geometry: geometry, pressed: pressed, selected: selected, hovered: $hovered, onSelect: onSelect)
                .frame(width: geometry.volumeSize.width, height: geometry.volumeSize.height)
                .position(geometry.volumeCenter)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    }

    private func key(_ button: RemoteButton, diameter: CGFloat? = nil, symbolScale: CGFloat = 0.34) -> some View {
        let d = diameter ?? geometry.keyDiameter
        return RemoteKey(button: button, isPressed: pressed.contains(button), isSelected: selected == button,
                         isHovered: hovered == button, symbolScale: symbolScale)
            .frame(width: d, height: d)
            .contentShape(Circle())
            .onHover { hovered = $0 ? button : (hovered == button ? nil : hovered) }
            .onTapGesture { onSelect(button) }
            .position(geometry.center(of: button))
    }

    /// 机身右侧的 Siri 键，正面只露出一道边
    private var siriButton: some View {
        let isPressed = pressed.contains(.siri)
        let isSelected = selected == .siri
        let size = geometry.siriSize
        return Capsule()
            .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.06)], startPoint: .leading, endPoint: .trailing))
            .overlay(Capsule().fill(Theme.glow.opacity(isPressed ? 0.9 : 0)))
            .frame(width: size.width, height: size.height)
            .shadow(color: Theme.glow.opacity(isPressed ? 0.9 : 0), radius: 8)
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(Theme.glow, lineWidth: 1.5)
                        .frame(width: size.width + 8, height: size.height + 8)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .frame(width: 26, height: size.height + 10)
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? .siri : (hovered == .siri ? nil : hovered) }
            .onTapGesture { onSelect(.siri) }
            .position(geometry.center(of: .siri))
            .animation(.easeOut(duration: 0.12), value: isPressed)
    }
}

// MARK: - 机身

struct AluminumBody: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient(stops: [
                .init(color: Color(white: 0.70), location: 0),
                .init(color: Color(white: 0.86), location: 0.16),
                .init(color: Color(white: 0.93), location: 0.48),
                .init(color: Color(white: 0.84), location: 0.84),
                .init(color: Color(white: 0.66), location: 1),
            ], startPoint: .leading, endPoint: .trailing))
            .overlay {
                // 顶部受光、底部渐暗
                shape.fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.28), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .black.opacity(0.10), location: 1),
                ], startPoint: .top, endPoint: .bottom))
            }
            .overlay { BrushedTexture().clipShape(shape).blendMode(.overlay).opacity(0.55) }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.25), .black.opacity(0.18)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
            }
            .overlay { shape.stroke(.black.opacity(0.55), lineWidth: 0.6) }
            .shadow(color: .black.opacity(0.55), radius: 36, x: 0, y: 30)
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 4)
    }
}

/// 拉丝铝的细纹理，用固定种子保证每次绘制一致
struct BrushedTexture: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 7)
            for _ in 0..<Int(size.width * 2.2) {
                let x = CGFloat.random(in: 0...size.width, using: &generator)
                let light = Bool.random(using: &generator)
                let alpha = Double.random(in: 0.04...0.16, using: &generator)
                context.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)),
                             with: .color(light ? .white.opacity(alpha) : .black.opacity(alpha * 0.6)))
            }
        }
        .allowsHitTesting(false)
    }
}

nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - 按键

/// 黑色圆形按键
struct RemoteKey: View {
    let button: RemoteButton
    let isPressed: Bool
    let isSelected: Bool
    let isHovered: Bool
    var symbolScale: CGFloat = 0.34

    var body: some View {
        GeometryReader { proxy in
            let d = proxy.size.width
            ZStack {
                // 机身上的凹槽
                Circle().fill(.black.opacity(0.22)).padding(-1.5).blur(radius: 0.6)
                Circle().fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.075)], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                Circle().fill(RadialGradient(colors: [Theme.glow.opacity(0.85), Theme.glow.opacity(0.15)],
                                             center: .center, startRadius: 0, endRadius: d * 0.6))
                    .opacity(isPressed ? 1 : 0)
                Circle().fill(.white.opacity(isHovered && !isPressed ? 0.07 : 0))
                Image(systemName: button.symbol)
                    .font(.system(size: d * symbolScale, weight: .semibold))
                    .foregroundStyle(.white.opacity(isPressed ? 1 : 0.86))
                if isSelected {
                    Circle().strokeBorder(Theme.glow, lineWidth: 1.6)
                        .padding(-5)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .scaleEffect(isPressed ? 0.93 : 1)
            .shadow(color: Theme.glow.opacity(isPressed ? 0.8 : 0), radius: 14)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// 音量 +/− 竖条
struct VolumeRocker: View {
    let geometry: RemoteGeometry
    let pressed: Set<RemoteButton>
    /// 触控模式下没有选中的按键
    let selected: RemoteButton?
    @Binding var hovered: RemoteButton?
    let onSelect: (RemoteButton) -> Void

    var body: some View {
        let size = geometry.volumeSize
        ZStack {
            Capsule().fill(.black.opacity(0.22)).padding(-1.5).blur(radius: 0.6)
            Capsule().fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.075)], startPoint: .top, endPoint: .bottom))
            Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
            VStack(spacing: 0) {
                half(.volumeUp)
                half(.volumeDown)
            }
            .clipShape(Capsule())
            ForEach([RemoteButton.volumeUp, .volumeDown], id: \.self) { button in
                if selected == button {
                    Capsule().strokeBorder(Theme.glow, lineWidth: 1.6)
                        .frame(width: size.width + 10, height: size.height / 2 + 6)
                        .offset(y: button == .volumeUp ? -size.height / 4 : size.height / 4)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
        .shadow(color: Theme.glow.opacity(pressed.contains(.volumeUp) || pressed.contains(.volumeDown) ? 0.7 : 0), radius: 14)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pressed)
    }

    private func half(_ button: RemoteButton) -> some View {
        let isPressed = pressed.contains(button)
        return ZStack {
            Rectangle().fill(RadialGradient(colors: [Theme.glow.opacity(0.85), Theme.glow.opacity(0.1)],
                                            center: .center, startRadius: 0, endRadius: geometry.volumeSize.width * 0.7))
                .opacity(isPressed ? 1 : 0)
            Rectangle().fill(.white.opacity(hovered == button && !isPressed ? 0.07 : 0))
            Image(systemName: button.symbol)
                .font(.system(size: geometry.volumeSize.width * 0.36, weight: .semibold))
                .foregroundStyle(.white.opacity(isPressed ? 1 : 0.86))
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? button : (hovered == button ? nil : hovered) }
        .onTapGesture { onSelect(button) }
    }
}

// MARK: - 触控板

/// 圆环扇区
nonisolated struct RingSegment: Shape {
    /// 扇区中心方向，0° 朝上、顺时针
    var direction: Double
    var span: Double = 90
    var innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let start = Angle(degrees: direction - 90 - span / 2)
        let end = Angle(degrees: direction - 90 + span / 2)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct ClickPad: View {
    let geometry: RemoteGeometry
    let pressed: Set<RemoteButton>
    /// 触控模式下没有选中的按键
    let selected: RemoteButton?
    @Binding var hovered: RemoteButton?
    let onSelect: (RemoteButton) -> Void

    private static let directions: [(RemoteButton, Double)] = [(.up, 0), (.right, 90), (.down, 180), (.left, 270)]

    var body: some View {
        let d = geometry.padDiameter
        let innerRatio = geometry.innerDiameter / d
        ZStack {
            Circle().fill(.black.opacity(0.25)).padding(-2).blur(radius: 1)
            Circle().fill(RadialGradient(colors: [Color(white: 0.16), Color(white: 0.055)], center: .init(x: 0.5, y: 0.42),
                                         startRadius: 0, endRadius: d * 0.55))
            // 左上方的镜面高光
            Circle().fill(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center))
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 1)

            ForEach(Self.directions, id: \.0) { button, angle in
                let isPressed = pressed.contains(button)
                RingSegment(direction: angle, innerRatio: innerRatio)
                    .fill(RadialGradient(colors: [Theme.glow.opacity(0.75), Theme.glow.opacity(0.05)], center: .center,
                                         startRadius: d * innerRatio / 2, endRadius: d / 2))
                    .opacity(isPressed ? 1 : 0)
                RingSegment(direction: angle, innerRatio: innerRatio)
                    .fill(.white.opacity(hovered == button && !isPressed ? 0.05 : 0))
                if selected == button {
                    RingSegment(direction: angle, span: 74, innerRatio: innerRatio + 0.06)
                        .stroke(Theme.glow, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                        .padding(5)
                        .transition(.opacity)
                }
            }

            // 方向指示点
            ForEach(Self.directions, id: \.0) { button, angle in
                let radius = (d + geometry.innerDiameter) / 4
                Circle()
                    .fill(.white.opacity(pressed.contains(button) ? 0.95 : 0.32))
                    .frame(width: 3.5, height: 3.5)
                    .offset(x: sin(angle * .pi / 180) * radius, y: -cos(angle * .pi / 180) * radius)
            }

            // 中央按压区
            let isSelectPressed = pressed.contains(.select)
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.13), Color(white: 0.07)], center: .center, startRadius: 0,
                                     endRadius: geometry.innerDiameter / 2))
                .overlay(Circle().fill(RadialGradient(colors: [Theme.glow.opacity(0.85), Theme.glow.opacity(0.1)],
                                                      center: .center, startRadius: 0, endRadius: geometry.innerDiameter / 2))
                    .opacity(isSelectPressed ? 1 : 0))
                .overlay(Circle().fill(.white.opacity(hovered == .select && !isSelectPressed ? 0.06 : 0)))
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 0.8))
                .overlay {
                    if selected == .select {
                        Circle().strokeBorder(Theme.glow, lineWidth: 1.6).padding(-5)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .frame(width: geometry.innerDiameter, height: geometry.innerDiameter)
                .scaleEffect(isSelectPressed ? 0.96 : 1)
        }
        .shadow(color: Theme.glow.opacity(pressed.contains(where: { $0.isDirectional || $0 == .select }) ? 0.55 : 0), radius: 18)
        .contentShape(Circle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hovered = region(at: location, diameter: d)
            case .ended: if hovered.map(isPadButton) == true { hovered = nil }
            }
        }
        .gesture(SpatialTapGesture().onEnded { value in
            if let button = region(at: value.location, diameter: d) { onSelect(button) }
        })
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: selected)
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    private func isPadButton(_ button: RemoteButton) -> Bool { button.isDirectional || button == .select }

    private func region(at location: CGPoint, diameter d: CGFloat) -> RemoteButton? {
        let dx = location.x - d / 2
        let dy = location.y - d / 2
        let distance = hypot(dx, dy)
        guard distance <= d / 2 else { return nil }
        if distance <= geometry.innerDiameter / 2 { return .select }
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }
}
