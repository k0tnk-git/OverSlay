import AppKit
import OverSlayCore

/// A value snapshot of the active system keyboard layout. It intentionally
/// contains no TIS/Carbon pointers so every panel uses the same stable labels.
struct KeyboardLanguage: Equatable {
    let inputSourceID: String?
    let sourceName: String
    let languageCode: String?
    let canTranslate: Bool
    private let translatedLabels: [UInt16: String]

    init(inputSourceID: String?, sourceName: String, languageCode: String? = nil, canTranslate: Bool, translatedLabels: [UInt16: String]) {
        self.inputSourceID = inputSourceID
        self.sourceName = sourceName
        self.languageCode = languageCode
        self.canTranslate = canTranslate
        self.translatedLabels = translatedLabels
    }

    var shortTitle: String {
        switch inputSourceID {
        case "com.apple.keylayout.US", "com.apple.keylayout.ABC": return "EN"
        case "com.apple.keylayout.Russian": return "RU"
        default: break
        }
        if let languageCode,
           let code = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased(),
           (2...3).contains(code.count),
           code.utf8.allSatisfy({ (97...122).contains($0) }),
           !["und", "mul", "zxx"].contains(code) {
            return code.uppercased()
        }
        let words = sourceName.split(whereSeparator: { !$0.isLetter })
        let initials = words.count == 1 ? String(words[0].prefix(2)) : String(words.prefix(2).compactMap(\.first))
        return initials.isEmpty ? L10n.text("КЛ") : initials.uppercased()
    }

    var tooltip: String {
        canTranslate ? sourceName : L10n.format("%@ — this system layout does not provide a character map", sourceName)
    }

    func label(for keyCode: UInt16) -> String {
        if let special = Self.specialLabels[keyCode] { return special }
        guard let value = translatedLabels[keyCode], Self.isVisible(value) else { return "Key \(keyCode)" }
        let uppercase = value.uppercased()
        return uppercase.count == 1 ? uppercase : value
    }

    func displayLabel(for action: KeyAction, fallback: String) -> String {
        let labels = action.bindings.map { binding in
            let flags = NSEvent.ModifierFlags(rawValue: UInt(binding.modifiers))
            let modifiers = [
                flags.contains(.command) ? "⌘" : nil,
                flags.contains(.option) ? "⌥" : nil,
                flags.contains(.control) ? "⌃" : nil,
                flags.contains(.shift) ? "⇧" : nil
            ].compactMap { $0 }.joined()
            return modifiers + label(for: binding.keyCode)
        }
        return labels.isEmpty ? fallback : labels.joined(separator: " + ")
    }

    private static func isVisible(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private static let specialLabels: [UInt16: String] = [
        36: "↩", 48: "Tab", 49: "Space", 51: "⌫", 53: "Esc",
        54: "⌘", 55: "⌘", 56: "⇧", 57: "Caps", 58: "⌥", 59: "⌃",
        60: "⇧", 61: "⌥", 62: "⌃", 63: "Fn", 64: "F17", 65: "Num.",
        67: "Num*", 69: "Num+", 71: "Clear", 75: "Num/", 76: "Num↩",
        78: "Num−", 79: "F18", 80: "F19", 81: "Num=", 82: "Num0", 83: "Num1",
        84: "Num2", 85: "Num3", 86: "Num4", 87: "Num5", 88: "Num6", 89: "Num7",
        90: "F20", 91: "Num8", 92: "Num9", 96: "F5", 97: "F6", 98: "F7",
        99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16",
        107: "F14", 109: "F10", 111: "F12", 113: "F15", 115: "Home", 116: "PgUp",
        117: "Delete", 118: "F4", 119: "End", 120: "F2", 121: "PgDn", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}
