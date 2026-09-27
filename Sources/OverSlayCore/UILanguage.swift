import Foundation

public enum OverSlayLanguage: String, CaseIterable, Equatable {
    case english = "en"
    case russian = "ru"

    public static let preferenceKey = "io.github.k0tnk-git.OverSlay.uiLanguage"

    /// The language is fixed for this process so existing windows and editor drafts remain stable.
    public static let active: OverSlayLanguage = resolve(
        savedValue: UserDefaults.standard.string(forKey: preferenceKey)
    )

    public static var preferred: OverSlayLanguage {
        resolve(savedValue: UserDefaults.standard.string(forKey: preferenceKey))
    }

    public static func resolve(savedValue: String?) -> OverSlayLanguage {
        guard let savedValue, let language = OverSlayLanguage(rawValue: savedValue) else { return .english }
        return language
    }

    public static func savePreference(_ language: OverSlayLanguage, defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: preferenceKey)
    }
}

public enum L10n {
    public static func text(_ key: String) -> String {
        text(key, language: OverSlayLanguage.active)
    }

    public static func text(_ key: String, language: OverSlayLanguage) -> String {
        let bundle: Bundle
        if let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            bundle = localizedBundle
        } else if let englishPath = Bundle.module.path(forResource: OverSlayLanguage.english.rawValue, ofType: "lproj"),
                  let englishBundle = Bundle(path: englishPath) {
            bundle = englishBundle
        } else {
            bundle = Bundle.module
        }
        return NSLocalizedString(key, tableName: "Localizable", bundle: bundle, comment: "")
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, language: OverSlayLanguage.active, arguments: arguments)
    }

    public static func format(_ key: String, language: OverSlayLanguage, _ arguments: CVarArg...) -> String {
        format(key, language: language, arguments: arguments)
    }

    private static func format(_ key: String, language: OverSlayLanguage, arguments: [CVarArg]) -> String {
        String(format: text(key, language: language), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    static func catalogKeys(for language: OverSlayLanguage) throws -> Set<String> {
        guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
              let url = Bundle(path: path)?.url(forResource: "Localizable", withExtension: "strings") else { return [] }
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let strings = object as? [String: String] else { return [] }
        return Set(strings.keys)
    }
}
