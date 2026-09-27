import XCTest
@testable import OverSlayCore

final class MacroTests: XCTestCase {
    private let ctrl = KeyAction(KeyBinding(keyCode: 59))
    private let x = KeyAction(KeyBinding(keyCode: 7))

    func testSequentialHoldThenTapHasReleaseGap() {
        let clock = TestScheduler(); let sink = MacroTestSink()
        let runner = MacroRunner(sink: sink, scheduler: clock)
        XCTAssertTrue(runner.start(.init(steps: [.hold(ctrl, milliseconds: 3000, during: []), .tap(x, milliseconds: 33)])))
        clock.advance(by: 3)
        XCTAssertEqual(sink.events, ["down:59", "up:59"])
        clock.advance(by: 0.032)
        XCTAssertEqual(sink.events.count, 2)
        clock.advance(by: 0.002)
        XCTAssertEqual(sink.events.last, "down:7")
        clock.advance(by: 1)
        XCTAssertFalse(runner.isRunning)
        XCTAssertEqual(sink.events.last, "up:7")
    }

    func testNestedChildReleasesBeforeParentAtSameDeadline() {
        let clock = TestScheduler(); let sink = MacroTestSink()
        let runner = MacroRunner(sink: sink, scheduler: clock)
        runner.start(.init(steps: [.hold(ctrl, milliseconds: 3000, during: [
            .init(offsetMilliseconds: 1000, action: x, durationMilliseconds: 2000)
        ])]))
        clock.advance(by: 1)
        XCTAssertEqual(sink.events, ["down:59", "down:7"])
        clock.advance(by: 2)
        XCTAssertEqual(sink.events, ["down:59", "down:7", "up:7", "up:59"])
        XCTAssertFalse(runner.isRunning)
    }

    func testExplicitWaitReplacesAutomaticGap() {
        let clock = TestScheduler(); let sink = MacroTestSink()
        let runner = MacroRunner(sink: sink, scheduler: clock)
        runner.start(.init(steps: [.tap(ctrl, milliseconds: 100), .wait(milliseconds: 1000), .tap(x, milliseconds: 33)]))
        clock.advance(by: 1.099)
        XCTAssertEqual(sink.events.last, "up:59")
        clock.advance(by: 0.002)
        XCTAssertEqual(sink.events.last, "down:7")
    }

    func testCancellationRemovesChildrenAndDoesNotAffectNewRun() {
        let clock = TestScheduler(); let sink = MacroTestSink()
        let runner = MacroRunner(sink: sink, scheduler: clock)
        runner.start(.init(steps: [.hold(ctrl, milliseconds: 3000, during: [.init(offsetMilliseconds: 1000, action: x)])]))
        runner.cancel(); runner.cancel()
        runner.start(.init(steps: [.wait(milliseconds: 2000)]))
        clock.advance(by: 1.5)
        XCTAssertTrue(runner.isRunning)
        XCTAssertEqual(sink.events, ["down:59", "up:59"])
        clock.advance(by: 1)
        XCTAssertFalse(runner.isRunning)
    }

    func testDurationsStartAfterDeliveryAcknowledgementAndStaleCallbackIgnored() {
        let clock = TestScheduler(); let sink = MacroTestSink(); sink.deferPress = true
        let runner = MacroRunner(sink: sink, scheduler: clock)
        runner.start(.init(steps: [.tap(x, milliseconds: 100)]))
        clock.advance(by: 5)
        XCTAssertTrue(runner.isRunning)
        XCTAssertEqual(runner.progress, 1)
        sink.ack?(); sink.ack = nil
        clock.advance(by: 0.05)
        XCTAssertEqual(runner.progress, 0.5, accuracy: 0.001)
        clock.advance(by: 0.051)
        XCTAssertFalse(runner.isRunning)
        runner.start(.init(steps: [.tap(x, milliseconds: 100)]))
        let stale = sink.ack
        runner.cancel()
        runner.start(.init(steps: [.wait(milliseconds: 2000)]))
        stale?()
        clock.advance(by: 0.5)
        XCTAssertTrue(runner.isRunning)
    }

    func testBackendFailureStopsSequenceAndReleasesOwnedInput() {
        let clock = TestScheduler(); let sink = MacroTestSink()
        let runner = MacroRunner(sink: sink, scheduler: clock)
        sink.error = .inputConflict
        runner.start(.init(steps: [.tap(x, milliseconds: 33), .text("no", intervalMilliseconds: 33)]))
        clock.advance(by: 10)
        XCTAssertFalse(runner.isRunning)
        XCTAssertEqual(runner.lastError, .inputConflict)
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testTextUsesGraphemesAndCancellationStopsRemainingText() {
        let clock = TestScheduler(); let sink = MacroTestSink()
        let runner = MacroRunner(sink: sink, scheduler: clock)
        runner.start(.init(steps: [.text("я👩‍💻e\u{301}", intervalMilliseconds: 100)]))
        XCTAssertEqual(sink.events, ["text:я"])
        clock.advance(by: 0.1)
        XCTAssertEqual(sink.events.last, "text:👩‍💻")
        runner.cancel(); clock.advance(by: 10)
        XCTAssertEqual(sink.events.count, 2)
    }

    func testGlobalLimitsAndInvalidNumericValues() throws {
        for value in ["nan", "inf", "-1", "1e300", "3601", ""] {
            XCTAssertNil(MacroDefinition.milliseconds(value))
        }
        XCTAssertEqual(MacroDefinition.milliseconds("0,033"), 33)
        XCTAssertEqual(MacroDefinition.milliseconds("0", allowZero: true), 0)
        XCTAssertThrowsError(try MacroDefinition(steps: [.text(String(repeating: "a", count: 3000), intervalMilliseconds: 1), .text(String(repeating: "b", count: 2000), intervalMilliseconds: 1)]).validated())
        let children = (0..<64).map { TimedMacroTap(offsetMilliseconds: $0 * 100, action: x) }
        XCTAssertThrowsError(try MacroDefinition(steps: [
            .hold(ctrl, milliseconds: 10000, during: children), .hold(ctrl, milliseconds: 10000, during: children)
        ]).validated())
        XCTAssertThrowsError(try MacroDefinition(steps: [.wait(milliseconds: Int.max)]).validated())
    }

    func testInvalidKeysOverlapAndSequentialActionsAreRejected() throws {
        for action in [KeyAction(bindings: []), KeyAction(KeyBinding(keyCode: 500)),
                       KeyAction(bindings: [x.bindings[0], x.bindings[0]]),
                       KeyAction(x.bindings[0], combinationMode: .sequential)] {
            XCTAssertThrowsError(try MacroDefinition(steps: [.tap(action, milliseconds: 33)]).validated())
        }
        XCTAssertThrowsError(try MacroDefinition(steps: [.hold(ctrl, milliseconds: 1000, during: [.init(offsetMilliseconds: 0, action: ctrl)])]).validated())
        XCTAssertThrowsError(try MacroDefinition(steps: [.hold(ctrl, milliseconds: 1000, during: [
            .init(offsetMilliseconds: 0, action: x), .init(offsetMilliseconds: 40, action: x)
        ])]).validated())
        XCTAssertNoThrow(try MacroDefinition(steps: [.hold(ctrl, milliseconds: 1000, during: [
            .init(offsetMilliseconds: 100, action: x), .init(offsetMilliseconds: 0, action: x)
        ])]).validated())
    }

    func testProfileRoundTripAndAmbiguousActionRejected() throws {
        let macro = MacroDefinition(steps: [.tap(x, milliseconds: 33)])
        var widget = WidgetConfig(geometry: .init(x: 0, y: 0, width: 60, height: 60), label: "Макрос", action: .init(bindings: []), macro: macro)
        let profile = try Profile(widgets: [widget]).validated()
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile)), profile)
        widget.action = x
        XCTAssertThrowsError(try Profile(widgets: [widget]).validated())
    }

    func testDelayedChildAcknowledgementAbortsAndReleasesParent() {
        let clock = TestScheduler(); let sink = MacroTestSink()
        let runner = MacroRunner(sink: sink, scheduler: clock)
        runner.start(.init(steps: [.hold(ctrl, milliseconds: 1000, during: [
            .init(offsetMilliseconds: 500, action: x, durationMilliseconds: 300)
        ])]))
        sink.deferPress = true
        clock.advance(by: 0.9)
        sink.ack?()
        XCTAssertEqual(runner.lastError, .timingOverrun)
        XCTAssertFalse(runner.isRunning)
        XCTAssertEqual(sink.events.suffix(2), ["up:7", "up:59"])
        XCTAssertTrue(sink.owners.isEmpty)
    }

    func testSecondStartCannotReplaceRunningMacro() {
        let clock = TestScheduler(); let sink = MacroTestSink()
        let runner = MacroRunner(sink: sink, scheduler: clock)
        XCTAssertTrue(runner.start(.init(steps: [.wait(milliseconds: 1000)])))
        XCTAssertFalse(runner.start(.init(steps: [.tap(x, milliseconds: 33)])))
        clock.advance(by: 1)
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testChordAppliesAllModifiersBeforePrimaryRegardlessOfPickerOrder() {
        let chord = KeyAction(bindings: [KeyBinding(keyCode: 7), KeyBinding(keyCode: 59),
                                        KeyBinding(keyCode: 8, modifiers: 1 << 17)]).macroChord
        XCTAssertEqual(chord.bindings.first?.keyCode, 59)
        XCTAssertTrue(chord.bindings.allSatisfy { $0.modifiers == (1 << 17) | (1 << 18) })
    }

    func testProgressRemainsMonotonicAcrossKeyWaitAndText() {
        let clock = TestScheduler(); let sink = MacroTestSink()
        let runner = MacroRunner(sink: sink, scheduler: clock)
        runner.start(.init(steps: [.tap(ctrl, milliseconds: 100), .wait(milliseconds: 100),
                                  .text("abc", intervalMilliseconds: 100)]))
        var previous = runner.progress
        for _ in 0..<50 {
            clock.advance(by: 0.01)
            XCTAssertLessThanOrEqual(runner.progress, previous + 0.000001)
            previous = runner.progress
        }
        XCTAssertFalse(runner.isRunning)
    }
}

private final class MacroTestSink: MacroSink {
    var events: [String] = []
    var owners: [(UUID, KeyAction)] = []
    var run: UUID?
    var error: MacroError?
    var deferPress = false
    var ack: (() -> Void)?
    func beginMacro(run: UUID) { self.run = run }
    func macroPress(_ action: KeyAction, owner: UUID, run: UUID, latestStart: TimeInterval?, completion: @escaping (MacroError?) -> Void) {
        if let error { completion(error); return }
        owners.append((owner, action))
        events += action.bindings.map { "down:\($0.keyCode)" }
        if deferPress { ack = { completion(nil) } } else { completion(nil) }
    }
    func macroRelease(owner: UUID, run: UUID, completion: @escaping () -> Void) {
        if self.run == run, let index = owners.firstIndex(where: { $0.0 == owner }) {
            events += owners.remove(at: index).1.bindings.reversed().map { "up:\($0.keyCode)" }
        }
        completion()
    }
    func macroText(_ character: String, run: UUID, completion: @escaping (MacroError?) -> Void) {
        events.append("text:" + character); completion(nil)
    }
    func cancelMacro(run: UUID) {
        guard self.run == run else { return }
        for (_, action) in owners.reversed() { events += action.bindings.reversed().map { "up:\($0.keyCode)" } }
        owners.removeAll(); self.run = nil
    }
}
