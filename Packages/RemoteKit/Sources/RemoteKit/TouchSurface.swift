import CoreGraphics
import Foundation
import IOKit
import Observation
import os
import Synchronization

/// 通过私有框架 MultitouchSupport 读取 Siri Remote 触控面的触点。
///
/// 系统把遥控器的触控面注册为多点触控设备（与 Mac 触控板相同的驱动），
/// 因此不需要解析原始 HID 报告。私有接口没有头文件，函数以 dlsym 动态加载，
/// MTTouch 结构按偏移读取（布局沿用社区逆向结果，每个触点 96 字节）。
@Observable
public final class TouchSurface: TouchSource {
    public typealias Status = TouchSourceStatus

    public private(set) var status: Status = .idle {
        didSet { if status != oldValue { Self.log.info("触控面状态：\(String(describing: self.status), privacy: .public)") } }
    }
    private static let log = Logger(subsystem: "com.ws.RemoteMapper", category: "touch")
    /// 当前接触中的触点，供界面实时显示
    public private(set) var contacts: [TouchContact] = []
    /// 触控面尺寸（毫米）
    public private(set) var surfaceSize: CGSize?

    @ObservationIgnored public var onFrame: ((TouchFrame) -> Void)?

    @ObservationIgnored private var deviceList: CFArray?
    @ObservationIgnored private var device: UnsafeMutableRawPointer?
    @ObservationIgnored private var lastPublish: TimeInterval = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    public init() {}

    public func start() { start(retries: 5) }

    /// 查找遥控器的触控面并开始接收触点；遥控器刚连上时触控设备可能稍晚出现，会自动重试几次
    public func start(retries: Int) {
        guard device == nil else { return }
        retryTask?.cancel()
        guard let api = MultitouchAPI.shared else {
            status = .unavailable("无法加载 MultitouchSupport")
            return
        }
        guard let list = api.createList()?.takeRetainedValue() else {
            status = .notFound
            return
        }
        let devices = (0..<CFArrayGetCount(list)).compactMap { CFArrayGetValueAtIndex(list, $0) }
            .map { UnsafeMutableRawPointer(mutating: $0) }
        guard let match = devices.first(where: { Self.isRemote($0, api: api) }) else {
            status = .notFound
            if retries > 0 {
                retryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    self?.start(retries: retries - 1)
                }
            }
            return
        }

        var width: Int32 = 0, height: Int32 = 0
        _ = api.surfaceDimensions?(match, &width, &height)
        if width > 0, height > 0 { surfaceSize = CGSize(width: Double(width) / 100, height: Double(height) / 100) }

        touchRouter.withLock { $0 = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque()) }
        api.registerCallback(match, touchFrameCallback)
        _ = api.start(match, 0)
        deviceList = list
        device = match
        status = .running
    }

    public func stop() {
        retryTask?.cancel()
        if let device, let api = MultitouchAPI.shared {
            api.unregisterCallback(device, touchFrameCallback)
            _ = api.stop(device)
        }
        touchRouter.withLock { $0 = 0 }
        device = nil
        deviceList = nil
        contacts = []
        if status == .running { status = .idle }
    }

    /// 仅用于界面预览与截图
    public func simulate(contacts: [TouchContact], size: CGSize? = CGSize(width: 27.75, height: 27.75)) {
        status = .running
        surfaceSize = size
        self.contacts = contacts
    }

    fileprivate func receive(_ frame: TouchFrame) {
        guard device != nil else { return }
        onFrame?(frame)
        // 界面刷新限制在约 60 Hz；抬起时立即刷新，避免残留触点
        let touching = frame.contacts.filter(\.isTouching)
        if touching.isEmpty || frame.timestamp - lastPublish >= 1.0 / 60 {
            lastPublish = frame.timestamp
            if touching != contacts { contacts = touching }
        }
    }

    private static func isRemote(_ device: UnsafeMutableRawPointer, api: MultitouchAPI) -> Bool {
        guard let service = api.service?(device), service != 0 else { return false }
        func number(_ key: String) -> Int? {
            let value = IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                                        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
            return (value as? NSNumber)?.intValue
        }
        return number("VendorID") == RemoteDevice.vendorID && number("ProductID") == RemoteDevice.productID
    }
}

// MARK: - 私有接口

private typealias MTContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

private nonisolated struct MultitouchAPI: Sendable {
    let createList: @convention(c) () -> Unmanaged<CFArray>?
    let registerCallback: @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
    let unregisterCallback: @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
    let start: @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    let stop: @convention(c) (UnsafeMutableRawPointer) -> Int32
    let service: (@convention(c) (UnsafeMutableRawPointer) -> io_service_t)?
    let surfaceDimensions: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32)?

    static let shared: MultitouchAPI? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
            return nil
        }
        func load<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let createList = load("MTDeviceCreateList", as: (@convention(c) () -> Unmanaged<CFArray>?).self),
              let register = load("MTRegisterContactFrameCallback", as: (@convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void).self),
              let unregister = load("MTUnregisterContactFrameCallback", as: (@convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void).self),
              let start = load("MTDeviceStart", as: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Int32).self),
              let stop = load("MTDeviceStop", as: (@convention(c) (UnsafeMutableRawPointer) -> Int32).self) else {
            return nil
        }
        return MultitouchAPI(
            createList: createList, registerCallback: register, unregisterCallback: unregister, start: start, stop: stop,
            service: load("MTDeviceGetService", as: (@convention(c) (UnsafeMutableRawPointer) -> io_service_t).self),
            surfaceDimensions: load("MTDeviceGetSensorSurfaceDimensions",
                                    as: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32).self))
    }()
}

/// 回调不带上下文指针，用全局变量指向当前的 TouchSurface（同一时间只接一个遥控器）
private nonisolated let touchRouter = Mutex<UInt>(0)

/// MTTouch 中用到的字段偏移
private nonisolated enum TouchLayout {
    static let stride = 96
    static let identifier = 16
    static let state = 20
    static let normalizedX = 32
    static let normalizedY = 36
    static let size = 48
}

/// 在 MultitouchSupport 的内部线程上调用，复制触点后切回主线程
private nonisolated func touchFrameCallback(device: UnsafeMutableRawPointer?, touches: UnsafeMutableRawPointer?,
                                            count: Int32, timestamp: Double, frame: Int32) -> Int32 {
    var contacts: [TouchContact] = []
    if let touches, count > 0 {
        contacts.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let base = UnsafeRawPointer(touches) + index * TouchLayout.stride
            contacts.append(TouchContact(
                id: base.loadUnaligned(fromByteOffset: TouchLayout.identifier, as: Int32.self),
                state: base.loadUnaligned(fromByteOffset: TouchLayout.state, as: Int32.self),
                x: Double(base.loadUnaligned(fromByteOffset: TouchLayout.normalizedX, as: Float.self)),
                y: Double(base.loadUnaligned(fromByteOffset: TouchLayout.normalizedY, as: Float.self)),
                size: Double(base.loadUnaligned(fromByteOffset: TouchLayout.size, as: Float.self))))
        }
    }
    let touchFrame = TouchFrame(contacts: contacts, timestamp: timestamp)
    let address = touchRouter.withLock { $0 }
    guard address != 0 else { return 0 }
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
            Unmanaged<TouchSurface>.fromOpaque(pointer).takeUnretainedValue().receive(touchFrame)
        }
    }
    return 0
}
