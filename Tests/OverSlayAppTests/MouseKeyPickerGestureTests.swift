import AppKit
import XCTest
import OverSlayCore
@testable import OverSlay

@MainActor
final class MouseKeyPickerGestureTests: XCTestCase {
    func testCancelDuringDragSuppressesPickAndDragCallbacksOnMouseUp() throws {
        _ = NSApplication.shared
        var pickCount = 0
        var dragCount = 0
        var cancelCount = 0
        let picker = makePicker(onPick: { _, _ in pickCount += 1 },
                                onDrag: { _, _, _ in dragCount += 1 },
                                onCancel: { cancelCount += 1 })
        let drop = try place(picker, onScreenWithRoom: true)
        picker.makeKeyAndOrderFront(nil)
        defer { picker.close() }
        let key = try keyButton(in: picker, code: 27)

        key.mouseDown(with: mouseEvent(.leftMouseDown, point: NSPoint(x: 80, y: 80), in: picker))
        key.mouseDragged(with: mouseEvent(.leftMouseDragged, point: NSPoint(x: 90, y: 80), in: picker))
        let release = mouseEvent(.leftMouseUp, point: picker.convertPoint(fromScreen: drop), in: picker)
        try XCTUnwrap(button(in: picker, title: L10n.text("Отмена"))).performClick(nil)
        key.mouseUp(with: release)

        XCTAssertFalse(picker.isVisible)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(pickCount, 0)
        XCTAssertEqual(dragCount, 0)
    }

    func testCancelPlacementWhilePickerRemainsOpenSuppressesReleaseCallback() throws {
        _ = NSApplication.shared
        var pickCount = 0
        var dragCount = 0
        let picker = makePicker(onPick: { _, _ in pickCount += 1 },
                                onDrag: { _, _, _ in dragCount += 1 }, onCancel: {})
        let drop = try place(picker, onScreenWithRoom: true)
        picker.makeKeyAndOrderFront(nil)
        defer { picker.close() }
        let key = try keyButton(in: picker, code: 27)

        key.mouseDown(with: mouseEvent(.leftMouseDown, point: NSPoint(x: 80, y: 80), in: picker))
        key.mouseDragged(with: mouseEvent(.leftMouseDragged, point: NSPoint(x: 90, y: 80), in: picker))
        picker.cancelPlacement()
        key.mouseUp(with: mouseEvent(.leftMouseUp, point: picker.convertPoint(fromScreen: drop), in: picker))

        XCTAssertTrue(picker.isVisible)
        XCTAssertEqual(pickCount, 0)
        XCTAssertEqual(dragCount, 0)
    }

    func testDragWithoutDragHandlerLeavesPickerOpenAndKeepsTapBehavior() throws {
        _ = NSApplication.shared
        var pickCount = 0
        var pickedAction: KeyAction?
        let picker = makePicker(onPick: { action, _ in pickCount += 1; pickedAction = action }, onCancel: {})
        _ = try place(picker, onScreenWithRoom: false)
        picker.makeKeyAndOrderFront(nil)
        defer { picker.close() }
        let key = try keyButton(in: picker, code: 27)

        key.mouseDown(with: mouseEvent(.leftMouseDown, point: NSPoint(x: 80, y: 80), in: picker))
        key.mouseDragged(with: mouseEvent(.leftMouseDragged, point: NSPoint(x: -500, y: -500), in: picker))
        key.mouseUp(with: mouseEvent(.leftMouseUp, point: NSPoint(x: -500, y: -500), in: picker))

        XCTAssertTrue(picker.isVisible)
        XCTAssertEqual(pickCount, 0)
        try XCTUnwrap(button(in: picker, title: L10n.text("Добавить"))).performClick(nil)
        XCTAssertEqual(pickCount, 1)
        XCTAssertEqual(pickedAction?.bindings, [KeyBinding(keyCode: 27)])
        XCTAssertFalse(picker.isVisible)
    }

    func testSuccessfulDragReportsAnOnScreenDropPointOutsidePicker() throws {
        _ = NSApplication.shared
        var placement: NSPoint?
        let picker = makePicker(onPick: { _, _ in }, onDrag: { _, _, point in placement = point }, onCancel: {})
        let drop = try place(picker, onScreenWithRoom: true)
        picker.makeKeyAndOrderFront(nil)
        defer { picker.close() }
        let key = try keyButton(in: picker, code: 27)

        key.mouseDown(with: mouseEvent(.leftMouseDown, point: NSPoint(x: 80, y: 80), in: picker))
        key.mouseDragged(with: mouseEvent(.leftMouseDragged, point: NSPoint(x: 90, y: 80), in: picker))
        key.mouseUp(with: mouseEvent(.leftMouseUp, point: picker.convertPoint(fromScreen: drop), in: picker))

        XCTAssertEqual(placement, drop)
        XCTAssertFalse(picker.isVisible)
    }

    func testPlacementResetSuppressesLateReleaseAndAllowsANewClick() throws {
        _ = NSApplication.shared
        var pickCount = 0
        var dragCount = 0
        let picker = makePicker(onPick: { _, _ in pickCount += 1 },
                                onDrag: { _, _, _ in dragCount += 1 }, onCancel: {})
        let drop = try place(picker, onScreenWithRoom: true)
        picker.makeKeyAndOrderFront(nil)
        defer { picker.close() }
        let key = try keyButton(in: picker, code: 27)
        let down = mouseEvent(.leftMouseDown, point: NSPoint(x: 80, y: 80), in: picker)
        key.mouseDown(with: down)
        key.mouseDragged(with: mouseEvent(.leftMouseDragged, point: NSPoint(x: 90, y: 80), in: picker))
        picker.cancelPlacement()
        key.mouseUp(with: mouseEvent(.leftMouseUp, point: picker.convertPoint(fromScreen: drop), in: picker))
        try XCTUnwrap(button(in: picker, title: L10n.text("Добавить"))).performClick(nil)
        XCTAssertTrue(picker.isVisible)
        XCTAssertEqual(pickCount, 0)
        XCTAssertEqual(dragCount, 0)

        key.mouseDown(with: down)
        key.mouseUp(with: mouseEvent(.leftMouseUp, point: NSPoint(x: 80, y: 80), in: picker))
        try XCTUnwrap(button(in: picker, title: L10n.text("Добавить"))).performClick(nil)
        XCTAssertEqual(pickCount, 1)
        XCTAssertEqual(dragCount, 0)
    }

    private func makePicker(onPick: @escaping (KeyAction, String) -> Void,
                            onDrag: ((KeyAction, String, NSPoint) -> Void)? = nil,
                            onCancel: @escaping () -> Void) -> MouseKeyPickerWindow {
        let language = KeyboardLanguage(inputSourceID: "com.apple.keylayout.US", sourceName: "U.S.",
                                        languageCode: "en", canTranslate: true, translatedLabels: [:])
        return MouseKeyPickerWindow(language: language, onPick: onPick, onDrag: onDrag, onCancel: onCancel)
    }

    private func keyButton(in window: NSWindow, code: Int) throws -> NSButton {
        try XCTUnwrap(allViews(in: try XCTUnwrap(window.contentView)).compactMap { $0 as? NSButton }
            .first { $0.tag == code })
    }

    private func place(_ window: NSWindow, onScreenWithRoom: Bool) throws -> NSPoint {
        let frame = window.frame
        let candidates = NSScreen.screens.filter {
            !onScreenWithRoom || ($0.frame.width > frame.width + 20 && $0.frame.height > frame.height + 20)
        }
        guard let screen = candidates.first else { throw XCTSkip("No display is large enough for an on-screen drop outside the picker.") }
        window.setFrameOrigin(screen.frame.origin)
        return NSPoint(x: screen.frame.maxX - 5, y: screen.frame.minY + 40)
    }

    private func button(in window: NSWindow, title: String) -> NSButton? {
        allViews(in: window.contentView ?? NSView()).compactMap { $0 as? NSButton }.first { $0.title == title }
    }

    private func allViews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(allViews(in:))
    }

    private func mouseEvent(_ type: NSEvent.EventType, point: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 1)!
    }
}
