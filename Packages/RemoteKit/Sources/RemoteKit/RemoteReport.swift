import Foundation

/// Siri Remote 按键报告解析。
public enum RemoteReport {
    public static let buttonReportID: UInt32 = 0xFB

    /// 解析按键报告，返回当前处于按下状态的按钮；不是按键报告时返回 nil。
    /// IOKit 回调给出的数据首字节通常就是报告 ID，其后 2 字节为按钮位图。
    public static func pressedButtons(reportID: UInt32, bytes: [UInt8]) -> Set<RemoteButton>? {
        guard reportID == buttonReportID else { return nil }
        let payload = bytes.first == UInt8(buttonReportID) ? bytes.dropFirst() : bytes[...]
        guard payload.count >= 2 else { return nil }
        let start = payload.startIndex
        let bits = UInt16(payload[start]) | UInt16(payload[start + 1]) << 8
        return Set(RemoteButton.allCases.filter { bits & (1 << $0.bit) != 0 })
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
