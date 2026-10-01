// RemoteProbe.swift
// 监听 Siri Remote (VID 0x004C / PID 0x0315) 的原始 HID 报告，用于摸清按键与触控板的数据格式。
// 运行：swift RemoteProbe.swift [秒数]   不带参数则一直运行，Ctrl-C 退出。

import Foundation
import IOKit.hid

let vendorID = 0x004C
let productID = 0x0315

// 按键接口（Consumer Control）报告 ID 0xFB 中 13 个 1-bit 字段，顺序取自报告描述符：
// 0C:60 0C:E9 0C:EA 0C:80 0C:30 0C:04 01:86 0C:E2 0C:CD 0C:42 0C:45 0C:43 0C:44
let buttonNames = ["TV/控制中心", "音量+", "音量-", "触控板按下", "电源", "Siri",
                   "返回(<)", "静音", "播放/暂停", "上", "右", "下", "左"]

func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

func timestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
}

final class Interface {
    let page: Int
    let usage: Int
    let label: String
    let buffer: UnsafeMutablePointer<UInt8>
    let size: Int
    var lastButtons: UInt16 = 0
    var lastPrint = Date.distantPast

    init(device: IOHIDDevice) {
        page = intProperty(device, kIOHIDPrimaryUsagePageKey)
        usage = intProperty(device, kIOHIDPrimaryUsageKey)
        switch (page, usage) {
        case (0x0C, 0x01): label = "按键"
        case (0x0C, 0x04): label = "麦克风"
        case (0x0D, _): label = "触控板"
        case (0x20, _): label = "传感器"
        case (0xFF00, _): label = "厂商私有"
        default: label = "未知"
        }
        size = max(intProperty(device, kIOHIDMaxInputReportSizeKey), 64)
        buffer = .allocate(capacity: size)
    }

    func handle(reportID: UInt32, bytes: [UInt8]) {
        if page == 0x0C && usage == 0x01 && reportID == 0xFB {
            // 回调给出的数据首字节通常是报告 ID，去掉后是 2 字节按钮位图
            let payload = bytes.first == 0xFB ? Array(bytes.dropFirst()) : bytes
            guard payload.count >= 2 else { return }
            let bits = UInt16(payload[0]) | UInt16(payload[1]) << 8
            let changed = bits ^ lastButtons
            for i in buttonNames.indices where changed & (1 << i) != 0 {
                let state = bits & (1 << i) != 0 ? "按下" : "松开"
                print("\(timestamp()) [按键] bit\(i) \(buttonNames[i]) \(state)   raw=\(hex(bytes))")
            }
            lastButtons = bits
            return
        }
        // 触控板/传感器约 8ms 一帧，限频输出避免刷屏
        let now = Date()
        guard now.timeIntervalSince(lastPrint) > 0.2 else { return }
        lastPrint = now
        print("\(timestamp()) [\(label)] id=0x\(String(reportID, radix: 16)) len=\(bytes.count) \(hex(bytes.prefix(24)))…")
    }
}

var interfaces: [Interface] = []

let reportCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
    guard let context else { return }
    let iface = Unmanaged<Interface>.fromOpaque(context).takeUnretainedValue()
    iface.handle(reportID: reportID, bytes: Array(UnsafeBufferPointer(start: report, count: length)))
}

let matchingCallback: IOHIDDeviceCallback = { _, _, _, device in
    let iface = Interface(device: device)
    interfaces.append(iface)
    IOHIDDeviceRegisterInputReportCallback(device, iface.buffer, iface.size, reportCallback,
                                           Unmanaged.passUnretained(iface).toOpaque())
    print("已连接接口：\(iface.label)  (page=0x\(String(iface.page, radix: 16)) usage=0x\(String(iface.usage, radix: 16)))")
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, matchingCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if result != kIOReturnSuccess {
    print(String(format: "IOHIDManagerOpen 失败：0x%08x", result))
    if result == kIOReturnNotPermitted {
        print("缺少「输入监控」权限：系统设置 → 隐私与安全性 → 输入监控，勾选当前终端 App 后重试。")
    }
    exit(1)
}

print("开始监听 Siri Remote，按遥控器按键或触摸触控板……")
if let seconds = CommandLine.arguments.dropFirst().first.flatMap(Double.init) {
    CFRunLoopRunInMode(.defaultMode, seconds, false)
} else {
    CFRunLoopRun()
}
