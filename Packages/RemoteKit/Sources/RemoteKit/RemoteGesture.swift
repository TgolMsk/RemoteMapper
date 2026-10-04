import Foundation

public enum RemoteGesture: String, CaseIterable, Codable, Sendable, Identifiable {
    case tap, doubleTap, longPress, hold

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tap: L10n.text("单击")
        case .doubleTap: L10n.text("双击")
        case .longPress: L10n.text("长按")
        case .hold: L10n.text("按住")
        }
    }

    public var detail: String {
        switch self {
        case .tap: L10n.text("按下即触发")
        case .doubleTap: L10n.text("快速连按两次")
        case .longPress: L10n.text("按住超过设定时长后触发一次")
        case .hold: L10n.text("按下开始、松开结束，适合按住说话")
        }
    }

    public var symbol: String {
        switch self {
        case .tap: "hand.tap"
        case .doubleTap: "hand.tap.fill"
        case .longPress: "timer"
        case .hold: "hand.raised.fingers.spread"
        }
    }
}

/// 一个按钮在四种手势上的绑定。
public struct ButtonMapping: Codable, Hashable, Sendable {
    public var tap: BoundAction?
    public var doubleTap: BoundAction?
    public var longPress: BoundAction?
    public var hold: BoundAction?
    /// 仅在只绑定「单击」时生效：按住不放时按键盘重复速率连续触发
    public var repeatWhileHeld: Bool

    public init(tap: BoundAction? = nil, doubleTap: BoundAction? = nil, longPress: BoundAction? = nil,
                hold: BoundAction? = nil, repeatWhileHeld: Bool = false) {
        self.tap = tap
        self.doubleTap = doubleTap
        self.longPress = longPress
        self.hold = hold
        self.repeatWhileHeld = repeatWhileHeld
    }

    public subscript(gesture: RemoteGesture) -> BoundAction? {
        get {
            switch gesture {
            case .tap: tap
            case .doubleTap: doubleTap
            case .longPress: longPress
            case .hold: hold
            }
        }
        set {
            switch gesture {
            case .tap: tap = newValue
            case .doubleTap: doubleTap = newValue
            case .longPress: longPress = newValue
            case .hold: hold = newValue
            }
        }
    }

    public var boundGestures: Set<RemoteGesture> { Set(RemoteGesture.allCases.filter { self[$0] != nil }) }
    public var isEmpty: Bool { boundGestures.isEmpty }

    private enum CodingKeys: String, CodingKey { case tap, doubleTap, longPress, hold, repeatWhileHeld }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tap = try c.decodeIfPresent(BoundAction.self, forKey: .tap)
        doubleTap = try c.decodeIfPresent(BoundAction.self, forKey: .doubleTap)
        longPress = try c.decodeIfPresent(BoundAction.self, forKey: .longPress)
        hold = try c.decodeIfPresent(BoundAction.self, forKey: .hold)
        repeatWhileHeld = try c.decodeIfPresent(Bool.self, forKey: .repeatWhileHeld) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(tap, forKey: .tap)
        try c.encodeIfPresent(doubleTap, forKey: .doubleTap)
        try c.encodeIfPresent(longPress, forKey: .longPress)
        try c.encodeIfPresent(hold, forKey: .hold)
        if repeatWhileHeld { try c.encode(true, forKey: .repeatWhileHeld) }
    }
}
