import Foundation

/// 触控面上识别出的手势。
public enum TouchGesture: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
    case swipeUp, swipeDown, swipeLeft, swipeRight, rotateClockwise, rotateCounterclockwise

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .swipeUp: "上滑"
        case .swipeDown: "下滑"
        case .swipeLeft: "左滑"
        case .swipeRight: "右滑"
        case .rotateClockwise: "顺时针转动"
        case .rotateCounterclockwise: "逆时针转动"
        }
    }

    public var detail: String {
        switch self {
        case .swipeUp, .swipeDown, .swipeLeft, .swipeRight: "在触控板上快速\(displayName)后抬起"
        case .rotateClockwise: "沿外圈顺时针画圈，每转过设定角度触发一次"
        case .rotateCounterclockwise: "沿外圈逆时针画圈，每转过设定角度触发一次"
        }
    }

    public var symbol: String {
        switch self {
        case .swipeUp: "arrow.up"
        case .swipeDown: "arrow.down"
        case .swipeLeft: "arrow.left"
        case .swipeRight: "arrow.right"
        case .rotateClockwise: "arrow.clockwise"
        case .rotateCounterclockwise: "arrow.counterclockwise"
        }
    }

    public var isRotation: Bool { self == .rotateClockwise || self == .rotateCounterclockwise }
}

/// 一个触点。坐标归一化到 0...1，x 从左到右，y 从下到上（与 Mac 触控板一致）。
public nonisolated struct TouchContact: Equatable, Sendable {
    public var id: Int32
    /// MultitouchSupport 的触点状态：3 接触开始、4 接触中、5 抬起中，其余为悬停或离开
    public var state: Int32
    public var x: Double
    public var y: Double
    public var size: Double

    public init(id: Int32, state: Int32, x: Double, y: Double, size: Double = 1) {
        self.id = id
        self.state = state
        self.x = x
        self.y = y
        self.size = size
    }

    public var isTouching: Bool { state == 3 || state == 4 }
}

public nonisolated struct TouchFrame: Sendable {
    public var contacts: [TouchContact]
    public var timestamp: TimeInterval

    public init(contacts: [TouchContact], timestamp: TimeInterval) {
        self.contacts = contacts
        self.timestamp = timestamp
    }
}

/// 触控相关设置
public struct TouchSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// 滑动的最小距离，占触控面边长的比例
    public var swipeDistance: Double
    /// 转动时每转过多少度触发一次
    public var rotationStep: Double

    public init(isEnabled: Bool = true, swipeDistance: Double = 0.30, rotationStep: Double = 30) {
        self.isEnabled = isEnabled
        self.swipeDistance = swipeDistance
        self.rotationStep = rotationStep
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, swipeDistance, rotationStep }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TouchSettings()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        swipeDistance = try c.decodeIfPresent(Double.self, forKey: .swipeDistance) ?? defaults.swipeDistance
        rotationStep = try c.decodeIfPresent(Double.self, forKey: .rotationStep) ?? defaults.rotationStep
    }
}
