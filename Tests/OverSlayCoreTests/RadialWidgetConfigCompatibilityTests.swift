import XCTest
@testable import OverSlayCore

final class RadialWidgetConfigCompatibilityTests: XCTestCase {
    func testLegacyInputModeIsIgnoredWhileAllRadialSettingsSurviveRoundTrip() throws {
        let legacy = #"{"geometry":{"x":31,"y":47,"width":212,"height":212},"opacity":0.43,"rightMouseAction":{"kind":"custom","binding":{"keyCode":56,"modifiers":0}},"scrollUpAction":{"kind":"none"},"scrollDownAction":{"kind":"custom","binding":{"keyCode":49,"modifiers":0}},"inputMode":"analog"}"#.data(using: .utf8)!

        let config = try JSONDecoder().decode(RadialWidgetConfig.self, from: legacy)
        XCTAssertEqual(config.geometry, WidgetGeometry(x: 31, y: 47, width: 212, height: 212))
        XCTAssertEqual(config.opacity, 0.43)
        XCTAssertEqual(config.rightMouseAction, .custom(KeyBinding(keyCode: 56)))
        XCTAssertEqual(config.scrollUpAction, .none)
        XCTAssertEqual(config.scrollDownAction, .custom(KeyBinding(keyCode: 49)))

        let encoded = try JSONEncoder().encode(config)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["inputMode"])
        XCTAssertEqual(try JSONDecoder().decode(RadialWidgetConfig.self, from: encoded), config)
    }

    func testMalformedKnownFieldStillFailsEvenWhenLegacyInputModeIsPresent() {
        let malformed = #"{"geometry":{"x":"left","y":47,"width":212,"height":212},"opacity":0.43,"inputMode":"analog"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(RadialWidgetConfig.self, from: malformed))
    }
}
