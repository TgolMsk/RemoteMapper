import Foundation

/// 语音输入设置
public struct VoiceSettings: Codable, Hashable, Sendable {
    /// 识别语言，nil 表示跟随系统
    public var localeIdentifier: String?
    /// 麦克风的 CoreAudio 设备 UID，nil 表示使用系统默认输入
    public var inputDeviceUID: String?
    /// 使用遥控器内置麦克风；不可用时明确报错，不切换到其它麦克风。
    public var usesRemoteMicrophone: Bool
    /// 录音时在屏幕底部显示识别浮窗
    public var showsHUD: Bool

    public init(localeIdentifier: String? = "zh-CN", inputDeviceUID: String? = nil, showsHUD: Bool = true,
                usesRemoteMicrophone: Bool = true) {
        self.localeIdentifier = localeIdentifier
        self.inputDeviceUID = inputDeviceUID
        self.showsHUD = showsHUD
        self.usesRemoteMicrophone = usesRemoteMicrophone
    }

    private enum CodingKeys: String, CodingKey { case localeIdentifier, inputDeviceUID, showsHUD, usesRemoteMicrophone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = VoiceSettings()
        localeIdentifier = c.contains(.localeIdentifier)
            ? try c.decodeIfPresent(String.self, forKey: .localeIdentifier) : defaults.localeIdentifier
        inputDeviceUID = try c.decodeIfPresent(String.self, forKey: .inputDeviceUID)
        usesRemoteMicrophone = try c.decodeIfPresent(Bool.self, forKey: .usesRemoteMicrophone) ?? (inputDeviceUID == nil)
        showsHUD = try c.decodeIfPresent(Bool.self, forKey: .showsHUD) ?? defaults.showsHUD
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(localeIdentifier, forKey: .localeIdentifier)
        try c.encodeIfPresent(inputDeviceUID, forKey: .inputDeviceUID)
        try c.encode(showsHUD, forKey: .showsHUD)
        try c.encode(usesRemoteMicrophone, forKey: .usesRemoteMicrophone)
    }

    public var captureDeviceUID: String? {
        usesRemoteMicrophone ? AudioInputDevices.remoteMicrophoneUID : inputDeviceUID
    }
}
