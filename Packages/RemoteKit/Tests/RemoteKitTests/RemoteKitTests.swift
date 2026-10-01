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
