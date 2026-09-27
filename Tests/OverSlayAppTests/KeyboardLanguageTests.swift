import XCTest
@testable import OverSlay

final class KeyboardLanguageTests: XCTestCase {
    func testKnownAppleLayoutsKeepTheirEstablishedTitles() {
        XCTAssertEqual(language(id: "com.apple.keylayout.US", name: "U.S.").shortTitle, "EN")
        XCTAssertEqual(language(id: "com.apple.keylayout.ABC", name: "ABC").shortTitle, "EN")
        XCTAssertEqual(language(id: "com.apple.keylayout.Russian", name: "Russian").shortTitle, "RU")
    }

    func testLanguageMetadataUsesPrimarySubtagAndPreservesThreeLetterCodes() {
        XCTAssertEqual(language(name: "Filipino", code: "fil-PH").shortTitle, "FIL")
        XCTAssertEqual(language(name: "English", code: "en_US").shortTitle, "EN")
        XCTAssertEqual(language(name: "Chinese", code: "zh-Hans-CN").shortTitle, "ZH")
    }

    func testUnavailableOrNonLanguageMetadataFallsBackToReadableSourceName() {
        XCTAssertEqual(language(name: "Colemak Keyboard", code: nil).shortTitle, "CK")
        XCTAssertEqual(language(name: "Dvorak", code: "und").shortTitle, "DV")
        XCTAssertEqual(language(name: "日本語", code: "mul").shortTitle, "日本")
    }

    func testEmptyAndEmojiOnlyNamesUseLocalizedFallback() {
        let empty = language(name: "", code: nil)
        let emoji = language(name: "🎮🕹️", code: "zxx")
        XCTAssertFalse(empty.shortTitle.isEmpty)
        XCTAssertEqual(empty.shortTitle.count, 2)
        XCTAssertEqual(emoji.shortTitle, empty.shortTitle)
    }

    private func language(id: String? = nil, name: String, code: String? = nil) -> KeyboardLanguage {
        KeyboardLanguage(inputSourceID: id, sourceName: name, languageCode: code,
                         canTranslate: false, translatedLabels: [:])
    }
}
