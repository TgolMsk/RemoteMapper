import AppKit
import CoreGraphics
import os

/// 拦截被映射的遥控器媒体键（音量、静音、播放、电源）原本的系统行为。
/// 电源键不拦截时，系统会弹出「确定要现在将电脑关机吗？」对话框。
///
/// 系统媒体键事件（NX_SYSDEFINED）不携带来源设备信息，只能按时间与遥控器的 HID 报告关联：
/// 遥控器刚按过对应按钮 → 丢弃；否则先扣下事件，短暂等待遥控器报告，
/// 仍未出现则判定来自键盘，原样重新投递。因此键盘媒体键只会在对应按钮被映射时多出约 60ms 延迟。
public final class MediaKeyInterceptor {
    /// 某个按钮当前是否需要拦截（已映射且启用）
    public var shouldIntercept: (RemoteButton) -> Bool = { _ in false }

    public private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastRemoteActivity: [RemoteButton: TimeInterval] = [:]
    private var deferred: [(event: CGEvent, button: RemoteButton, time: TimeInterval)] = []

    private static let log = Logger(subsystem: "com.ws.RemoteMapper", category: "mediakey")
    private static let mediaButtons: Set<RemoteButton> = [.volumeUp, .volumeDown, .mute, .playPause, .power]
    private static let correlationWindow: TimeInterval = 0.35
    private static let deferWindow: TimeInterval = 0.06
    /// NX_SYSDEFINED 事件类型与媒体键子类型
    private static let systemDefinedType = CGEventType(rawValue: 14)!
    private static let mediaKeySubtype: Int16 = 8

    public init() {}

    /// 需要辅助功能权限，失败返回 false
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefinedType.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: mediaKeyTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            isRunning = false
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        isRunning = true
        return true
    }

    public func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        isRunning = false
        flushDeferred()
    }

    /// 遥控器按钮按下或松开时调用
    public func noteRemoteActivity(_ button: RemoteButton) {
        let now = ProcessInfo.processInfo.systemUptime
        lastRemoteActivity[button] = now
        guard Self.mediaButtons.contains(button) else { return }
        // 先到的系统事件正等待判定，遥控器报告随后到达 → 确认来自遥控器，直接丢弃
        let matched = deferred.filter { $0.button == button }
        deferred.removeAll { $0.button == button }
        Self.log.info("遥控器报告：\(button.displayName, privacy: .public)\(matched.isEmpty ? "" : "，丢弃先到的 \(matched.count) 个系统事件", privacy: .public)")
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        }
        guard type == Self.systemDefinedType,
              event.getIntegerValueField(.eventSourceUserData) != KeyboardSynth.eventMarker,
              let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == Self.mediaKeySubtype else {
            return event
        }
        let key = (nsEvent.data1 & 0xFFFF_0000) >> 16
        let state = (nsEvent.data1 & 0xFF00) >> 8 == 0x0A ? "按下" : "松开"
        guard let button = Self.button(forMediaKey: key) else {
            Self.log.info("系统媒体键 \(key) \(state, privacy: .public)：遥控器上没有对应按钮，放行")
            return event
        }
        guard shouldIntercept(button) else {
            Self.log.info("系统媒体键 \(button.displayName, privacy: .public) \(state, privacy: .public)：未映射或未接管，放行")
            return event
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastRemoteActivity[button], now - last < Self.correlationWindow {
            Self.log.info("系统媒体键 \(button.displayName, privacy: .public) \(state, privacy: .public)：\(Int((now - last) * 1000)) ms 前遥控器刚按过，丢弃")
            return nil
        }
        Self.log.info("系统媒体键 \(button.displayName, privacy: .public) \(state, privacy: .public)：暂扣，等待遥控器报告")
        guard let copy = event.copy() else { return event }
        deferred.append((copy, button, now))
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deferWindow) { [weak self] in
            MainActor.assumeIsolated { self?.flushDeferred(olderThan: Self.deferWindow) }
        }
        return nil
    }

    /// 把等待超时、判定为来自键盘的事件重新投递
    private func flushDeferred(olderThan age: TimeInterval = 0) {
        let now = ProcessInfo.processInfo.systemUptime
        let expired = deferred.filter { now - $0.time >= age - 0.005 }
        deferred.removeAll { now - $0.time >= age - 0.005 }
        for item in expired {
            Self.log.info("系统媒体键 \(item.button.displayName, privacy: .public)：未等到遥控器报告，判定来自键盘，重新投递")
            item.event.setIntegerValueField(.eventSourceUserData, value: KeyboardSynth.eventMarker)
            item.event.post(tap: .cghidEventTap)
        }
    }

    /// 遥控器按钮对应的系统媒体键；电源键不在其中：代发的电源键事件不会让系统做任何事
    static func mediaKey(for button: RemoteButton) -> Int? {
        switch button {
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        case .playPause: 16
        default: nil
        }
    }

    /// NX_KEYTYPE_* 与遥控器按钮的对应关系
    static func button(forMediaKey key: Int) -> RemoteButton? {
        switch key {
        case 0: .volumeUp      // NX_KEYTYPE_SOUND_UP
        case 1: .volumeDown    // NX_KEYTYPE_SOUND_DOWN
        case 6: .power         // NX_POWER_KEY
        case 7: .mute          // NX_KEYTYPE_MUTE
        case 16: .playPause    // NX_KEYTYPE_PLAY
        default: nil
        }
    }
}

private nonisolated func mediaKeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                             userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let address = UInt(bitPattern: userInfo)
    nonisolated(unsafe) let event = event
    nonisolated(unsafe) var result: Unmanaged<CGEvent>? = Unmanaged.passUnretained(event)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(pointer).takeUnretainedValue()
        result = interceptor.handle(type: type, event: event).map { Unmanaged.passUnretained($0) }
    }
    return result
}
