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

/// 记录触控鼠标输出的事件，代替真实的 CGEvent
final class RecordingPointerOutput: PointerOutput {
    enum Event: Equatable {
        case move(dx: Double, dy: Double, dragging: MouseButton?)
        case button(MouseButton, down: Bool, clicks: Int)
        case scroll(dx: Double, dy: Double, phase: ScrollPhase)
    }
    var events: [Event] = []
    func move(dx: Double, dy: Double, dragging: MouseButton?) { events.append(.move(dx: dx, dy: dy, dragging: dragging)) }
    func button(_ button: MouseButton, isDown: Bool, clickCount: Int) { events.append(.button(button, down: isDown, clicks: clickCount)) }
    func scroll(dx: Double, dy: Double, phase: ScrollPhase) { events.append(.scroll(dx: dx, dy: dy, phase: phase)) }

    var moves: [(dx: Double, dy: Double, dragging: MouseButton?)] {
        events.compactMap { if case .move(let x, let y, let d) = $0 { (x, y, d) } else { nil } }
    }
    var scrolls: [(dx: Double, dy: Double, phase: ScrollPhase)] {
        events.compactMap { if case .scroll(let x, let y, let p) = $0 { (x, y, p) } else { nil } }
    }
}

@Suite struct TouchPointerTests {
    private func frame(_ x: Double, _ y: Double, at t: TimeInterval, id: Int32 = 1) -> TouchFrame {
        TouchFrame(contacts: [TouchContact(id: id, state: 4, x: x, y: y)], timestamp: t)
    }
    private let lift = { (t: TimeInterval) in TouchFrame(contacts: [], timestamp: t) }

    private func makePointer(tapToClick: Bool = false, clock: ManualClock = ManualClock()) -> (TouchPointer, RecordingPointerOutput) {
        let output = RecordingPointerOutput()
        var time = 100.0
        let pointer = TouchPointer(settings: TouchSettings(mode: .pointer, tapToClick: tapToClick), output: output,
                                   now: { time += 0.1; return time }, clock: clock)
        pointer.doubleClickInterval = 0.5
        return (pointer, output)
    }

    @Test func movesCursorWithFinger() {
        let (pointer, output) = makePointer()
        pointer.handle(frame(0.5, 0.5, at: 0))
        #expect(output.events.isEmpty)
        pointer.handle(frame(0.55, 0.5, at: 0.015))
        pointer.handle(frame(0.55, 0.56, at: 0.03))
        let moves = output.moves
        #expect(moves.count == 2)
        #expect(moves[0].dx > 0 && moves[0].dy == 0)
        // 触控面 y 向上，屏幕 y 向下
        #expect(moves[1].dx == 0 && moves[1].dy < 0)
        #expect(moves.allSatisfy { $0.dragging == nil })
    }

    @Test func fastMovementTravelsFurther() {
        let (slow, slowOut) = makePointer()
        slow.handle(frame(0.5, 0.5, at: 0))
        slow.handle(frame(0.55, 0.5, at: 0.2))
        let (fast, fastOut) = makePointer()
        fast.handle(frame(0.5, 0.5, at: 0))
        fast.handle(frame(0.55, 0.5, at: 0.01))
        #expect(fastOut.moves[0].dx > slowOut.moves[0].dx * 2)
    }

    @Test func slowMovementAccumulatesSubpixels() {
        let (pointer, output) = makePointer()
        pointer.handle(frame(0.5, 0.5, at: 0))
        // 每帧不足一个像素，累积后仍应移动
        for step in 1...20 { pointer.handle(frame(0.5 + Double(step) * 0.0005, 0.5, at: Double(step) * 0.05)) }
        #expect(output.moves.reduce(0) { $0 + $1.dx } >= 5)
    }

    @Test func dragsWhileButtonHeld() {
        let (pointer, output) = makePointer()
        pointer.press(.left)
        pointer.handle(frame(0.5, 0.5, at: 0))
        pointer.handle(frame(0.6, 0.5, at: 0.02))
        pointer.release(.left)
        #expect(output.events.first == .button(.left, down: true, clicks: 1))
        #expect(output.moves.first?.dragging == .left)
        #expect(output.events.last == .button(.left, down: false, clicks: 1))
    }

    @Test func scrollFollowsFinger() {
        let (pointer, output) = makePointer()
        pointer.isScrolling = true
        pointer.handle(frame(0.5, 0.5, at: 0))
        pointer.handle(frame(0.5, 0.6, at: 0.02))
        pointer.handle(frame(0.6, 0.6, at: 0.04))
        #expect(output.moves.isEmpty)
        // 手指上移显示下方内容（负值），右移显示左侧内容（正值）
        #expect(output.scrolls[0].dy < 0 && output.scrolls[0].dx == 0 && output.scrolls[0].phase == .began)
        #expect(output.scrolls[1].dx > 0 && output.scrolls[1].phase == .changed)
    }

    @Test func flickKeepsScrollingWithMomentum() {
        let clock = ManualClock()
        let (pointer, output) = makePointer(clock: clock)
        pointer.isScrolling = true
        pointer.handle(frame(0.5, 0.3, at: 0))
        pointer.handle(frame(0.5, 0.4, at: 0.016))
        pointer.handle(frame(0.5, 0.5, at: 0.032))
        pointer.handle(lift(0.04))
        #expect(output.scrolls.last?.phase == .ended)
        clock.advance(0.5)
        let momentum = output.scrolls.filter { $0.phase == .momentumBegan || $0.phase == .momentum }
        #expect(momentum.first?.phase == .momentumBegan)
        #expect(momentum.count > 5 && momentum.allSatisfy { $0.dy < 0 })
        // 越滑越慢
        #expect(abs(momentum.last!.dy) < abs(momentum.first!.dy))
        clock.advance(5)
        #expect(output.scrolls.last?.phase == .momentumEnded)
        #expect(output.scrolls.filter { $0.phase == .momentumEnded }.count == 1)
    }

    @Test func noMomentumAfterFingerStops() {
        let clock = ManualClock()
        let (pointer, output) = makePointer(clock: clock)
        pointer.isScrolling = true
        pointer.handle(frame(0.5, 0.3, at: 0))
        pointer.handle(frame(0.5, 0.5, at: 0.016))
        pointer.handle(frame(0.5, 0.5, at: 0.2))
        pointer.handle(lift(0.3))
        clock.advance(1)
        #expect(!output.scrolls.contains { $0.phase == .momentumBegan })
    }

    @Test func touchingAgainStopsMomentum() {
        let clock = ManualClock()
        let (pointer, output) = makePointer(clock: clock)
        pointer.isScrolling = true
        pointer.handle(frame(0.5, 0.3, at: 0))
        pointer.handle(frame(0.5, 0.5, at: 0.016))
        pointer.handle(lift(0.02))
        clock.advance(0.1)
        pointer.handle(frame(0.5, 0.5, at: 0.2, id: 2))
        #expect(output.scrolls.last?.phase == .momentumEnded)
        let count = output.scrolls.count
        clock.advance(1)
        #expect(output.scrolls.count == count)
    }

    @Test func togglingScrollNotifiesAndEndsGesture() {
        let (pointer, output) = makePointer()
        var states: [Bool] = []
        pointer.onScrollingChange = { states.append($0) }
        pointer.isScrolling = true
        pointer.handle(frame(0.5, 0.5, at: 0))
        pointer.handle(frame(0.5, 0.6, at: 0.02))
        pointer.isScrolling = false
        #expect(states == [true, false])
        #expect(output.scrolls.last?.phase == .ended)
        // 切回光标后移动的是光标
        pointer.handle(frame(0.6, 0.6, at: 0.04))
        #expect(output.moves.count == 1)
    }

    @Test func tapClicksOnlyWhenEnabled() {
        let (pointer, output) = makePointer(tapToClick: true)
        pointer.handle(frame(0.5, 0.5, at: 0))
        pointer.handle(frame(0.505, 0.5, at: 0.05))
        pointer.handle(lift(0.1))
        #expect(output.events.filter { if case .button = $0 { true } else { false } }.count == 2)

        let (off, offOut) = makePointer(tapToClick: false)
        off.handle(frame(0.5, 0.5, at: 0))
        off.handle(lift(0.1))
        #expect(offOut.events.isEmpty)

        // 划动后抬起不是轻点
        let (moved, movedOut) = makePointer(tapToClick: true)
        moved.handle(frame(0.3, 0.5, at: 0))
        moved.handle(frame(0.5, 0.5, at: 0.05))
        moved.handle(lift(0.1))
        #expect(!movedOut.events.contains { if case .button = $0 { true } else { false } })
    }

    @Test func freezesBrieflyAfterPhysicalPress() {
        let (pointer, output) = makePointer(tapToClick: true)
        pointer.handle(frame(0.5, 0.5, at: 0))
        pointer.noteButtonPress()
        pointer.handle(frame(0.52, 0.5, at: 0.02))
        pointer.handle(frame(0.54, 0.5, at: 0.1))
        #expect(output.moves.isEmpty)
        pointer.handle(frame(0.6, 0.5, at: 0.3))
        #expect(output.moves.count == 1)
        // 按过实体键的这次触摸不算轻点
        pointer.handle(lift(0.32))
        #expect(!output.events.contains { if case .button = $0 { true } else { false } })
    }

    @Test func quickSecondClickIsDoubleClick() {
        let (pointer, output) = makePointer()
        pointer.click(.left)
        pointer.click(.left)
        #expect(output.events == [.button(.left, down: true, clicks: 1), .button(.left, down: false, clicks: 1),
                                  .button(.left, down: true, clicks: 2), .button(.left, down: false, clicks: 2)])
    }

    @Test func resetReleasesHeldButtons() {
        let (pointer, output) = makePointer()
        pointer.press(.right)
        pointer.isScrolling = true
        pointer.reset()
        #expect(output.events.last == .button(.right, down: false, clicks: 1))
        #expect(!pointer.isScrolling && pointer.heldButtons.isEmpty)
    }

    @Test func holdScrollThroughRunner() {
        let (pointer, _) = makePointer()
        let runner = ActionRunner()
        runner.pointer = pointer
        runner.begin(.pointerScroll, for: .playPause)
        #expect(pointer.isScrolling)
        runner.end(for: .playPause)
        #expect(!pointer.isScrolling)
    }

    @Test func toggleTouchModeFlipsConfig() {
        let url = FileManager.default.temporaryDirectory.appending(path: "remote-\(UUID().uuidString).json")
        let store = ConfigStore(fileURL: url, persists: false, initial: .default)
        let engine = RemoteEngine(store: store, pointerOutput: RecordingPointerOutput())
        engine.runner.onToggleTouchMode()
        #expect(store.config.touch.mode == .pointer)
        engine.runner.onToggleTouchMode()
        #expect(store.config.touch.mode == .gestures)
    }

    @Test func mouseActionsAndSettingsAreReadable() throws {
        let json = String(data: try JSONEncoder().encode(Action.mouseButton(.right)), encoding: .utf8)!
        #expect(json.contains("\"type\":\"mouseButton\"") && json.contains("\"button\":\"right\""))
        #expect(try JSONDecoder().decode(Action.self, from: Data(#"{"type":"mouseButton"}"#.utf8)) == .mouseButton(.left))
        #expect(try JSONDecoder().decode(Action.self, from: Data(#"{"type":"pointerScroll"}"#.utf8)) == .pointerScroll)
        #expect(try JSONDecoder().decode(Action.self, from: Data(#"{"type":"toggleTouchMode"}"#.utf8)) == .toggleTouchMode)

        let old = try JSONDecoder().decode(TouchSettings.self, from: Data(#"{"isEnabled":true}"#.utf8))
        #expect(old.mode == .gestures && old.pointerSpeed == 1 && !old.tapToClick)
        let pointer = try JSONDecoder().decode(TouchSettings.self, from: Data(#"{"mode":"pointer","pointerSpeed":2}"#.utf8))
        #expect(pointer.mode == .pointer && pointer.pointerSpeed == 2)
        #expect(Preset.all.filter { $0.group == .mouse && $0.action.kind == .mouseButton }.allSatisfy { $0.preferredGesture == .hold })
    }
}

@Suite struct PointerProfileTests {
    @Test func defaultConfigHasPointerProfile() throws {
        let config = RemoteConfig.default
        let pointer = try #require(config.pointerProfile)
        #expect(!pointer.isGlobal)
        // 侧键单击为确定、双击切换滚轮；按下触控板为左键（可拖动）；返回键为右键
        #expect(pointer.mapping(for: .siri)?.tap?.action == .mouseButton(.left))
        #expect(pointer.mapping(for: .siri)?.tap?.displayTitle == "确定")
        #expect(pointer.mapping(for: .siri)?.doubleTap?.action == .pointerScroll)
        #expect(pointer.mapping(for: .select)?.hold?.action == .mouseButton(.left))
        // 触控板四周按下也是左键，不再继承方向键
        for edge in [RemoteButton.up, .down, .left, .right] {
            #expect(pointer.mapping(for: edge)?.hold?.action == .mouseButton(.left))
        }
        #expect(pointer.mapping(for: .back)?.tap?.action == .mouseButton(.right))
        #expect(pointer.mapping(for: .mute) == nil)
        #expect(config.globalProfile.isGlobal && config.profiles.filter(\.isGlobal).count == 1)
    }

    @Test func pointerProfileWinsOnlyInPointerMode() {
        var config = RemoteConfig.default
        var global = config.globalProfile
        global.mappings[.siri] = ButtonMapping(longPress: Preset.find("dot.toggleCall")!.bound)
        config.globalProfile = global

        // 手势模式：Siri 长按仍是呼叫 dot
        #expect(config.resolve(.siri, frontmost: nil)?.mapping.longPress?.action == .dotCall(.toggle))
        config.touch.mode = .pointer
        #expect(config.resolve(.siri, frontmost: nil)?.mapping.tap?.action == .mouseButton(.left))
        #expect(config.resolve(.siri, frontmost: nil)?.profile.isPointerMode == true)
        // 鼠标模式优先于 App 专属配置：终端里的「确认 = 发送」被左键覆盖
        #expect(config.resolve(.select, frontmost: KnownApp.iTerm)?.mapping.hold?.action == .mouseButton(.left))
        // 鼠标模式配置里没设置的键沿用原来的映射
        #expect(config.resolve(.tv, frontmost: nil)?.profile.isGlobal == true)
        #expect(config.resolve(.playPause, frontmost: KnownApp.iTerm)?.profile.bundleIDs == [KnownApp.iTerm, KnownApp.terminal])
        // 关闭触控时鼠标模式不生效
        config.touch.isEnabled = false
        #expect(config.resolve(.siri, frontmost: nil)?.mapping.longPress?.action == .dotCall(.toggle))
    }

    @Test func migrationAddsPointerProfileOnce() throws {
        let json = #"{"version": 2, "profiles": [{"name": "全局", "mappings": {}}]}"#
        var config = try JSONDecoder().decode(RemoteConfig.self, from: Data(json.utf8))
        #expect(config.pointerProfile == nil)
        let migrated = config.migrate()
        #expect(migrated)
        #expect(config.profiles.filter(\.isPointerMode).count == 1)
        let migratedAgain = config.migrate()
        #expect(!migratedAgain)
        #expect(config.profiles.filter(\.isPointerMode).count == 1)

        let encoded = String(data: try JSONEncoder().encode(config), encoding: .utf8)!
        #expect(encoded.contains("\"pointerMode\":true"))
        let decoded = try JSONDecoder().decode(RemoteConfig.self, from: Data(encoded.utf8))
        #expect(decoded.pointerProfile?.name == "鼠标模式")
    }

    @Test func pointerActionsRunWhileSettingsFocused() {
        #expect(Action.mouseButton(.left).runsWhileSettingsFocused)
        #expect(Action.pointerScroll.runsWhileSettingsFocused)
        #expect(!Action.keystroke(.returnKey).runsWhileSettingsFocused)
    }
}

@Suite struct RingScrollTests {
    /// 外圈上某个角度的点，半径 0.45（触控面边长为 1）
    private func ring(_ degrees: Double, radius: Double = 0.45) -> (Double, Double) {
        let a = degrees * .pi / 180
        return (0.5 + radius * cos(a), 0.5 + radius * sin(a))
    }

    private func run(_ points: [(Double, Double)], settings: TouchSettings = TouchSettings(mode: .pointer))
        -> RecordingPointerOutput {
        let output = RecordingPointerOutput()
        let pointer = TouchPointer(settings: settings, output: output, clock: ManualClock())
        for (index, point) in points.enumerated() {
            pointer.handle(TouchFrame(contacts: [TouchContact(id: 1, state: 4, x: point.0, y: point.1)], timestamp: Double(index) * 0.016))
        }
        pointer.handle(TouchFrame(contacts: [], timestamp: Double(points.count) * 0.016))
        return output
    }

    @Test func clockwiseOnRingScrollsDown() {
        // 从上方起手（右侧属于滚动区）；y 向上时角度减小即顺时针
        let output = run(stride(from: 90.0, through: 0, by: -6).map { ring($0) })
        #expect(output.moves.isEmpty)
        let deltas = output.scrolls.filter { $0.phase == .began || $0.phase == .changed }
        #expect(!deltas.isEmpty && deltas.allSatisfy { $0.dy < 0 && $0.dx == 0 })
        // 转盘停手即停：结束后没有惯性
        #expect(output.scrolls.last?.phase == .ended)
        #expect(!output.scrolls.contains { $0.phase == .momentumBegan })
        // 转过 90° 约滚动 ringGain × π/2 像素
        #expect(abs(deltas.reduce(0) { $0 + $1.dy } + 190 * .pi / 2) < 40)
    }

    @Test func counterclockwiseOnRingScrollsUp() {
        let output = run(stride(from: 90.0, through: 180, by: 6).map { ring($0) })
        #expect(output.moves.isEmpty)
        #expect(output.scrolls.filter { $0.phase == .changed }.allSatisfy { $0.dy > 0 })
    }

    @Test func swipingInwardFromRingMovesPointer() {
        // 从左侧外圈往中间划：径向为主，是移动光标
        let output = run(stride(from: 0.05, through: 0.4, by: 0.02).map { ($0, 0.5) })
        #expect(output.scrolls.isEmpty)
        #expect(output.moves.allSatisfy { $0.dx > 0 })
        // 判定前积累的位移会补发，总位移不丢
        #expect(output.moves.reduce(0) { $0 + $1.dx } > 100)
    }

    @Test func centerTouchMovesWithoutDelay() {
        let output = run([(0.5, 0.5), (0.52, 0.5)])
        #expect(output.moves.count == 1)
    }

    @Test func ringScrollCanBeDisabled() {
        let output = run(stride(from: 90.0, through: 0, by: -6).map { ring($0) },
                         settings: TouchSettings(mode: .pointer, ringScroll: false))
        #expect(output.scrolls.isEmpty && !output.moves.isEmpty)
    }

    @Test func narrowerRingLeavesMoreRoomForPointer() {
        // 半径 0.36 的圆周：外圈宽 0.18 时在外圈内，宽 0.12 时属于中间区域
        let path = stride(from: 90.0, through: 0, by: -6).map { ring($0, radius: 0.36) }
        #expect(!run(path, settings: TouchSettings(mode: .pointer, ringWidth: 0.18)).scrolls.isEmpty)
        let narrow = run(path, settings: TouchSettings(mode: .pointer, ringWidth: 0.12))
        #expect(narrow.scrolls.isEmpty && !narrow.moves.isEmpty)
    }

    @Test func ringWidthDefaultsForOldConfigs() throws {
        let settings = try JSONDecoder().decode(TouchSettings.self, from: Data(#"{"mode":"pointer"}"#.utf8))
        #expect(settings.ringScroll && settings.ringWidth == 0.12)
        #expect(settings.sideScroll && settings.sideScrollWidth == 0.33)
    }

    // MARK: 右侧滚动区

    @Test func rightStripScrollFollowsFinger() {
        // 在右侧往上滑：内容跟着手指往上走，显示下方内容（负值）
        let output = run(stride(from: 0.3, through: 0.7, by: 0.03).map { (0.85, $0) })
        #expect(output.moves.isEmpty)
        let deltas = output.scrolls.filter { $0.phase == .began || $0.phase == .changed }
        #expect(!deltas.isEmpty && deltas.allSatisfy { $0.dy < 0 && $0.dx == 0 })
        // 判定前积累的位移也补发了：总滚动约等于整面滚轮的滚动量
        #expect(abs(deltas.reduce(0) { $0 + $1.dy } + 0.39 * 900) < 40)
        #expect(output.scrolls.contains { $0.phase == .ended })
    }

    @Test func rightStripDownScrollsUp() {
        let output = run(stride(from: 0.7, through: 0.3, by: -0.03).map { (0.85, $0) })
        #expect(output.scrolls.filter { $0.phase == .changed }.allSatisfy { $0.dy > 0 })
    }

    @Test func horizontalFromRightStripMovesPointer() {
        let output = run(stride(from: 0.85, through: 0.5, by: -0.03).map { ($0, 0.5) })
        #expect(output.scrolls.isEmpty && output.moves.allSatisfy { $0.dx < 0 })
    }

    @Test func leftSideMovesPointerVertically() {
        // 左侧不是滚动区：上下滑动移动光标
        let output = run(stride(from: 0.4, through: 0.6, by: 0.02).map { (0.3, $0) })
        #expect(output.scrolls.isEmpty && output.moves.allSatisfy { $0.dy < 0 })
    }

    @Test func rightStripFlickHasMomentum() {
        let clock = ManualClock()
        let output = RecordingPointerOutput()
        let pointer = TouchPointer(settings: TouchSettings(mode: .pointer), output: output, clock: clock)
        for (index, y) in [0.3, 0.38, 0.46, 0.54].enumerated() {
            pointer.handle(TouchFrame(contacts: [TouchContact(id: 1, state: 4, x: 0.85, y: y)], timestamp: Double(index) * 0.016))
        }
        pointer.handle(TouchFrame(contacts: [], timestamp: 0.07))
        clock.advance(0.3)
        #expect(output.scrolls.contains { $0.phase == .momentumBegan })
    }

    @Test func sideScrollCanBeDisabledOrNarrowed() {
        let path = stride(from: 0.3, through: 0.7, by: 0.03).map { (0.75, $0) }
        // 宽 33% 时 x = 0.75 在滚动区内
        #expect(!run(path).scrolls.isEmpty)
        // 宽 20% 时 x = 0.75 不在滚动区内
        #expect(run(path, settings: TouchSettings(mode: .pointer, sideScrollWidth: 0.2)).scrolls.isEmpty)
        #expect(run(path, settings: TouchSettings(mode: .pointer, sideScroll: false)).scrolls.isEmpty)
    }
}
