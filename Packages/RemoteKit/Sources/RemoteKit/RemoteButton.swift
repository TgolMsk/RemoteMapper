import Foundation

/// Siri Remote（VID 0x004C / PID 0x0315）按键接口报告 0xFB 中的 13 个按钮。
/// 声明顺序即报告位图中的位序号，取自设备的 HID 报告描述符。
public enum RemoteButton: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
    case tv, volumeUp, volumeDown, select, power, siri, back, mute, playPause, up, right, down, left

    public var id: String { rawValue }

    /// 在报告位图中的位序号
    public var bit: Int { Self.allCases.firstIndex(of: self)! }

    public var displayName: String {
        switch self {
        case .tv: "TV / 控制中心"
        case .volumeUp: "音量 +"
        case .volumeDown: "音量 −"
        case .select: "触控板按下"
        case .power: "电源"
        case .siri: "Siri"
        case .back: "返回"
        case .mute: "静音"
        case .playPause: "播放 / 暂停"
        case .up: "方向 · 上"
        case .right: "方向 · 右"
        case .down: "方向 · 下"
        case .left: "方向 · 左"
        }
    }

    public var shortName: String {
        switch self {
        case .tv: "TV"
        case .volumeUp: "音量+"
        case .volumeDown: "音量−"
        case .select: "按下"
        case .power: "电源"
        case .siri: "Siri"
        case .back: "返回"
        case .mute: "静音"
        case .playPause: "播放"
        case .up: "上"
        case .right: "右"
        case .down: "下"
        case .left: "左"
        }
    }

    public var symbol: String {
        switch self {
        case .tv: "tv"
        case .volumeUp: "plus"
        case .volumeDown: "minus"
        case .select: "circle.circle"
        case .power: "power"
        case .siri: "mic.fill"
        case .back: "chevron.left"
        case .mute: "speaker.slash.fill"
        case .playPause: "playpause.fill"
        case .up: "arrow.up"
        case .right: "arrow.right"
        case .down: "arrow.down"
        case .left: "arrow.left"
        }
    }

    /// 报告描述符中的 Usage（页:用途）
    public var hidUsage: String {
        switch self {
        case .tv: "0C:60"
        case .volumeUp: "0C:E9"
        case .volumeDown: "0C:EA"
        case .select: "0C:80"
        case .power: "0C:30"
        case .siri: "0C:04"
        case .back: "01:86"
        case .mute: "0C:E2"
        case .playPause: "0C:CD"
        case .up: "0C:42"
        case .right: "0C:45"
        case .down: "0C:43"
        case .left: "0C:44"
        }
    }

    public var isDirectional: Bool {
        switch self {
        case .up, .right, .down, .left: true
        default: false
        }
    }

    /// macOS 会把这些键当作系统媒体键处理，映射后需要拦截系统默认行为
    public var isSystemMediaKey: Bool {
        switch self {
        case .volumeUp, .volumeDown, .mute, .playPause: true
        default: false
        }
    }
}
