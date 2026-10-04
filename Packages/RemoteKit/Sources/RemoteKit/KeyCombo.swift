import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// 修饰键集合，JSON 中编码为可读的字符串数组，例如 ["control", "shift"]。
public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)

    /// Apple 规范的显示顺序：⌃ ⌥ ⇧ ⌘
    static let ordered: [(Modifiers, name: String, glyph: String)] = [
        (.function, "fn", "fn"),
        (.control, "control", "⌃"),
        (.option, "option", "⌥"),
        (.shift, "shift", "⇧"),
        (.command, "command", "⌘"),
    ]

    public var glyphs: [String] { Self.ordered.filter { contains($0.0) }.map(\.glyph) }

    public var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    public init(from decoder: Decoder) throws {
        let names = try decoder.singleValueContainer().decode([String].self)
        var result: Modifiers = []
        for name in names {
            guard let entry = Self.ordered.first(where: { $0.name == name }) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: L10n.format("未知修饰键 %@", name)))
            }
            result.insert(entry.0)
        }
        self = result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.ordered.filter { contains($0.0) }.map(\.name))
    }
}

/// 一个按键组合。keyCode 为 macOS 虚拟键码（kVK_*）。
public struct KeyCombo: Hashable, Sendable, Codable {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init?(key name: String, modifiers: Modifiers = []) {
        guard let code = KeyNames.code(for: name) else { return nil }
        self.init(keyCode: code, modifiers: modifiers)
    }

    /// 是否是单独的修饰键（例如只按 ⌥）
    public var isModifierKey: Bool { KeyNames.modifierFlag(for: keyCode) != nil }

    /// 显示用的键帽文字，例如 ["⇧", "⇥"]
    public var keycaps: [String] {
        if isModifierKey { return [KeyNames.glyph(for: keyCode)] }
        return modifiers.glyphs + [KeyNames.glyph(for: keyCode)]
    }

    public var displayString: String { keycaps.joined() }

    // MARK: Codable：{"key": "tab", "modifiers": ["shift"]}，无名称的键退回数字 keyCode

    private enum CodingKeys: String, CodingKey { case key, keyCode, modifiers }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modifiers = try c.decodeIfPresent(Modifiers.self, forKey: .modifiers) ?? []
        if let name = try c.decodeIfPresent(String.self, forKey: .key) {
            guard let code = KeyNames.code(for: name) else {
                throw DecodingError.dataCorruptedError(forKey: .key, in: c, debugDescription: L10n.format("未知按键 %@", name))
            }
            keyCode = code
        } else {
            keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let name = KeyNames.name(for: keyCode) {
            try c.encode(name, forKey: .key)
        } else {
            try c.encode(keyCode, forKey: .keyCode)
        }
        if !modifiers.isEmpty { try c.encode(modifiers, forKey: .modifiers) }
    }
}

public extension KeyCombo {
    static let returnKey = KeyCombo(keyCode: UInt16(kVK_Return))
    static let escape = KeyCombo(keyCode: UInt16(kVK_Escape))
    static let space = KeyCombo(keyCode: UInt16(kVK_Space))
    static let tab = KeyCombo(keyCode: UInt16(kVK_Tab))
    static let upArrow = KeyCombo(keyCode: UInt16(kVK_UpArrow))
    static let downArrow = KeyCombo(keyCode: UInt16(kVK_DownArrow))
    static let leftArrow = KeyCombo(keyCode: UInt16(kVK_LeftArrow))
    static let rightArrow = KeyCombo(keyCode: UInt16(kVK_RightArrow))
    static let option = KeyCombo(keyCode: UInt16(kVK_Option))
}

/// 虚拟键码与可读名称、显示符号之间的对照表。
public enum KeyNames {
    private static let table: [(code: Int, name: String, glyph: String)] = {
        var t: [(Int, String, String)] = [
            (kVK_Return, "return", "↩"), (kVK_Tab, "tab", "⇥"), (kVK_Space, "space", "Space"),
            (kVK_Delete, "delete", "⌫"), (kVK_ForwardDelete, "forwardDelete", "⌦"), (kVK_Escape, "escape", "esc"),
            (kVK_UpArrow, "up", "↑"), (kVK_DownArrow, "down", "↓"), (kVK_LeftArrow, "left", "←"), (kVK_RightArrow, "right", "→"),
            (kVK_Home, "home", "↖"), (kVK_End, "end", "↘"), (kVK_PageUp, "pageUp", "⇞"), (kVK_PageDown, "pageDown", "⇟"),
            (kVK_ANSI_Minus, "minus", "-"), (kVK_ANSI_Equal, "equal", "="), (kVK_ANSI_LeftBracket, "leftBracket", "["),
            (kVK_ANSI_RightBracket, "rightBracket", "]"), (kVK_ANSI_Semicolon, "semicolon", ";"), (kVK_ANSI_Quote, "quote", "'"),
            (kVK_ANSI_Comma, "comma", ","), (kVK_ANSI_Period, "period", "."), (kVK_ANSI_Slash, "slash", "/"),
            (kVK_ANSI_Backslash, "backslash", "\\"), (kVK_ANSI_Grave, "grave", "`"),
            (kVK_Command, "command", "⌘"), (kVK_RightCommand, "rightCommand", "右⌘"),
            (kVK_Option, "option", "⌥"), (kVK_RightOption, "rightOption", "右⌥"),
            (kVK_Control, "control", "⌃"), (kVK_RightControl, "rightControl", "右⌃"),
            (kVK_Shift, "shift", "⇧"), (kVK_RightShift, "rightShift", "右⇧"),
            (kVK_Function, "fn", "fn"), (kVK_CapsLock, "capsLock", "⇪"),
        ]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "a"), (kVK_ANSI_B, "b"), (kVK_ANSI_C, "c"), (kVK_ANSI_D, "d"), (kVK_ANSI_E, "e"),
            (kVK_ANSI_F, "f"), (kVK_ANSI_G, "g"), (kVK_ANSI_H, "h"), (kVK_ANSI_I, "i"), (kVK_ANSI_J, "j"),
            (kVK_ANSI_K, "k"), (kVK_ANSI_L, "l"), (kVK_ANSI_M, "m"), (kVK_ANSI_N, "n"), (kVK_ANSI_O, "o"),
            (kVK_ANSI_P, "p"), (kVK_ANSI_Q, "q"), (kVK_ANSI_R, "r"), (kVK_ANSI_S, "s"), (kVK_ANSI_T, "t"),
            (kVK_ANSI_U, "u"), (kVK_ANSI_V, "v"), (kVK_ANSI_W, "w"), (kVK_ANSI_X, "x"), (kVK_ANSI_Y, "y"),
            (kVK_ANSI_Z, "z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"),
            (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
        ]
        t += letters.map { ($0.0, $0.1, $0.1.uppercased()) }
        let fkeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        t += fkeys.enumerated().map { ($0.element, "f\($0.offset + 1)", "F\($0.offset + 1)") }
        return t
    }()

    public static func code(for name: String) -> UInt16? {
        table.first { $0.name == name }.map { UInt16($0.code) }
    }

    public static func name(for code: UInt16) -> String? {
        table.first { $0.code == Int(code) }?.name
    }

    public static func glyph(for code: UInt16) -> String {
        table.first { $0.code == Int(code) }.map { L10n.text($0.glyph) } ?? "#\(code)"
    }

    /// 修饰键本身的键码对应的事件标志位
    public static func modifierFlag(for code: UInt16) -> CGEventFlags? {
        switch Int(code) {
        case kVK_Command, kVK_RightCommand: .maskCommand
        case kVK_Option, kVK_RightOption: .maskAlternate
        case kVK_Control, kVK_RightControl: .maskControl
        case kVK_Shift, kVK_RightShift: .maskShift
        case kVK_Function: .maskSecondaryFn
        case kVK_CapsLock: .maskAlphaShift
        default: nil
        }
    }
}
