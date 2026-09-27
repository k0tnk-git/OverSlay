import XCTest
@testable import OverSlayCore

final class ProfileStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ProfileStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ProfileStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func file(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    func testIndependentProfilesRoundTripAndProtectedDefault() throws {
        let original = try store.loadOrCreateDefault()
        var copy = Profile(name: "Game", widgets: original.widgets, radial: original.radial)
        copy.widgets[0].label = "Different"
        try store.save(copy)
        XCTAssertEqual(try store.loadProfile(id: original.id), original)
        XCTAssertEqual(try store.loadProfile(id: copy.id), copy)
        XCTAssertThrowsError(try store.delete(id: original.id))
        try store.delete(id: copy.id)
        XCTAssertEqual(try store.loadAll().map(\.id), [original.id])
    }

    func testFreshInstallCreatesEnglishDefaultProfile() throws {
        let englishStore = ProfileStore(directory: directory, uiLanguage: .english)
        let profiles = try englishStore.loadAll()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].name, "Default")
    }

    func testLegacyRussianDefaultNameIsReusedWithoutCreatingDuplicate() throws {
        let legacy = Profile(name: "По умолчанию", widgets: ProfileStore.defaultWidgets())
        try store.save(legacy)

        let profiles = try store.loadAll()

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].id, legacy.id)
        XCTAssertEqual(profiles[0].name, "По умолчанию")
        XCTAssertEqual(try store.loadPreferences()?.defaultProfileID, legacy.id)
    }

    func testLegacyMigrationIsIdempotentAndPreservesBackup() throws {
        var old = Profile(name: "Legacy", widgets: ProfileStore.defaultWidgets())
        old.schemaVersion = 2
        old.widgets[0].geometry.x = 987
        let data = try JSONEncoder().encode(old)
        let legacy = directory.appendingPathComponent("default.json")
        try data.write(to: legacy)
        let first = try store.loadAll()
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].id, old.id)
        XCTAssertEqual(first[0].widgets, old.widgets)
        XCTAssertEqual(first[0].schemaVersion, Profile.currentSchemaVersion)
        XCTAssertEqual(try store.loadAll(), first)
        XCTAssertEqual(try Data(contentsOf: legacy), data)
    }

    func testBackupDoesNotOverwriteDamagedMigratedFile() throws {
        let old = Profile(widgets: ProfileStore.defaultWidgets())
        try JSONEncoder().encode(old).write(to: directory.appendingPathComponent("default.json"))
        _ = try store.loadAll()
        let damaged = Data("broken newer user data".utf8)
        try damaged.write(to: file(old.id))
        XCTAssertThrowsError(try store.loadAll())
        XCTAssertEqual(try Data(contentsOf: file(old.id)), damaged)
    }

    func testCorruptSiblingDoesNotHideValidProfiles() throws {
        let original = try store.loadOrCreateDefault()
        let url = file(UUID())
        let damaged = Data("broken".utf8)
        try damaged.write(to: url)
        XCTAssertEqual(try store.loadAll(), [original])
        XCTAssertFalse(store.catalogIssues.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }

    func testInvalidSaveAndUnknownImportPreserveExistingData() throws {
        let original = try store.loadOrCreateDefault()
        let before = try Data(contentsOf: file(original.id))
        var invalid = original
        invalid.name = " "
        XCTAssertThrowsError(try store.save(invalid))
        invalid.schemaVersion = Profile.currentSchemaVersion + 1
        let imported = directory.appendingPathComponent("import.json")
        try JSONEncoder().encode(invalid).write(to: imported)
        XCTAssertThrowsError(try store.load(from: imported))
        XCTAssertEqual(try Data(contentsOf: file(original.id)), before)
    }

    func testPreferencesPersistManualChoiceAndAutoModeSeparately() throws {
        let original = try store.loadOrCreateDefault()
        let game = Profile(name: "Game", widgets: original.widgets)
        try store.save(game)
        var prefs = try XCTUnwrap(store.loadPreferences())
        prefs.lastManualProfileID = game.id
        prefs.autoSelectByBundleIdentifier = true
        try store.savePreferences(prefs)
        _ = try store.loadAll()
        let restored = try XCTUnwrap(store.loadPreferences())
        XCTAssertEqual(restored.selectedProfileID, original.id)
        XCTAssertEqual(restored.lastManualProfileID, game.id)
        XCTAssertTrue(restored.autoSelectByBundleIdentifier)
    }

    func testAmbiguousBindingsNeverSelectAnArbitraryProfile() throws {
        let a = Profile(bundleIdentifier: "game.id", widgets: ProfileStore.defaultWidgets())
        let b = Profile(bundleIdentifier: "game.id", widgets: ProfileStore.defaultWidgets())
        XCTAssertEqual(ProfileSelection.matching("game.id", in: [a])?.id, a.id)
        XCTAssertNil(ProfileSelection.matching("unknown", in: [a]))
        XCTAssertNil(ProfileSelection.matching("game.id", in: [a, b]))
        try store.save(a)
        try store.save(b)
        _ = try store.loadAll()
        XCTAssertFalse(store.catalogIssues.isEmpty)
    }

    func testWriteFailureLeavesOtherProfilesReadable() throws {
        let original = try store.loadOrCreateDefault()
        let blocked = Profile(widgets: original.widgets)
        try FileManager.default.createDirectory(at: file(blocked.id), withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.save(blocked))
        XCTAssertEqual(try store.loadProfile(id: original.id), original)
    }

    func testAppearanceRoundTripsThroughProfileJSON() throws {
        let baseline = try store.loadOrCreateDefault()
        var profile = baseline
        profile.widgets[0].appearance = ButtonAppearance(pattern: .checkered, firstColor: "#718096", secondColor: "#B8796B")
        try store.save(profile)
        XCTAssertEqual(try store.loadProfile(id: profile.id).widgets[0].appearance, profile.widgets[0].appearance)
    }

    func testV4ProfileMigratesWithLegacyDarkGrayAppearance() throws {
        var profile = Profile(name: "Old", widgets: ProfileStore.defaultWidgets())
        profile.schemaVersion = 4
        let raw = try JSONEncoder().encode(profile)
        let object = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        var legacy = object
        legacy["widgets"] = (object["widgets"] as! [[String: Any]]).map { widget -> [String: Any] in
            var value = widget; value.removeValue(forKey: "appearance"); return value
        }
        try JSONSerialization.data(withJSONObject: legacy).write(to: file(profile.id))

        let loaded = try store.loadAll()
        let migrated = try XCTUnwrap(loaded.first(where: { $0.id == profile.id }))
        XCTAssertEqual(migrated.schemaVersion, Profile.currentSchemaVersion)
        XCTAssertTrue(migrated.widgets.allSatisfy { $0.appearance == .default })
        let persisted = try store.loadProfile(id: profile.id)
        XCTAssertEqual(persisted, migrated)
    }

    func testInvalidAppearanceIsRejectedWithoutReplacingSavedProfile() throws {
        var profile = try store.loadOrCreateDefault()
        let before = try Data(contentsOf: file(profile.id))
        profile.widgets[0].appearance.firstColor = "not-hex"
        XCTAssertThrowsError(try store.save(profile))
        XCTAssertEqual(try Data(contentsOf: file(profile.id)), before)
    }

    func testUnknownAppearancePatternCannotDecode() throws {
        let data = Data("{\"pattern\":\"glitter\",\"firstColor\":\"#555555\",\"secondColor\":\"#718096\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ButtonAppearance.self, from: data))
    }
}
