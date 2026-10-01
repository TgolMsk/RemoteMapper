import ApplicationServices
import Foundation
import Testing
@testable import RemoteKit

/// 手动推进时间的时钟
final class ManualClock: GestureClock {
    final class Item: GestureTimer {
        let fireAt: TimeInterval
        let action: @MainActor () -> Void
        var cancelled = false
        init(fireAt: TimeInterval, action: @escaping @MainActor () -> Void) {
            self.fireAt = fireAt
            self.action = action
        }
        func cancel() { cancelled = true }
    }

    private(set) var now: TimeInterval = 0
    private var items: [Item] = []

    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> GestureTimer {
        let item = Item(fireAt: now + interval, action: action)
        items.append(item)
        return item
    }

    func advance(_ seconds: TimeInterval) {
        let target = now + seconds
        while let next = items.filter({ !$0.cancelled && $0.fireAt <= target }).min(by: { $0.fireAt < $1.fireAt }) {
            now = next.fireAt
            next.cancelled = true
            next.action()
        }
        now = target
    }
}

@Suite struct ReportTests {
    @Test func decodesButtonBitmap() {
        // bit 8（播放/暂停）与 bit 3（触控板按下）
        let pressed = RemoteReport.pressedButtons(reportID: 0xFB, bytes: [0xFB, 0b0000_1000, 0b0000_0001])
        #expect(pressed == [.select, .playPause])
    }

    @Test func acceptsPayloadWithoutReportID() {
        #expect(RemoteReport.pressedButtons(reportID: 0xFB, bytes: [0x01, 0x10]) == [.tv, .left])
    }

    @Test func ignoresOtherReports() {
        #expect(RemoteReport.pressedButtons(reportID: 0x01, bytes: [0x01, 0xFF, 0xFF]) == nil)
        #expect(RemoteReport.pressedButtons(reportID: 0xFB, bytes: [0xFB]) == nil)
    }

    @Test func bitOrderMatchesDescriptor() {
        #expect(RemoteButton.tv.bit == 0)
        #expect(RemoteButton.siri.bit == 5)
        #expect(RemoteButton.left.bit == 12)
    }
}

@Suite struct GestureTests {
    let clock = ManualClock()

    func engine(_ gestures: Set<RemoteGesture>, repeat: Bool = false) -> (GestureEngine, () -> [GestureOutput]) {
        var outputs: [GestureOutput] = []
        let engine = GestureEngine(clock: clock) { _ in .init(gestures: gestures, repeatWhileHeld: `repeat`) }
        engine.onOutput = { outputs.append($0) }
        return (engine, { outputs })
    }

    @Test func tapOnlyFiresImmediatelyOnPress() {
        let (engine, outputs) = engine([.tap])
        engine.handle(.select, isDown: true)
        #expect(outputs() == [.fire(.select, .tap)])
        engine.handle(.select, isDown: false)
        #expect(outputs().count == 1)
    }

    @Test func repeatsWhileHeld() {
        let (engine, outputs) = engine([.tap], repeat: true)
        engine.handle(.up, isDown: true)
        clock.advance(0.38 + 0.07 * 3)
        engine.handle(.up, isDown: false)
        clock.advance(1)
        #expect(outputs().count == 5)
    }

    @Test func holdBeginsAndEnds() {
        let (engine, outputs) = engine([.hold, .tap])
        engine.handle(.siri, isDown: true)
        clock.advance(2)
        engine.handle(.siri, isDown: false)
        #expect(outputs() == [.begin(.siri), .end(.siri)])
    }

    @Test func longPressSuppressesTap() {
        let (engine, outputs) = engine([.tap, .longPress])
        engine.handle(.tv, isDown: true)
        clock.advance(0.5)
        engine.handle(.tv, isDown: false)
        clock.advance(1)
        #expect(outputs() == [.fire(.tv, .longPress)])
    }

    @Test func shortPressWithLongPressBoundFiresTapOnRelease() {
        let (engine, outputs) = engine([.tap, .longPress])
        engine.handle(.tv, isDown: true)
        clock.advance(0.1)
        #expect(outputs().isEmpty)
        engine.handle(.tv, isDown: false)
        #expect(outputs() == [.fire(.tv, .tap)])
    }

    @Test func doubleTap() {
        let (engine, outputs) = engine([.tap, .doubleTap])
        engine.handle(.tv, isDown: true)
        engine.handle(.tv, isDown: false)
        clock.advance(0.1)
        engine.handle(.tv, isDown: true)
        engine.handle(.tv, isDown: false)
        clock.advance(1)
        #expect(outputs() == [.fire(.tv, .doubleTap)])
    }

    @Test func singleTapWaitsForDoubleTapWindow() {
        let (engine, outputs) = engine([.tap, .doubleTap])
        engine.handle(.tv, isDown: true)
        engine.handle(.tv, isDown: false)
        clock.advance(0.2)
        #expect(outputs().isEmpty)
        clock.advance(0.2)
        #expect(outputs() == [.fire(.tv, .tap)])
    }

    @Test func resetEndsActiveHolds() {
        let (engine, outputs) = engine([.hold])
        engine.handle(.siri, isDown: true)
        engine.reset()
        #expect(outputs() == [.begin(.siri), .end(.siri)])
    }

    @Test func unboundButtonProducesNothing() {
        let (engine, outputs) = engine([])
        engine.handle(.mute, isDown: true)
        engine.handle(.mute, isDown: false)
        clock.advance(1)
        #expect(outputs().isEmpty)
    }
}

@Suite struct ConfigTests {
    @Test func roundTripsThroughJSON() throws {
        let config = RemoteConfig.default
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RemoteConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test func encodesReadableKeys() throws {
        let action = Action.keystroke(KeyCombo(key: "tab", modifiers: .shift)!)
        let json = String(data: try JSONEncoder().encode(action), encoding: .utf8)!
        #expect(json.contains("\"key\":\"tab\""))
        #expect(json.contains("\"modifiers\":[\"shift\"]"))
        #expect(json.contains("\"type\":\"keystroke\""))
    }

    @Test func decodesHandWrittenConfig() throws {
        let json = """
        {"profiles": [{"name": "全局", "mappings": {
            "siri": {"hold": {"action": {"type": "holdKey", "key": "space"}, "title": "说话"}},
            "playPause": {"tap": {"action": {"type": "shell", "command": "say hi"}}}
        }}]}
        """
        let config = try JSONDecoder().decode(RemoteConfig.self, from: Data(json.utf8))
        #expect(config.isEnabled)
        #expect(config.globalProfile.mappings[.siri]?.hold?.action == .holdKey(.space))
        #expect(config.globalProfile.mappings[.playPause]?.tap?.action == .shell("say hi"))
    }

    @Test func appProfileOverridesGlobalPerButton() {
        let config = RemoteConfig.default
        let terminal = KnownApp.iTerm
        #expect(config.resolve(.siri, frontmost: terminal)?.profile.name == "终端")
        #expect(config.resolve(.up, frontmost: terminal)?.profile.isGlobal == true)
        #expect(config.resolve(.siri, frontmost: "com.example.other")?.profile.isGlobal == true)
        #expect(config.resolve(.mute, frontmost: terminal) == nil)
    }

    @Test func alwaysHasGlobalProfile() throws {
        let config = try JSONDecoder().decode(RemoteConfig.self, from: Data("{}".utf8))
        #expect(config.profiles.count == 1)
        #expect(config.globalProfile.isGlobal)
    }

    @Test func keycapsUseAppleModifierOrder() {
        let combo = KeyCombo(key: "k", modifiers: [.command, .shift, .control])!
        #expect(combo.keycaps == ["⌃", "⇧", "⌘", "K"])
        #expect(KeyCombo.option.keycaps == ["⌥"])
    }
}

@Suite struct TouchTests {
    /// 生成一串触点帧：沿给定点序列移动，最后抬起
    func frames(_ points: [(Double, Double)], duration: TimeInterval = 0.3) -> [TouchFrame] {
        var result: [TouchFrame] = []
        for (index, point) in points.enumerated() {
            let time = duration * Double(index) / Double(max(points.count - 1, 1))
            result.append(TouchFrame(contacts: [TouchContact(id: 1, state: 4, x: point.0, y: point.1)], timestamp: time))
        }
        result.append(TouchFrame(contacts: [], timestamp: duration + 0.01))
        return result
    }

    func line(from a: (Double, Double), to b: (Double, Double), steps: Int = 12) -> [(Double, Double)] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
        }
    }

    func arc(degrees: [Double], radius: Double = 0.4) -> [(Double, Double)] {
        degrees.map { (0.5 + radius * cos($0 * .pi / 180), 0.5 + radius * sin($0 * .pi / 180)) }
    }

    func recognize(_ frames: [TouchFrame], suppressAt: Int? = nil) -> [TouchGesture] {
        let recognizer = TouchGestureRecognizer()
        var output: [TouchGesture] = []
        recognizer.onGesture = { output.append($0) }
        for (index, frame) in frames.enumerated() {
            if index == suppressAt { recognizer.suppressCurrentTouch() }
            recognizer.handle(frame)
        }
        return output
    }

    @Test func swipesInFourDirections() {
        #expect(recognize(frames(line(from: (0.5, 0.2), to: (0.5, 0.8)))) == [.swipeUp])
        #expect(recognize(frames(line(from: (0.5, 0.8), to: (0.5, 0.2)))) == [.swipeDown])
        #expect(recognize(frames(line(from: (0.2, 0.5), to: (0.8, 0.5)))) == [.swipeRight])
        #expect(recognize(frames(line(from: (0.8, 0.5), to: (0.2, 0.5)))) == [.swipeLeft])
    }

    @Test func straightSwipeAlongEdgeIsNotRotation() {
        // 贴着右边缘竖直上滑，转角接近 100°，但轨迹是直线
        #expect(recognize(frames(line(from: (0.85, 0.1), to: (0.85, 0.9)))) == [.swipeUp])
    }

    @Test func shortOrDiagonalMovementIsIgnored() {
        #expect(recognize(frames(line(from: (0.5, 0.5), to: (0.6, 0.55)))).isEmpty)
        #expect(recognize(frames(line(from: (0.2, 0.2), to: (0.7, 0.7)))).isEmpty)
    }

    @Test func slowSwipeIsIgnored() {
        #expect(recognize(frames(line(from: (0.5, 0.2), to: (0.5, 0.8)), duration: 2)).isEmpty)
    }

    @Test func rotationEmitsTicksAndNoSwipe() {
        // 从 90° 顺时针转到 -90°（转过 180°），默认每 30° 一次
        let clockwise = recognize(frames(arc(degrees: stride(from: 90.0, through: -90, by: -10).map { $0 }), duration: 0.8))
        #expect(clockwise == Array(repeating: .rotateClockwise, count: 6))
        let counter = recognize(frames(arc(degrees: stride(from: 0.0, through: 120, by: 10).map { $0 }), duration: 0.8))
        #expect(counter == Array(repeating: .rotateCounterclockwise, count: 4))
    }

    @Test func physicalPressSuppressesGesture() {
        #expect(recognize(frames(line(from: (0.5, 0.2), to: (0.5, 0.8))), suppressAt: 3).isEmpty)
    }
}

@Suite struct TouchConfigTests {
    @Test func resolvesTouchPerApp() {
        let config = RemoteConfig.default
        #expect(config.resolve(.swipeLeft, frontmost: KnownApp.iTerm)?.profile.name == "终端")
        #expect(config.resolve(.swipeUp, frontmost: KnownApp.iTerm)?.profile.isGlobal == true)
        #expect(config.resolve(.rotateClockwise, frontmost: nil)?.action.action == .scroll(.down, lines: 3))
    }

    @Test func migratesVersionOneConfig() throws {
        let json = """
        {"version": 1, "profiles": [
            {"name": "全局", "mappings": {}},
            {"name": "终端", "bundleIDs": ["com.googlecode.iterm2"], "mappings": {}}
        ]}
        """
        var config = try JSONDecoder().decode(RemoteConfig.self, from: Data(json.utf8))
        let migrated = config.migrate()
        #expect(migrated)
        #expect(config.version == RemoteConfig.currentVersion)
        #expect(config.globalProfile.touchMappings.count == 6)
        #expect(config.profiles[1].touchMappings[.swipeRight]?.presetID == "system.nextTab")
        let migratedAgain = config.migrate()
        #expect(!migratedAgain)
    }

    @Test func scrollActionIsReadable() throws {
        let json = String(data: try JSONEncoder().encode(Action.scroll(.down, lines: 3)), encoding: .utf8)!
        #expect(json.contains("\"direction\":\"down\""))
        #expect(try JSONDecoder().decode(Action.self, from: Data(json.utf8)) == .scroll(.down, lines: 3))
    }
}

@Suite struct VoiceTests {
    @Test func dictationActionIsReadable() throws {
        let json = String(data: try JSONEncoder().encode(Action.dictation(submit: true)), encoding: .utf8)!
        #expect(json.contains("\"type\":\"dictation\""))
        #expect(try JSONDecoder().decode(Action.self, from: Data(json.utf8)) == .dictation(submit: true))
        let plain = try JSONDecoder().decode(Action.self, from: Data(#"{"type":"dictation"}"#.utf8))
        #expect(plain == .dictation(submit: false))
    }

    @Test func siriHoldDictatesByDefault() {
        let config = RemoteConfig.default
        #expect(config.resolve(.siri, frontmost: nil)?.mapping.hold?.action == .dictation(submit: false))
        #expect(config.resolve(.siri, frontmost: KnownApp.iTerm)?.mapping.hold?.presetID == "voice.dictation")
    }

    @Test func voiceSettingsDefaultsAndFollowSystem() throws {
        let missing = try JSONDecoder().decode(RemoteConfig.self, from: Data("{}".utf8))
        #expect(missing.voice.localeIdentifier == "zh-CN")
        #expect(missing.voice.showsHUD)
        #expect(missing.voice.usesRemoteMicrophone)
        #expect(missing.voice.captureDeviceUID == AudioInputDevices.remoteMicrophoneUID)

        var config = RemoteConfig.default
        config.voice.localeIdentifier = nil
        let decoded = try JSONDecoder().decode(RemoteConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.voice.localeIdentifier == nil)
    }

    @Test func preservesExplicitMicrophoneFromOlderConfig() throws {
        let older = try JSONDecoder().decode(VoiceSettings.self, from: Data(#"{"inputDeviceUID":"USB-Mic"}"#.utf8))
        #expect(!older.usesRemoteMicrophone)
        #expect(older.captureDeviceUID == "USB-Mic")
        let system = VoiceSettings(usesRemoteMicrophone: false)
        #expect(system.captureDeviceUID == nil)
        #expect(try JSONDecoder().decode(VoiceSettings.self, from: JSONEncoder().encode(system)) == system)
    }

    @Test func missingRemoteNeverFallsBackToAnotherMicrophone() {
        let usb = AudioInputDevice(id: 123, uid: "USB-Mic", name: "USB")
        #expect(throws: DictationError.self) {
            try AudioInputDevices.resolve(uid: AudioInputDevices.remoteMicrophoneUID, devices: [usb], defaultInput: usb)
        }
        #expect(throws: DictationError.self) {
            try AudioInputDevices.resolve(uid: "Disconnected", devices: [usb], defaultInput: usb)
        }
    }

    @Test func selectsExactRemoteInput() throws {
        let remote = AudioInputDevice(id: 123, uid: AudioInputDevices.remoteMicrophoneUID, name: "Siri Remote Mic")
        let usb = AudioInputDevice(id: 124, uid: "USB-Mic", name: "USB")
        #expect(try AudioInputDevices.resolve(uid: remote.uid, devices: [usb, remote], defaultInput: usb) == remote)
        #expect(try AudioInputDevices.resolve(uid: nil, devices: [usb, remote], defaultInput: usb) == usb)
    }
}

@Suite struct DotCallTests {
    @Test func dotCallActionIsReadable() throws {
        let json = String(data: try JSONEncoder().encode(Action.dotCall(.hangUp)), encoding: .utf8)!
        #expect(json.contains("\"type\":\"dotCall\""))
        #expect(json.contains("\"operation\":\"hangUp\""))
        #expect(try JSONDecoder().decode(Action.self, from: Data(json.utf8)) == .dotCall(.hangUp))
        let plain = try JSONDecoder().decode(Action.self, from: Data(#"{"type":"dotCall"}"#.utf8))
        #expect(plain == .dotCall(.toggle))
    }

    @Test func presetsCoverCallAndMute() {
        #expect(Preset.find("dot.toggleCall")?.action == .dotCall(.toggle))
        #expect(Preset.find("dot.hangUp")?.action == .dotCall(.hangUp))
        #expect(Preset.find("dot.toggleMute")?.action == .dotCall(.toggleMute))
        #expect(Preset.all.filter { $0.group == .dot }.allSatisfy { $0.action.kind == .dotCall })
    }

    @Test func matchesButtonLabelsInBothLanguages() {
        // 中文界面下 Start call / Hang up 未翻译，静音按钮是中文
        #expect(DotCall.matches(["Start call", "Start call"], DotCall.startLabels))
        #expect(DotCall.matches(["拨打电话"], DotCall.startLabels))
        #expect(DotCall.matches(["Hang up"], DotCall.hangUpLabels))
        #expect(DotCall.matches(["将麦克风静音"], DotCall.muteLabels))
        #expect(DotCall.matches(["取消麦克风静音"], DotCall.muteLabels))
        #expect(!DotCall.matches(["Start call"], DotCall.hangUpLabels))
        #expect(!DotCall.matches(["开始新的语音聊天"], DotCall.startLabels))
    }

    @Test func recognizesSidebarRow() {
        #expect(DotCall.isSidebarRow(["嗨宝"], dotName: "嗨宝"))
        #expect(DotCall.isSidebarRow(["嗨宝 Call in progress"], dotName: "嗨宝"))
        #expect(!DotCall.isSidebarRow(["嗨宝的周报"], dotName: "嗨宝"))
        #expect(DotCall.isCallInProgress(["嗨宝 Call in progress"]))
        #expect(!DotCall.isCallInProgress(["嗨宝"]))
    }

    private func node(_ label: String, enabled: Bool = true) -> AXNode {
        AXNode(element: AXUIElementCreateApplication(getpid()), labels: [label, label], isEnabled: enabled)
    }

    private func pressed(_ decision: DotCall.Decision) -> String? {
        if case .press(let node) = decision { return node.labels.first }
        return nil
    }

    @Test func toggleHangsUpWhenInCallOtherwiseCalls() {
        let inCall = [node("嗨宝 Call in progress"), node("Start call", enabled: false), node("将麦克风静音"), node("Hang up")]
        #expect(pressed(DotCall.decide(.toggle, inCall, dotName: "嗨宝")) == "Hang up")
        let idle = [node("嗨宝"), node("Start call")]
        #expect(pressed(DotCall.decide(.toggle, idle, dotName: "嗨宝")) == "Start call")
        // 侧边栏显示通话中，但当前不在 dot 页面：要切过去，不能点呼叫
        let elsewhere = [node("嗨宝 Call in progress"), node("新聊天")]
        if case .missing = DotCall.decide(.toggle, elsewhere, dotName: "嗨宝") {} else { Issue.record("应切到 dot 页面") }
    }

    @Test func startDoesNothingDuringCall() {
        if case .alreadyDone = DotCall.decide(.start, [node("Hang up")], dotName: nil) {} else { Issue.record("通话中不应再呼叫") }
        // 呼叫按钮不可用时不点
        if case .missing = DotCall.decide(.start, [node("Start call", enabled: false)], dotName: nil) {} else {
            Issue.record("不可用的按钮不应点击")
        }
    }

    @Test func hangUpWithoutCallReturnsQuickly() {
        // 侧边栏能看到 dot 且没在通话：直接返回，不必切到 dot 页面等待
        if case .noCall = DotCall.decide(.hangUp, [node("嗨宝"), node("新聊天")], dotName: "嗨宝") {} else { Issue.record("应判定为没有通话") }
        if case .noCall = DotCall.decide(.toggleMute, [node("嗨宝")], dotName: "嗨宝") {} else { Issue.record("应判定为没有通话") }
        // 不知道 dot 名字时只能切过去看
        if case .missing = DotCall.decide(.hangUp, [node("嗨宝")], dotName: nil) {} else { Issue.record("应切到 dot 页面") }
        #expect(pressed(DotCall.decide(.toggleMute, [node("取消麦克风静音")], dotName: "嗨宝")) == "取消麦克风静音")
    }

    @Test func readsPrimaryDotNameFromChatGPTState() {
        let state = #"""
        {"electron-persisted-atom-state": {
          "primary-aeon-selection-v1": {"response": {"selection": {"thread_id": "t1"}}},
          "cloud-aeon-sidebar-cache-v1": {"profilesByThreadId": {
            "t0": {"display_name": "别的 dot"},
            "t1": {"display_name": "嗨宝"}
          }}
        }}
        """#
        #expect(DotCall.primaryDotName(fromGlobalState: Data(state.utf8)) == "嗨宝")
        #expect(DotCall.primaryDotName(fromGlobalState: Data("{}".utf8)) == nil)
    }
}
