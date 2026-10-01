import AppKit
import RemoteKit
import SwiftUI

/// 触控板在光标、滚轮、手势之间切换时，在屏幕下方短暂显示当前状态。
/// 用遥控器切换时看不到设置界面，没有提示就不知道现在滑动是移动光标还是滚动
final class PointerModeToast {
    enum State: Equatable {
        case cursor, wheel, gestures

        var title: String {
            switch self {
            case .cursor: "光标"
            case .wheel: "滚轮 · 滑动翻页"
            case .gestures: "触控手势"
            }
        }

        var symbol: String {
            switch self {
            case .cursor: "cursorarrow"
            case .wheel: "scroll"
            case .gestures: "hand.draw"
            }
        }
    }

    private let model: AppModel
    private var panel: NSPanel?
    private var host: NSHostingView<PointerModeToastView>?
    private var hideTask: Task<Void, Never>?
    private var last: State
    private static let size = CGSize(width: 320, height: 96)

    init(model: AppModel) {
        self.model = model
        last = Self.state(of: model)
        observe()
    }

    private static func state(of model: AppModel) -> State {
        guard model.config.touch.mode == .pointer else { return .gestures }
        return model.engine.isPointerScrolling ? .wheel : .cursor
    }

    private func observe() {
        withObservationTracking {
            _ = model.engine.isPointerScrolling
            _ = model.config.touch.mode
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.changed()
                self?.observe()
            }
        }
    }

    private func changed() {
        let state = Self.state(of: model)
        guard state != last else { return }
        last = state
        guard model.config.isEnabled, model.config.touch.isEnabled else { return }
        show(state)
    }

    private func show(_ state: State) {
        let panel = panel ?? makePanel()
        self.panel = panel
        host?.rootView = PointerModeToastView(state: state)
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
            try? await Task.sleep(for: .seconds(1.1))
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
        let host = NSHostingView(rootView: PointerModeToastView(state: last))
        host.frame = CGRect(origin: .zero, size: Self.size)
        panel.contentView = host
        self.host = host
        return panel
    }
}

/// 提示内容，样式与语音输入浮窗一致
struct PointerModeToastView: View {
    let state: PointerModeToast.State

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.symbol)
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
            Text(state.title)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            Capsule(style: .continuous)
                .fill(Color(white: 0.08).opacity(0.92))
                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 20)
    }
}
