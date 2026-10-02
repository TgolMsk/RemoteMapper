import Foundation
import IOKit.hid
import Observation
import os

/// 通过 IOHIDManager 读取 Siri Remote 按键接口的原始报告。
/// 回调都挂在主线程 run loop 上，因此在主线程处理。
@Observable
public final class RemoteDevice {
    public static let vendorID = 0x004C
    public static let productID = 0x0315

    public enum Status: Equatable, Sendable {
        case idle
        case searching
        case connected
        case failed(String)
    }

    public private(set) var status: Status = .idle {
        didSet { if status != oldValue { Self.log.info("遥控器状态：\(String(describing: self.status), privacy: .public)") } }
    }
    private static let log = Logger(subsystem: "com.ws.RemoteMapper", category: "device")
    public private(set) var productName: String?
    public private(set) var pressed: Set<RemoteButton> = []
    public private(set) var lastReport: [UInt8] = []
    public private(set) var lastReportDate: Date?

    public var isConnected: Bool { status == .connected }

    /// 按钮状态变化：(按钮, 是否按下)
    @ObservationIgnored public var onButton: ((RemoteButton, Bool) -> Void)?
    /// 遥控器连接或断开
    @ObservationIgnored public var onConnectionChange: ((Bool) -> Void)?

    @ObservationIgnored private var manager: IOHIDManager?
    @ObservationIgnored private var sinks: [ReportSink] = []

    /// 独占遥控器的按键接口：系统不再收到任何按键，只由本 App 处理。
    /// 电源键在 HID 驱动里直接通知电源管理弹出关机对话框，事件拦截挡不住，只能这样屏蔽
    public var isExclusive = false {
        didSet {
            guard isExclusive != oldValue, manager != nil else { return }
            stop()
            start()
        }
    }

    public init() {}

    public func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDPrimaryUsagePageKey: 0x0C,
            kIOHIDPrimaryUsageKey: 0x01,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemoved, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        var result = IOHIDManagerOpen(manager, IOOptionBits(isExclusive ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone))
        if isExclusive, result != kIOReturnSuccess {
            Self.log.error("独占按键接口失败 0x\(String(UInt32(bitPattern: result), radix: 16), privacy: .public)，改为共享读取")
            result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        } else if isExclusive {
            Self.log.info("已独占遥控器按键接口")
        }
        if result == kIOReturnSuccess {
            status = sinks.isEmpty ? .searching : .connected
        } else if result == kIOReturnNotPermitted {
            status = .failed("没有读取输入设备的权限（输入监控）")
        } else {
            status = .failed(String(format: "IOHIDManagerOpen 失败 0x%08x", result))
        }
        self.manager = manager
    }

    public func stop() {
        guard let manager else { return }
        for sink in sinks { sink.detach() }
        sinks.removeAll()
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        if isExclusive { Self.log.info("已释放遥控器按键接口") }
        releaseAll()
        status = .idle
    }

    /// 仅用于界面预览与截图：注入连接与按键状态
    public func simulate(connected: Bool, pressed: Set<RemoteButton> = [], productName: String? = nil) {
        status = connected ? .connected : .searching
        self.productName = productName
        self.pressed = pressed
    }

    fileprivate func attach(_ device: IOHIDDevice) {
        guard !sinks.contains(where: { $0.device === device }) else { return }
        let sink = ReportSink(device: device, owner: self)
        sinks.append(sink)
        productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        let wasConnected = isConnected
        status = .connected
        if !wasConnected { onConnectionChange?(true) }
    }

    fileprivate func detach(_ device: IOHIDDevice) {
        sinks.removeAll { sink in
            guard sink.device === device else { return false }
            sink.detach()
            return true
        }
        if sinks.isEmpty {
            releaseAll()
            status = manager == nil ? .idle : .searching
            onConnectionChange?(false)
        }
    }

    fileprivate func handleReport(reportID: UInt32, bytes: [UInt8]) {
        guard let now = RemoteReport.pressedButtons(reportID: reportID, bytes: bytes) else { return }
        lastReport = bytes
        lastReportDate = Date()
        let released = pressed.subtracting(now)
        let newlyPressed = now.subtracting(pressed)
        pressed = now
        for button in released.sorted(by: { $0.bit < $1.bit }) { onButton?(button, false) }
        for button in newlyPressed.sorted(by: { $0.bit < $1.bit }) { onButton?(button, true) }
    }

    /// 断开时把仍处于按下状态的按钮全部松开，避免「按住」动作卡住
    private func releaseAll() {
        let held = pressed
        pressed = []
        for button in held { onButton?(button, false) }
    }
}

/// 持有单个 HID 接口的报告缓冲区，生命周期与接口一致。
private final class ReportSink {
    let device: IOHIDDevice
    nonisolated(unsafe) let buffer: UnsafeMutablePointer<UInt8>
    let size: Int
    weak var owner: RemoteDevice?

    init(device: IOHIDDevice, owner: RemoteDevice) {
        self.device = device
        self.owner = owner
        let reported = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0
        size = max(reported, 64)
        buffer = .allocate(capacity: size)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, size, inputReport, Unmanaged.passUnretained(self).toOpaque())
    }

    func detach() {
        IOHIDDeviceRegisterInputReportCallback(device, buffer, size, nil, nil)
    }

    deinit { buffer.deallocate() }
}

// IOKit 回调都在主线程 run loop 上触发；指针以地址形式传入主线程上下文
private nonisolated func deviceMatched(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    let address = UInt(bitPattern: context)
    nonisolated(unsafe) let device = device
    MainActor.assumeIsolated {
        guard let owner = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<RemoteDevice>.fromOpaque(owner).takeUnretainedValue().attach(device)
    }
}

private nonisolated func deviceRemoved(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    let address = UInt(bitPattern: context)
    nonisolated(unsafe) let device = device
    MainActor.assumeIsolated {
        guard let owner = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<RemoteDevice>.fromOpaque(owner).takeUnretainedValue().detach(device)
    }
}

private nonisolated func inputReport(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?,
                                     type: IOHIDReportType, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
    let address = UInt(bitPattern: context)
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        let sink = Unmanaged<ReportSink>.fromOpaque(pointer).takeUnretainedValue()
        sink.owner?.handleReport(reportID: reportID, bytes: bytes)
    }
}
