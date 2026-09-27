import XCTest
@testable import OverSlayCore

final class ProfileSelectionTests: XCTestCase {
    func testManualOverrideSurvivesOwnWindowsAndSameGameUntilAnotherTarget() {
        let a = Profile(bundleIdentifier: "a", widgets: ProfileStore.defaultWidgets())
        let b = Profile(bundleIdentifier: "b", widgets: ProfileStore.defaultWidgets())
        let fallback = UUID()
        var state = ProfileActivationState()
        func activate(_ bundle: String?, own: Bool = false, auto: Bool = true) -> UUID? {
            state.activate(bundle: bundle, isOwnApplication: own, automatic: auto,
                           profiles: [a, b], defaultID: fallback)
        }
        XCTAssertEqual(activate("a"), a.id)
        state.selectManually()
        XCTAssertNil(activate("OverSlay", own: true))
        XCTAssertEqual(state.lastExternalBundleIdentifier, "a")
        XCTAssertNil(activate("a"))
        XCTAssertEqual(activate("b"), b.id)
        XCTAssertEqual(activate("a"), a.id)
        XCTAssertEqual(activate("unknown"), fallback)
        XCTAssertEqual(activate(nil), fallback)
        state.selectManually()
        XCTAssertNil(activate(nil))
        state.clearOverride()
        XCTAssertEqual(activate(nil), fallback)
        XCTAssertNil(activate("b", auto: false))
        XCTAssertEqual(state.lastExternalBundleIdentifier, "b")
        XCTAssertEqual(activate("b"), b.id)
    }
}
