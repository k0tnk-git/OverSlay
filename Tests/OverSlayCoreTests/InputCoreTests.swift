import XCTest
@testable import OverSlayCore

final class InputCoreTests: XCTestCase {
    private let w = KeyBinding(keyCode: 13)
    private let a = KeyBinding(keyCode: 0)

    func testLongHoldDoesNotAddCompatibilityDelayAfterRelease() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler)
        let owner = UUID()
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .hold)
        scheduler.advance(by: 1)
        manager.handleRelease(owner: owner)
        XCTAssertEqual(sink.events, [.press(w), .release(w)])
    }

    func testDefaultModeIsHoldUntilMouseRelease() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler)
        let owner = UUID()
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .hold)
        XCTAssertEqual(sink.events, [.press(w)])
        scheduler.advance(by: 1)
        XCTAssertEqual(sink.events, [.press(w)])
        manager.handleRelease(owner: owner)
        XCTAssertEqual(sink.events, [.press(w), .release(w)])
    }

    func testLegacyTapModeDecodesAsOrdinaryHold() throws {
        let mode = try JSONDecoder().decode(TriggerMode.self, from: Data("\"tap\"".utf8))
        XCTAssertEqual(mode, .hold)
    }

    func testWidgetConfigDefaultsToOrdinaryHold() {
        let widget = WidgetConfig(
            geometry: .init(x: 0, y: 0, width: 80, height: 60),
            label: "W",
            action: KeyAction(w)
        )
        XCTAssertEqual(widget.mode, .hold)
    }

    func testTimedToggleReleasesAfterConfiguredDuration() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler, compatibilityMilliseconds: 1)
        let owner = UUID()
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .timedToggle, timedDurationSeconds: 2)
        scheduler.advance(by: 1.999)
        XCTAssertEqual(sink.events, [.press(w)])
        scheduler.advance(by: 0.001)
        XCTAssertEqual(sink.events, [.press(w), .release(w)])
    }

    func testCompatibilityWaitsOnlyForRemainingMinimum() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler, compatibilityMilliseconds: 100)
        let owner = UUID()
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .hold)
        scheduler.advance(by: 0.04)
        manager.handleRelease(owner: owner)
        scheduler.advance(by: 0.059)
        XCTAssertEqual(sink.events, [.press(w)])
        scheduler.advance(by: 0.002)
        XCTAssertEqual(sink.events, [.press(w), .release(w)])
    }

    func testStaleCancelledReleaseCannotReleaseReusedOwner() {
        let sink = InMemoryInputSink()
        let scheduler = UncooperativeScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler)
        let owner = UUID()
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .hold)
        manager.handleRelease(owner: owner)
        manager.reset()
        manager.handlePress(owner: owner, action: KeyAction(a), mode: .hold)
        manager.handleRelease(owner: owner)
        scheduler.actions[0]()
        XCTAssertEqual(sink.events, [.press(w), .releaseAll, .press(a)])
        scheduler.actions[1]()
        XCTAssertEqual(sink.events.last, .release(a))
    }

    func testResetCancelsSequenceBeforeAnyLaterPress() {
        let sink = InMemoryInputSink()
        let scheduler = UncooperativeScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler)
        manager.handlePress(owner: UUID(), action: KeyAction(bindings: [w, a], combinationMode: .sequential), mode: .toggle)
        manager.reset()
        scheduler.actions[0]()
        XCTAssertEqual(sink.events, [.press(w), .releaseAll])
    }

    func testRepressThenReleaseIgnoresOldCallbackEvenIfCancellationRaces() {
        let sink = InMemoryInputSink()
        let scheduler = UncooperativeScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler)
        let owner = UUID()
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .hold)
        manager.handleRelease(owner: owner)
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .hold)
        manager.handleRelease(owner: owner)
        scheduler.actions[0]()
        XCTAssertEqual(sink.events, [.press(w)])
        scheduler.actions[1]()
        XCTAssertEqual(sink.events, [.press(w), .release(w)])
    }

    func testRadialStaleReleaseDoesNotReleaseNewSession() {
        let sink = InMemoryInputSink()
        let scheduler = UncooperativeScheduler()
        let radial = RadialControlEngine(config: RadialConfig(up: KeyAction(w), down: KeyAction(a), left: KeyAction(a), right: KeyAction(w)), sink: sink, scheduler: scheduler)
        radial.update(offset: .init(x: 0, y: 1))
        radial.update(offset: .init(x: 0, y: 0))
        radial.releaseAll()
        radial.update(offset: .init(x: 0, y: 1))
        radial.update(offset: .init(x: 0, y: 0))
        scheduler.actions[0]()
        XCTAssertEqual(sink.events, [.press(w), .release(w), .press(w)])
        scheduler.actions[1]()
        XCTAssertEqual(sink.events.last, .release(w))
    }

    func testProfileRejectsDuplicateIDsAndNonfiniteGeometry() throws {
        let widget = WidgetConfig(geometry: .init(x: 0, y: 0, width: 80, height: 60), label: "W", action: KeyAction(w))
        XCTAssertThrowsError(try Profile(widgets: [widget, widget]).validated())
        var invalid = widget
        invalid.geometry.x = .infinity
        XCTAssertThrowsError(try Profile(widgets: [invalid]).validated())
        let profile = Profile(widgets: [widget])
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile)).validated(), profile)
    }

    func testProfilePersistsTimedModeAndRadialAppearance() throws {
        let widget = WidgetConfig(geometry: .init(x: 4, y: 8, width: 80, height: 60), label: "Q", action: KeyAction(w), mode: .timedToggle, opacity: 0.4, timedDurationSeconds: 7)
        let profile = Profile(widgets: [widget], radial: RadialWidgetConfig(geometry: .init(x: 40, y: 50, width: 220, height: 220), opacity: 0.55))
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile)).validated(), profile)
    }

    func testProfileRejectsNonSquareRadialGeometry() {
        let widget = WidgetConfig(geometry: .init(x: 0, y: 0, width: 80, height: 60), label: "Q", action: KeyAction(w))
        let profile = Profile(widgets: [widget], radial: RadialWidgetConfig(geometry: .init(x: 0, y: 0, width: 220, height: 180)))
        XCTAssertThrowsError(try profile.validated())
    }

    private final class UncooperativeScheduler: ActionScheduler {
        var now: TimeInterval = 0
        var actions: [() -> Void] = []
        func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> Cancellable {
            actions.append(action)
            return Token()
        }
        private final class Token: Cancellable { func cancel() {} }
    }

    func testHoldPressAndReleaseUsesOnePhysicalPair() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler, compatibilityMilliseconds: 1)
        let owner = UUID()
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .hold)
        manager.handleRelease(owner: owner)
        XCTAssertEqual(sink.events, [.press(w)]) // release is scheduled by compatibility mode
        XCTAssertEqual(manager.activeOwnerCount, 0)
        scheduler.advance(by: 0.001)
        XCTAssertEqual(sink.events, [.press(w), .release(w)])
    }

    func testToggleSecondClickReleasesImmediatelyWhenCompatibilityDisabledByAdvance() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler, compatibilityMilliseconds: 10)
        let owner = UUID()
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .toggle)
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .toggle)
        scheduler.advance(by: 0.01)
        XCTAssertEqual(sink.events, [.press(w), .release(w)])
    }

    func testTwoOwnersSharePhysicalKey() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler, compatibilityMilliseconds: 1)
        let first = UUID(); let second = UUID()
        manager.handlePress(owner: first, action: KeyAction(w), mode: .hold)
        manager.handlePress(owner: second, action: KeyAction(w), mode: .hold)
        manager.handleRelease(owner: first)
        scheduler.advance(by: 0.001)
        XCTAssertEqual(sink.events, [.press(w)])
        manager.handleRelease(owner: second)
        scheduler.advance(by: 0.001)
        XCTAssertEqual(sink.events, [.press(w), .release(w)])
    }

    func testSharedChordBindingIsNotReleasedUntilBothOwnersLeave() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler, compatibilityMilliseconds: 1)
        let chord = KeyBinding(keyCode: 0, modifiers: 1)
        let first = UUID(); let second = UUID()
        manager.handlePress(owner: first, action: KeyAction(chord), mode: .hold)
        manager.handlePress(owner: second, action: KeyAction(chord), mode: .hold)
        manager.handleRelease(owner: first)
        scheduler.advance(by: 0.001)
        XCTAssertEqual(sink.events, [.press(chord)])
        manager.handleRelease(owner: second)
        scheduler.advance(by: 0.001)
        XCTAssertEqual(sink.events, [.press(chord), .release(chord)])
    }

    func testRepressCancelsPendingReleaseWithoutDuplicatePress() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler, compatibilityMilliseconds: 100)
        let owner = UUID()
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .hold)
        manager.handleRelease(owner: owner)
        manager.handlePress(owner: owner, action: KeyAction(w), mode: .hold)
        scheduler.advance(by: 0.2)
        XCTAssertEqual(sink.events, [.press(w)])
    }

    func testEmergencyCountersAreIndependentAndIgnoreAutorepeat() {
        var resets = 0
        let controller = EmergencyResetController { resets += 1 }
        for index in 0..<4 { XCTAssertEqual(controller.recordEditClick(at: Double(index) * 0.1), .regular) }
        XCTAssertEqual(controller.recordEscapeKeyDown(at: 0.1, isAutoRepeat: true), .ignored)
        for index in 0..<4 { XCTAssertEqual(controller.recordEscapeKeyDown(at: Double(index) * 0.1, isAutoRepeat: false), .regular) }
        XCTAssertEqual(resets, 0)
        XCTAssertEqual(controller.recordEditClick(at: 0.4), .emergency)
        XCTAssertEqual(resets, 1)
        XCTAssertEqual(controller.recordEscapeKeyDown(at: 0.4, isAutoRepeat: false), .emergency)
        XCTAssertEqual(resets, 2)
    }

    func testEmergencyGapResetsSequence() {
        var resets = 0
        let controller = EmergencyResetController { resets += 1 }
        for index in 0..<4 { _ = controller.recordEditClick(at: Double(index) * 0.1) }
        XCTAssertEqual(controller.recordEditClick(at: 3), .regular)
        XCTAssertEqual(resets, 0)
        for index in 0..<4 { _ = controller.recordEscapeKeyDown(at: 4 + Double(index) * 0.1, isAutoRepeat: false) }
        XCTAssertEqual(resets, 0)
        XCTAssertEqual(controller.recordEscapeKeyDown(at: 4.4, isAutoRepeat: false), .emergency)
    }

    func testResetCancelsPendingReleaseAndClearsAll() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler, compatibilityMilliseconds: 500)
        manager.handlePress(owner: UUID(), action: KeyAction(KeyBinding(keyCode: 1)), mode: .hold)
        manager.reset()
        scheduler.advance(by: 1)
        XCTAssertEqual(manager.activeOwnerCount, 0)
        XCTAssertEqual(sink.events.last, .releaseAll)
    }

    func testSimultaneousCombinationAcquiresAndReleasesEachBinding() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler, compatibilityMilliseconds: 1)
        let owner = UUID()
        let combination = KeyAction(bindings: [KeyBinding(keyCode: 0, modifiers: 1), KeyBinding(keyCode: 2)])
        manager.handlePress(owner: owner, action: combination, mode: .hold)
        manager.handleRelease(owner: owner)
        scheduler.advance(by: 0.001)
        XCTAssertEqual(sink.events, [
            .press(KeyBinding(keyCode: 0, modifiers: 1)),
            .press(KeyBinding(keyCode: 2)),
            .release(KeyBinding(keyCode: 0, modifiers: 1)),
            .release(KeyBinding(keyCode: 2))
        ])
    }

    func testSequentialCombinationReleasesEachBindingBeforeAdvancing() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler, compatibilityMilliseconds: 10)
        let owner = UUID()
        let first = KeyBinding(keyCode: 12)
        let second = KeyBinding(keyCode: 14)
        let action = KeyAction(bindings: [first, second], combinationMode: .sequential)

        manager.handlePress(owner: owner, action: action, mode: .toggle)
        XCTAssertEqual(sink.events, [.press(first)])
        scheduler.advance(by: 0.01)
        XCTAssertEqual(sink.events, [.press(first), .release(first), .press(second)])
        scheduler.advance(by: 0.01)
        XCTAssertEqual(sink.events, [.press(first), .release(first), .press(second), .release(second)])
        XCTAssertTrue(manager.isActive(owner: owner))

        manager.handlePress(owner: owner, action: action, mode: .toggle)
        XCTAssertFalse(manager.isActive(owner: owner))
    }

    func testSequentialCombinationCancelsWhenReleasedEarly() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let manager = ModeManager(sink: sink, scheduler: scheduler, compatibilityMilliseconds: 50)
        let owner = UUID()
        let first = KeyBinding(keyCode: 12)
        let second = KeyBinding(keyCode: 14)

        manager.handlePress(owner: owner, action: KeyAction(bindings: [first, second], combinationMode: .sequential), mode: .hold)
        manager.handleRelease(owner: owner)
        scheduler.advance(by: 1)
        XCTAssertEqual(sink.events, [.press(first), .release(first)])
        XCTAssertEqual(manager.activeOwnerCount, 0)
    }

    func testLegacyKeyActionDefaultsToSimultaneousMode() throws {
        let data = #"{"bindings":[{"keyCode":13,"modifiers":0}]}"#.data(using: .utf8)!
        let action = try JSONDecoder().decode(KeyAction.self, from: data)
        XCTAssertEqual(action.bindings, [w])
        XCTAssertEqual(action.combinationMode, .simultaneous)
    }

    func testRadialDiagonalKeepsSharedDirectionHeld() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let radial = RadialControlEngine(
            config: RadialConfig(
                releaseDelayMilliseconds: 100,
                up: KeyAction(w), down: KeyAction(KeyBinding(keyCode: 1)),
                left: KeyAction(a), right: KeyAction(KeyBinding(keyCode: 2))
            ),
            sink: sink,
            scheduler: scheduler
        )
        radial.update(offset: .init(x: 0, y: 1))
        radial.update(offset: .init(x: 1, y: 1))
        XCTAssertEqual(sink.events, [.press(w), .press(KeyBinding(keyCode: 2))])
        scheduler.advance(by: 0.2)
        XCTAssertEqual(sink.events, [.press(w), .press(KeyBinding(keyCode: 2))])
        radial.update(offset: .init(x: 0, y: 1))
        XCTAssertEqual(sink.events, [.press(w), .press(KeyBinding(keyCode: 2))])
        scheduler.advance(by: 0.1)
        XCTAssertEqual(sink.events, [.press(w), .press(KeyBinding(keyCode: 2)), .release(KeyBinding(keyCode: 2))])
    }

    func testRadialDeadZoneReleasesAfterDelayAndResetIsImmediate() {
        let sink = InMemoryInputSink()
        let scheduler = TestScheduler()
        let radial = RadialControlEngine(
            config: RadialConfig(releaseDelayMilliseconds: 50, up: KeyAction(w), down: KeyAction(a), left: KeyAction(a), right: KeyAction(w)),
            sink: sink,
            scheduler: scheduler
        )
        radial.update(offset: .init(x: 0, y: 1))
        radial.update(offset: .init(x: 0.01, y: 0.01))
        XCTAssertEqual(sink.events, [.press(w)])
        scheduler.advance(by: 0.05)
        XCTAssertEqual(sink.events, [.press(w), .release(w)])
        radial.update(offset: .init(x: 0, y: 1))
        radial.releaseAll()
        XCTAssertEqual(sink.events, [.press(w), .release(w), .press(w), .release(w)])
    }
}
