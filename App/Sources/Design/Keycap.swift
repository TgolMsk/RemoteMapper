import AppKit
import RemoteKit
import SwiftUI

/// 实体键帽样式的按键符号
struct Keycap: View {
    let key: String
    var large = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let height: CGFloat = large ? 40 : 21
        Text(key)
            .font(.system(size: large ? 17 : 11, weight: .medium, design: key.count > 1 ? .default : .rounded))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, large ? 12 : 6)
            .frame(minWidth: height, minHeight: height, maxHeight: height)
            .background {
                let shape = RoundedRectangle(cornerRadius: large ? 9 : 5, style: .continuous)
                ZStack {
                    // 键帽底部的厚度
                    shape.fill(colorScheme == .dark ? Color(white: 0.09) : Color(white: 0.78))
                        .offset(y: large ? 2 : 1)
                    shape.fill(LinearGradient(colors: colorScheme == .dark
                                              ? [Color(white: 0.27), Color(white: 0.21)]
                                              : [.white, Color(white: 0.955)],
                                              startPoint: .top, endPoint: .bottom))
                    shape.strokeBorder(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.10), lineWidth: 0.5)
                }
            }
            .padding(.bottom, large ? 2 : 1)
    }
}

struct KeycapRow: View {
    let keys: [String]
    var large = false

    var body: some View {
        HStack(spacing: large ? 6 : 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Keycap(key: key, large: large)
            }
        }
    }
}

/// 点击后录制下一次按下的组合键；单独按下再松开修饰键会被录制为该修饰键本身
struct KeyRecorder: View {
    @Binding var combo: KeyCombo?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var lastModifierKey: UInt16?
    @State private var pulse = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                Group {
                    if isRecording {
                        Text("请按下组合键…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .opacity(pulse ? 0.45 : 1)
                    } else if let combo {
                        KeycapRow(keys: combo.keycaps, large: true)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        Text("点击后按下要发送的按键")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isRecording ? Theme.accent : .secondary)
            }
            .padding(.horizontal, 18)
            .frame(height: 74)
            .background(Theme.card, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isRecording ? Theme.accent : Theme.cardBorder, lineWidth: isRecording ? 2 : 0.5)
            }
            .shadow(color: isRecording ? Theme.accent.opacity(0.25) : .clear, radius: 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: combo)
        .animation(.easeOut(duration: 0.2), value: isRecording)
        .onDisappear(perform: stop)
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        lastModifierKey = nil
        withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        pulse = false
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.type {
        case .keyDown:
            combo = KeyCombo(keyCode: event.keyCode, modifiers: Modifiers(flags))
            stop()
        case .flagsChanged:
            if flags.isEmpty, let key = lastModifierKey {
                combo = KeyCombo(keyCode: key)
                stop()
            } else if !flags.isEmpty {
                lastModifierKey = event.keyCode
            }
        default:
            break
        }
    }
}

extension Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: Modifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }
}
