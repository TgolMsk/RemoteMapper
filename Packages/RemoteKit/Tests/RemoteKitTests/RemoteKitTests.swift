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
