import Foundation

public struct ProfilePreferences: Codable {
    public var defaultProfileID: UUID
    public var selectedProfileID: UUID
    public var lastManualProfileID: UUID
    public var autoSelectByBundleIdentifier = false
    public var snapToGrid = true
    public var snapToEdges = true

    public init(defaultProfileID: UUID, selectedProfileID: UUID, lastManualProfileID: UUID) {
        self.defaultProfileID = defaultProfileID
        self.selectedProfileID = selectedProfileID
        self.lastManualProfileID = lastManualProfileID
    }

    private enum CodingKeys: String, CodingKey {
        case defaultProfileID, selectedProfileID, lastManualProfileID, autoSelectByBundleIdentifier, snapToGrid, snapToEdges
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        defaultProfileID = try values.decode(UUID.self, forKey: .defaultProfileID)
        selectedProfileID = try values.decode(UUID.self, forKey: .selectedProfileID)
        lastManualProfileID = try values.decode(UUID.self, forKey: .lastManualProfileID)
        autoSelectByBundleIdentifier = try values.decodeIfPresent(Bool.self, forKey: .autoSelectByBundleIdentifier) ?? false
        snapToGrid = try values.decodeIfPresent(Bool.self, forKey: .snapToGrid) ?? true
        snapToEdges = try values.decodeIfPresent(Bool.self, forKey: .snapToEdges) ?? true
    }
}

public final class ProfileStore {
    private let directory: URL
    private let fileManager: FileManager
    private let uiLanguage: OverSlayLanguage
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let preferencesURL: URL
    public private(set) var catalogIssues: [String] = []

    public init(fileManager: FileManager = .default, directory: URL? = nil, uiLanguage: OverSlayLanguage = .active) {
        self.fileManager = fileManager
        self.uiLanguage = uiLanguage
        if let directory {
            self.directory = directory
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = support.appendingPathComponent("OverSlay/Profiles", isDirectory: true)
        }
        preferencesURL = self.directory.appendingPathComponent("settings.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    public func loadOrCreateDefault() throws -> Profile {
        let all = try loadAll()
        guard let preferences = try loadPreferences(), let profile = all.first(where: { $0.id == preferences.defaultProfileID }) else {
            throw ProfileStoreError.missingDefaultProfile
        }
        return profile
    }

    public func loadAll() throws -> [Profile] {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var profiles: [Profile] = []
        catalogIssues = []
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for url in files where url.pathExtension.lowercased() == "json" && url.lastPathComponent != "default.json" && url.lastPathComponent != "settings.json" {
            do {
                let decoded = try decoder.decode(Profile.self, from: Data(contentsOf: url))
                let profile = try migrate(decoded).validated()
                guard url.deletingPathExtension().lastPathComponent.lowercased() == profile.id.uuidString.lowercased() else {
                    throw ProfileStoreError.profileFileIDMismatch
                }
                profiles.append(profile)
                if profile != decoded {
                    do { try writeProfile(profile) }
                    catch { catalogIssues.append(L10n.format("Migration for %@ loaded, but could not be saved: %@", url.lastPathComponent, error.localizedDescription)) }
                }
            } catch {
                catalogIssues.append(L10n.format("%@: %@", url.lastPathComponent, error.localizedDescription))
            }
        }

        // Copy the old single-profile file into the collection. Keep it as a recovery copy.
        let legacyURL = directory.appendingPathComponent("default.json")
        var preferences = try loadPreferences()
        if fileManager.fileExists(atPath: legacyURL.path) {
            do {
                let old = try migrate(decoder.decode(Profile.self, from: Data(contentsOf: legacyURL))).validated()
                if !profiles.contains(where: { $0.id == old.id }) && !fileManager.fileExists(atPath: profileURL(old.id).path) {
                    var migrated = Self.migrateLegacyStarterProfile(old)
                    migrated.bundleIdentifier = nil
                    try writeProfile(migrated)
                    profiles.append(migrated)
                }
                if preferences == nil {
                    preferences = ProfilePreferences(defaultProfileID: old.id, selectedProfileID: old.id, lastManualProfileID: old.id)
                }
            } catch {
                // A broken legacy file must remain untouched and must not be replaced by an empty layout.
                if profiles.isEmpty { throw error }
                catalogIssues.append(L10n.format("default.json: %@", error.localizedDescription))
            }
        }

        if profiles.isEmpty {
            guard catalogIssues.isEmpty else { throw ProfileStoreError.noReadableProfiles(catalogIssues) }
            let profile = Profile(name: L10n.text("По умолчанию", language: uiLanguage), widgets: Self.defaultWidgets())
            try writeProfile(profile)
            profiles = [profile]
            preferences = ProfilePreferences(defaultProfileID: profile.id, selectedProfileID: profile.id, lastManualProfileID: profile.id)
        }

        if preferences == nil {
            if let defaultProfile = profiles.first(where: { Self.isDefaultProfileName($0.name) }) {
                preferences = ProfilePreferences(defaultProfileID: defaultProfile.id, selectedProfileID: defaultProfile.id, lastManualProfileID: defaultProfile.id)
            } else {
                let defaultProfile = Profile(name: L10n.text("По умолчанию", language: uiLanguage), widgets: Self.defaultWidgets())
                try writeProfile(defaultProfile)
                profiles.append(defaultProfile)
                preferences = ProfilePreferences(defaultProfileID: defaultProfile.id, selectedProfileID: defaultProfile.id, lastManualProfileID: defaultProfile.id)
            }
        }
        if let value = preferences, !profiles.contains(where: { $0.id == value.defaultProfileID }) {
            catalogIssues.append(L10n.text("Профиль по умолчанию недоступен; исходный файл сохранён."))
            let fallback: Profile
            if let namedDefault = profiles.first(where: { Self.isDefaultProfileName($0.name) }) {
                fallback = namedDefault
            } else {
                fallback = Profile(name: L10n.text("По умолчанию", language: uiLanguage), widgets: Self.defaultWidgets())
                try writeProfile(fallback)
                profiles.append(fallback)
            }
            preferences?.defaultProfileID = fallback.id
        }
        if let value = preferences, !profiles.contains(where: { $0.id == value.selectedProfileID }) {
            preferences?.selectedProfileID = value.defaultProfileID
            preferences?.lastManualProfileID = value.defaultProfileID
        }
        if let value = preferences, !profiles.contains(where: { $0.id == value.lastManualProfileID }) {
            preferences?.lastManualProfileID = value.defaultProfileID
        }
        for (bundle, matches) in Dictionary(grouping: profiles.filter { $0.bundleIdentifier != nil }, by: { $0.bundleIdentifier! }) where matches.count > 1 {
            catalogIssues.append(L10n.format("Duplicate app link for %@. Choose a profile manually.", bundle))
        }
        if let preferences { try savePreferences(preferences) }
        return profiles.sorted {
            if $0.id == preferences?.defaultProfileID { return true }
            if $1.id == preferences?.defaultProfileID { return false }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func loadProfile(id: UUID) throws -> Profile {
        let url = profileURL(id)
        let profile = try migrate(decoder.decode(Profile.self, from: Data(contentsOf: url))).validated()
        guard profile.id == id else { throw ProfileStoreError.profileFileIDMismatch }
        return profile
    }

    public func save(_ profile: Profile) throws {
        try writeProfile(profile)
    }

    public func delete(id: UUID) throws {
        guard let preferences = try loadPreferences(), id != preferences.defaultProfileID else { throw ProfileStoreError.cannotDeleteDefault }
        try fileManager.removeItem(at: profileURL(id))
    }

    public func loadPreferences() throws -> ProfilePreferences? {
        guard fileManager.fileExists(atPath: preferencesURL.path) else { return nil }
        return try decoder.decode(ProfilePreferences.self, from: Data(contentsOf: preferencesURL))
    }

    public func savePreferences(_ preferences: ProfilePreferences) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(preferences).write(to: preferencesURL, options: .atomic)
    }

    public func load(from url: URL) throws -> Profile {
        try migrate(decoder.decode(Profile.self, from: Data(contentsOf: url))).validated()
    }

    public func export(_ profile: Profile, to url: URL) throws {
        let valid = try profile.validated()
        try encoder.encode(valid).write(to: url, options: .atomic)
    }

    private func writeProfile(_ profile: Profile) throws {
        let valid = try profile.validated()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(valid).write(to: profileURL(valid.id), options: .atomic)
    }

    private func profileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    public static func defaultWidgets() -> [WidgetConfig] {
        [
            WidgetConfig(geometry: .init(x: 110, y: 310, width: 78, height: 58), label: "W", action: .init(.init(keyCode: 13)), mode: .hold),
            WidgetConfig(geometry: .init(x: 110, y: 240, width: 78, height: 58), label: "S", action: .init(.init(keyCode: 1)), mode: .hold),
            WidgetConfig(geometry: .init(x: 20, y: 240, width: 78, height: 58), label: "A", action: .init(.init(keyCode: 0)), mode: .hold),
            WidgetConfig(geometry: .init(x: 200, y: 240, width: 78, height: 58), label: "D", action: .init(.init(keyCode: 2)), mode: .hold),
            WidgetConfig(geometry: .init(x: 300, y: 240, width: 128, height: 58), label: "Space", action: .init(.init(keyCode: 49)), mode: .hold),
            WidgetConfig(geometry: .init(x: 450, y: 240, width: 78, height: 58), label: "E", action: .init(.init(keyCode: 14)), mode: .hold)
        ]
    }

    private static func isDefaultProfileName(_ name: String) -> Bool {
        name == "По умолчанию" || name == "Default"
    }

    private static func migrateLegacyStarterProfile(_ profile: Profile) -> Profile {
        let defaults = defaultWidgets()
        let legacyModes: [TriggerMode] = [.hold, .hold, .hold, .hold, .toggle, .toggle]
        guard profile.widgets.count == defaults.count,
              profile.widgets.enumerated().allSatisfy({ item in
                  let index = item.offset
                  let widget = item.element
                  let expected = defaults[index]
                  return widget.geometry == expected.geometry && widget.label == expected.label
                      && widget.action == expected.action && widget.opacity == expected.opacity
                      && widget.timedDurationSeconds == expected.timedDurationSeconds && widget.mode == legacyModes[index]
              }) else { return profile }
        var migrated = profile
        for index in migrated.widgets.indices { migrated.widgets[index].mode = .hold }
        return migrated
    }

    private func migrate(_ profile: Profile) throws -> Profile {
        guard (1...Profile.currentSchemaVersion).contains(profile.schemaVersion) else {
            throw ProfileError.unsupportedSchema(profile.schemaVersion)
        }
        var migrated = profile
        migrated.schemaVersion = Profile.currentSchemaVersion
        if migrated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { migrated.name = L10n.text("Новый профиль") }
        return migrated
    }
}

public enum ProfileStoreError: LocalizedError {
    case missingDefaultProfile, profileFileIDMismatch, cannotDeleteDefault, noReadableProfiles([String])
    public var errorDescription: String? {
        switch self {
        case .missingDefaultProfile: return L10n.text("Не найден профиль «По умолчанию».")
        case .profileFileIDMismatch: return L10n.text("ID профиля не совпадает с именем файла.")
        case .cannotDeleteDefault: return L10n.text("Профиль «По умолчанию» нельзя удалить.")
        case .noReadableProfiles(let issues): return L10n.format("Не удалось загрузить профили: %@", issues.joined(separator: "; "))
        }
    }
}
