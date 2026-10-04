import AppKit
import RemoteKit
import SwiftUI

/// 语音输入浮窗：录音期间显示在屏幕底部，不抢焦点、不接收鼠标，文字仍然输入到当前 App。
@MainActor
final class DictationHUDController {
    private let model: AppModel
    private var panel: NSPanel?
    static let size = CGSize(width: 480, height: 96)

    init(model: AppModel) {
        self.model = model
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = model.engine.dictation.phase
            _ = model.config.voice.showsHUD
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
        update()
    }

    private func update() {
        let dictation = model.engine.dictation
        let visible = model.config.voice.showsHUD && dictation.phase != .idle
        visible ? show() : hide()
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        guard !panel.isVisible else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 56))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                if self.model.engine.dictation.phase == .idle { panel.orderOut(nil) }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: DictationHUDView()
            .environment(model)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom))
        host.frame = CGRect(origin: .zero, size: Self.size)
        panel.contentView = host
        return panel
    }
}

/// 浮窗内容：随音量跳动的麦克风、实时识别文字、状态提示
struct DictationHUDView: View {
    @Environment(AppModel.self) private var model
    @State private var levels: [Float] = Array(repeating: 0, count: 16)

    var body: some View {
        let dictation = model.engine.dictation
        HStack(spacing: 12) {
            MicOrb(level: dictation.level, phase: dictation.phase)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline(dictation.phase))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(L10n.language.isRightToLeft ? 0 : 0.5)
                    .foregroundStyle(headlineColor(dictation.phase))
                Text(bodyText(dictation))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(dictation.transcript.isEmpty ? .white.opacity(0.45) : .white)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.interpolate)
                    .animation(.easeOut(duration: 0.15), value: dictation.transcript)
            }
            Group {
                if dictation.phase == .listening {
                    Waveform(levels: levels).transition(.opacity)
                } else if dictation.phase == .finishing {
                    ProgressView().controlSize(.small).tint(.white)
                }
            }
            .frame(width: 46, height: 20)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .frame(width: 400)
        .hudBackground()
        .padding(.bottom, 20)
        .environment(\.locale, L10n.locale)
        .environment(\.layoutDirection, L10n.language.isRightToLeft ? .rightToLeft : .leftToRight)
        .onChange(of: dictation.level) {
            levels.removeFirst()
            levels.append(dictation.level)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: dictation.phase)
    }

    private func headline(_ phase: VoiceDictation.Phase) -> String {
        switch phase {
        case .starting: L10n.text("准备中")
        case .listening: model.engine.dictation.endsOnRelease ? L10n.text("正在聆听 · 松开遥控器结束") : L10n.text("正在聆听 · 再按一次结束")
        case .finishing: L10n.text("正在识别")
        case .failed: L10n.text("语音输入不可用")
        case .idle: ""
        }
    }

    private func headlineColor(_ phase: VoiceDictation.Phase) -> Color {
        if case .failed = phase { return Theme.warning }
        return .white.opacity(0.5)
    }

    private func bodyText(_ dictation: VoiceDictation) -> String {
        if case .failed(let message) = dictation.phase { return message }
        if !dictation.transcript.isEmpty { return dictation.transcript }
        return dictation.phase == .listening ? L10n.text("请说话…") : "…"
    }
}

/// 麦克风圆球：音量越大光晕越亮
struct MicOrb: View {
    let level: Float
    let phase: VoiceDictation.Phase

    var body: some View {
        let isFailed: Bool = { if case .failed = phase { return true } else { return false } }()
        let tint = isFailed ? Theme.warning : Theme.tint(for: .voice)
        let energy = phase == .listening ? CGFloat(level) : 0
        ZStack {
            Circle()
                .fill(tint.opacity(0.35))
                .frame(width: 32, height: 32)
                .scaleEffect(1 + energy * 0.5)
                .opacity(0.25 + Double(energy) * 0.75)
            Circle()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 30)
                .shadow(color: tint.opacity(0.6), radius: 3 + energy * 8)
            Image(systemName: isFailed ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
        .animation(.easeOut(duration: 0.12), value: level)
    }
}

/// 最近一段时间的音量波形
struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(.white.opacity(0.35 + Double(index) / Double(levels.count) * 0.55))
                    .frame(width: 2, height: max(3, CGFloat(value) * 20))
            }
        }
        .animation(.easeOut(duration: 0.1), value: levels)
    }
}
