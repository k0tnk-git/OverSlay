import XCTest
@testable import OverSlayCore

final class UILanguageTests: XCTestCase {
    func testEnglishIsDefaultAndUnknownSavedValuesFallBackToEnglish() {
        XCTAssertEqual(OverSlayLanguage.resolve(savedValue: nil), .english)
        XCTAssertEqual(OverSlayLanguage.resolve(savedValue: "fr"), .english)
        XCTAssertEqual(OverSlayLanguage.resolve(savedValue: "ru"), .russian)
    }

    func testPreferencePersistsInAnIsolatedDefaultsSuite() {
        let suite = "UILanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(defaults.string(forKey: OverSlayLanguage.preferenceKey))
        OverSlayLanguage.savePreference(.russian, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: OverSlayLanguage.preferenceKey), "ru")
        XCTAssertEqual(OverSlayLanguage.resolve(savedValue: defaults.string(forKey: OverSlayLanguage.preferenceKey)), .russian)
    }

    func testEnglishAndRussianCatalogsHaveMatchingKeysAndFormatArguments() throws {
        XCTAssertEqual(try L10n.catalogKeys(for: .english), try L10n.catalogKeys(for: .russian))
        XCTAssertEqual(L10n.format("Не удалось загрузить профили: %@", language: .english, "profile.json"), "Could not load profiles: profile.json")
        XCTAssertEqual(L10n.format("Не удалось загрузить профили: %@", language: .russian, "profile.json"), "Не удалось загрузить профили: profile.json")
        XCTAssertEqual(L10n.text("Аварийный сброс", language: .english), "Emergency Reset")
        XCTAssertEqual(L10n.text("Аварийный сброс", language: .russian), "Аварийный сброс")
    }
}
