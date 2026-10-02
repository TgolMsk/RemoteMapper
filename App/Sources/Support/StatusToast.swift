import AppKit
import RemoteKit
import SwiftUI

/// 屏幕下方的短暂提示：触控板在光标、滚轮、手势之间切换，以及引擎发出的状态消息（例如电源菜单的选项）。
/// 用遥控器操作时看不到设置界面，没有提示就不知道当前状态
final class StatusToast {
    struct Content: Equatable {
        var symbol: String
        var title: String
        var detail: String?
    }

    private enum PointerState: Equatable {
        case cursor, wheel, gestures

        var content: Content {
            switch self {
            case .cursor: Content(symbol: "cursorarrow", title: "光标")
            case .wheel: Content(symbol: "scroll", title: "滚轮 · 滑动翻页")
            case .gestures: Content(symbol: "hand.draw", title: "触控手势")
            }
        }
    }

    private let model: AppModel
    private var panel: NSPanel?
    private var host: NSHostingView<StatusToastView>?
    private var hideTask: Task<Void, Never>?
    private var lastPointerState: PointerState
    private var lastMessageID: UUID?
    private static let size = CGSize(width: 460, height: 120)

    init(model: AppModel) {
        self.model = model
        lastPointerState = Self.pointerState(of: model)
        lastMessageID = model.engine.statusMessage?.id
        observe()
    }

    private static func pointerState(of model: AppModel) -> PointerState {
        guard model.config.touch.mode == .pointer else { return .gestures }
        return model.engine.isPointerScrolling ? .wheel : .cursor
    }

    private func observe() {
        withObservationTracking {
            _ = model.engine.isPointerScrolling
            _ = model.config.touch.mode
            _ = model.engine.statusMessage
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.changed()
                self?.observe()
            }
        }
    }

    private func changed() {
        if let message = model.engine.statusMessage, message.id != lastMessageID {
            lastMessageID = message.id
            show(Content(symbol: message.symbol, title: message.title, detail: message.detail), for: message.duration)
            return
        }
        let state = Self.pointerState(of: model)
        guard state != lastPointerState else { return }
        lastPointerState = state
        guard model.config.isEnabled, model.config.touch.isEnabled else { return }
        show(state.content, for: 1.1)
    }

    private func show(_ content: Content, for duration: TimeInterval) {
        let panel = panel ?? makePanel()
        self.panel = panel
        host?.rootView = StatusToastView(content: content)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 56))
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                if panel.alphaValue == 0 { panel.orderOut(nil) }
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
        let host = NSHostingView(rootView: StatusToastView(content: lastPointerState.content))
        host.frame = CGRect(origin: .zero, size: Self.size)
        panel.contentView = host
        self.host = host
        return panel
    }
}

/// 提示内容，背景与语音输入浮窗一致
struct StatusToastView: View {
    let content: StatusToast.Content

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: content.symbol)
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(size: 14, weight: .semibold))
                if let detail = content.detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .hudBackground()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 20)
    }
}
