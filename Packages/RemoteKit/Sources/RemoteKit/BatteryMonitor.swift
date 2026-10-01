import CoreBluetooth
import Foundation
import Observation
import os

/// 通过蓝牙标准电池服务（Battery Service 0x180F / Battery Level 0x2A19）读取遥控器电量。
///
/// 遥控器由系统连接，这里用 retrieveConnectedPeripherals 找到它并共享这条连接，不会断开系统的连接。
/// 首次创建 CBCentralManager 时系统会请求蓝牙权限。
@Observable
public final class BatteryMonitor: NSObject {
    public enum Status: Equatable, Sendable {
        case idle
        case unauthorized
        case bluetoothOff
        /// 已连接的蓝牙设备中还没找到遥控器
        case searching
        /// 找到了遥控器，但它没有提供电池服务
        case notSupported
        case reading
        case available
        case failed(String)
    }

    public private(set) var status: Status = .idle {
        didSet { if status != oldValue { Self.log.info("电量读取状态：\(String(describing: self.status), privacy: .public)") } }
    }
    /// 电量百分比 0...100
    public private(set) var level: Int?
    public private(set) var lastUpdate: Date?
    /// 提供电池服务的已连接设备名称，用于诊断匹配问题
    public private(set) var candidates: [String] = []

    /// 遥控器的 HID 产品名（例如序列号 C08KJ2532330），蓝牙外设名称通常与之一致
    @ObservationIgnored public var targetName: String?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var levelCharacteristic: CBCharacteristic?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTimer: Timer?

    private static let log = Logger(subsystem: "com.ws.RemoteMapper", category: "battery")
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    public var isLow: Bool { (level ?? 100) <= 15 }

    public override init() {
        super.init()
    }

    /// 开始读取；遥控器重新连接后再次调用即可
    public func start() {
        guard let central else {
            central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            return
        }
        if central.state == .poweredOn { findRemote() }
    }

    /// 遥控器断开：放弃当前连接，保留最后一次读到的电量直到下次连接
    public func remoteDisconnected() {
        retryTask?.cancel()
        refreshTimer?.invalidate()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        levelCharacteristic = nil
        status = .idle
    }

    /// 主动重新读取一次
    public func refresh() {
        if let peripheral, let levelCharacteristic, peripheral.state == .connected {
            peripheral.readValue(for: levelCharacteristic)
        } else {
            start()
        }
    }

    /// 仅用于界面预览与截图
    public func simulate(level: Int?) {
        self.level = level
        status = level == nil ? .idle : .available
        lastUpdate = level == nil ? nil : Date()
    }

    private func findRemote() {
        guard let central, peripheral == nil else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        candidates = connected.map { $0.name ?? $0.identifier.uuidString }
        Self.log.info("提供电池服务的已连接设备：\(self.candidates.joined(separator: ", "), privacy: .public)，目标：\(self.targetName ?? "-", privacy: .public)")
        let match = connected.first { $0.name == targetName && targetName != nil }
            ?? connected.first { $0.name?.localizedCaseInsensitiveContains("remote") == true }
        guard let match else {
            status = .searching
            scheduleRetry()
            return
        }
        peripheral = match
        match.delegate = self
        status = .reading
        central.connect(match)
    }

    private func scheduleRetry(after seconds: Double = 5) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.peripheral == nil ? self.findRemote() : self.refresh()
        }
    }

    private func update(level value: Int) {
        level = min(max(value, 0), 100)
        Self.log.info("遥控器电量：\(value)%")
        lastUpdate = Date()
        status = .available
    }
}

extension BatteryMonitor: @MainActor CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: findRemote()
        case .unauthorized: status = .unauthorized
        case .poweredOff: status = .bluetoothOff
        case .unsupported: status = .failed("此 Mac 不支持蓝牙低功耗")
        default: break
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // 枚举全部可见服务：电池服务用于读电量，其余仅记录到诊断日志
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        status = .failed(error?.localizedDescription ?? "连接失败")
        scheduleRetry(after: 10)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == self.peripheral else { return }
        self.peripheral = nil
        levelCharacteristic = nil
        refreshTimer?.invalidate()
        // 遥控器休眠会断开 BLE 连接，稍后重新查找
        scheduleRetry(after: 10)
    }
}

extension BatteryMonitor: @MainActor CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        Self.log.info("遥控器对 CoreBluetooth 可见的服务：\(services.map(\.uuid.uuidString).joined(separator: ", "), privacy: .public)")
        for other in services where other.uuid != Self.batteryService {
            peripheral.discoverCharacteristics(nil, for: other)
        }
        guard let service = services.first(where: { $0.uuid == Self.batteryService }) else {
            status = error.map { .failed($0.localizedDescription) } ?? .notSupported
            return
        }
        peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard service.uuid == Self.batteryService else {
            let list = (service.characteristics ?? []).map { "\($0.uuid.uuidString)[\($0.properties.rawValue)]" }
            Self.log.info("服务 \(service.uuid.uuidString, privacy: .public) 的特征：\(list.joined(separator: ", "), privacy: .public)")
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else {
            status = error.map { .failed($0.localizedDescription) } ?? .notSupported
            return
        }
        levelCharacteristic = characteristic
        peripheral.readValue(for: characteristic)
        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
        // 不支持通知时定期重读；支持时也偶尔校准一次
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            status = .failed(error.localizedDescription)
            return
        }
        guard characteristic.uuid == Self.batteryLevel, let byte = characteristic.value?.first else { return }
        update(level: Int(byte))
    }
}
