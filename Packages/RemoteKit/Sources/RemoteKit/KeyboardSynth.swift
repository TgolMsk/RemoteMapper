import AppKit
import CoreGraphics

/// 通过 CGEvent 合成键盘事件。需要「辅助功能」权限，否则事件会被系统静默丢弃。
public enum KeyboardSynth {
    /// 写入 eventSourceUserData，标记本 App 合成的事件，避免被自己的事件拦截器处理
    public static let eventMarker: Int64 = 0x524D_4150

    private static let source = CGEventSource(stateID: .hidSystemState)

    public static func tap(_ combo: KeyCombo) {
        post(combo, down: true)
        post(combo, down: false)
    }

    public static func beginHold(_ combo: KeyCombo) -> HoldSession {
        HoldSession(combo: combo)
    }

    /// 以 Unicode 方式输入文字，不受当前键盘布局与输入法影响
    public static func type(_ text: String) {
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(index + 16, units.count)])
            index += chunk.count
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// 按行滚动：向下即显示下方内容
    public static func scroll(_ direction: ScrollDirection, lines: Int) {
        let amount = Int32(max(1, lines))
        let (vertical, horizontal): (Int32, Int32) = switch direction {
        case .up: (amount, 0)
        case .down: (-amount, 0)
        case .left: (0, amount)
        case .right: (0, -amount)
        }
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2,
                                  wheel1: vertical, wheel2: horizontal, wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
        event.post(tap: .cghidEventTap)
    }

    static func post(_ combo: KeyCombo, down: Bool, autorepeat: Bool = false) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: down) else { return }
        if let modifierFlag = KeyNames.modifierFlag(for: combo.keyCode) {
            // 单独的修饰键需要以 flagsChanged 事件发送，App 才会识别为「按了一下 ⌥」
            event.type = .flagsChanged
            event.flags = down ? modifierFlag.union(combo.modifiers.cgFlags) : []
        } else {
            event.flags = combo.modifiers.cgFlags
        }
        if autorepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
        event.post(tap: .cghidEventTap)
    }
}

/// 一次「按住」：开始时按下，之后按系统键盘重复速率发送自动重复事件，结束时松开。
/// 终端程序收不到松开事件，只能通过连续的重复字符判断按键仍被按住，所以必须模拟自动重复。
public final class HoldSession {
    private let combo: KeyCombo
    private var timer: Timer?
    private var delayTask: Task<Void, Never>?

    init(combo: KeyCombo) {
        self.combo = combo
        KeyboardSynth.post(combo, down: true)
        guard !combo.isModifierKey else { return }
        let delay = NSEvent.keyRepeatDelay
        let interval = max(NSEvent.keyRepeatInterval, 0.015)
        delayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [combo] _ in
                MainActor.assumeIsolated { KeyboardSynth.post(combo, down: true, autorepeat: true) }
            }
        }
    }

    public func end() {
        delayTask?.cancel()
        timer?.invalidate()
        timer = nil
        KeyboardSynth.post(combo, down: false)
    }
}
