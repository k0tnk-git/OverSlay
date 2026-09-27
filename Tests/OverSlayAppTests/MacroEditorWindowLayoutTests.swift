import AppKit
import XCTest
import OverSlayCore
@testable import OverSlay

@MainActor
final class MacroEditorWindowLayoutTests: XCTestCase {
    func testWindowBuildsAndLaysOutAtSupportedSizes() throws {
        _ = NSApplication.shared
        let language = KeyboardLanguage(inputSourceID: "com.apple.keylayout.US", sourceName: "U.S.",
                                        languageCode: "en", canTranslate: true, translatedLabels: [:])
        let window = MacroEditorWindow(
            language: language,
            onChooseKey: { _ in },
            onSave: { _, _ in true }
        )
        defer { window.close() }
        let contentView = try XCTUnwrap(window.contentView)

        for size in [NSSize(width: 680, height: 720), NSSize(width: 900, height: 800), NSSize(width: 680, height: 480)] {
            window.setContentSize(size)
            contentView.layoutSubtreeIfNeeded()
            XCTAssertEqual(contentView.bounds.width, size.width, accuracy: 1)
            XCTAssertEqual(contentView.bounds.height, size.height, accuracy: 1)
            assertFiniteReasonableFrames(in: contentView)
        }
    }

    private func assertFiniteReasonableFrames(in view: NSView, file: StaticString = #filePath, line: UInt = #line) {
        for dimension in [view.frame.origin.x, view.frame.origin.y, view.frame.width, view.frame.height] {
            XCTAssertTrue(dimension.isFinite, "Non-finite frame in \(type(of: view))", file: file, line: line)
            XCTAssertLessThan(abs(dimension), 10_000, "Unexpected frame size in \(type(of: view))", file: file, line: line)
        }
        for child in view.subviews { assertFiniteReasonableFrames(in: child, file: file, line: line) }
    }
}
