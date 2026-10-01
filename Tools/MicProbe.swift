// MicProbe.swift
// 抓取 Siri Remote 全部 HID 接口的原始报告，用于确认按住 Siri 键说话时麦克风接口是否有音频数据。
// 运行：swift Tools/MicProbe.swift [秒数] [输出文件]
// 输出文件每行一条报告：时间(秒) 接口 报告ID 长度 十六进制数据

import Foundation
import IOKit.hid

let duration = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 60 : 60
let outputPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "mic-capture.txt"
FileManager.default.createFile(atPath: outputPath, contents: nil)
let output = FileHandle(forWritingAtPath: outputPath)!
let start = Date()

final class Sink {
    let label: String
    let buffer: UnsafeMutablePointer<UInt8>
    let size: Int
    var count = 0
    var bytes = 0
    var sizes: [Int: Int] = [:]
    var lastSecondPrinted = -1
    var countThisSecond = 0

    init(label: String, size: Int) {
        self.label = label
        self.size = size
        buffer = .allocate(capacity: size)
    }
}

var sinks: [Sink] = []
var lastButtons: UInt16 = 0

func label(page: Int, usage: Int) -> String {
    switch (page, usage) {
    case (0x0C, 0x01): "buttons"
    case (0x0C, 0x04): "mic"
    case (0x0D, _): "touch"
    case (0xFF00, 0x0B): "devmgmt"
    case (0x20, _): "sensor"
    default: String(format: "%X:%X", page, usage)
    }
}

let callback: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
    let sink = Unmanaged<Sink>.fromOpaque(context!).takeUnretainedValue()
    let t = Date().timeIntervalSince(start)
    let data = UnsafeBufferPointer(start: report, count: length)
    sink.count += 1
    sink.bytes += length
    sink.sizes[length, default: 0] += 1
    let hex = data.map { String(format: "%02x", $0) }.joined()
    output.write("\(String(format: "%.4f", t)) \(sink.label) \(String(format: "%02x", reportID)) \(length) \(hex)\n".data(using: .utf8)!)

    if sink.label == "buttons", reportID == 0xFB, length >= 3 {
        let bits = UInt16(data[1]) | UInt16(data[2]) << 8
        if (bits ^ lastButtons) & (1 << 5) != 0 {
            print(String(format: "%7.2fs  Siri 键%@", t, bits & (1 << 5) != 0 ? "按下" : "松开"))
        }
        lastButtons = bits
    }
    if sink.label == "mic" {
        let second = Int(t)
        sink.countThisSecond += 1
        if second != sink.lastSecondPrinted {
            print(String(format: "%7.2fs  麦克风接口开始收到数据（报告 ID %02x，%d 字节）", t, reportID, length))
            sink.lastSecondPrinted = second
            sink.countThisSecond = 0
        }
    }
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x004C, kIOHIDProductIDKey: 0x0315] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
    let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
    let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? 0
    let size = max((IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0, 256)
    let sink = Sink(label: label(page: page, usage: usage), size: size)
    sinks.append(sink)
    IOHIDDeviceRegisterInputReportCallback(device, sink.buffer, sink.size, callback, Unmanaged.passUnretained(sink).toOpaque())
}, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard result == kIOReturnSuccess else {
    print(String(format: "IOHIDManagerOpen 失败 0x%08x", result))
    exit(1)
}

print("开始抓取 \(Int(duration)) 秒：请按住 Siri 键说几句话，松开后再重复一两次。")
CFRunLoopRunInMode(.defaultMode, duration, false)
try? output.close()

print("\n==== 汇总 ====")
for sink in sinks.sorted(by: { $0.label < $1.label }) {
    let sizes = sink.sizes.sorted { $0.key < $1.key }.map { "\($0.key)B×\($0.value)" }.joined(separator: " ")
    print("\(sink.label.padding(toLength: 8, withPad: " ", startingAt: 0)) 报告 \(sink.count) 条，共 \(sink.bytes) 字节  \(sizes)")
}
print("原始数据已写入 \(outputPath)")
