import AppKit
import OverSlayCore
import Carbon.HIToolbox

final class KeyboardInputSourceController {
    enum SwitchError: LocalizedError {
        case noSelectableLayouts
        case selectionFailed(String, OSStatus)
        case selectionNotConfirmed(String)

        var errorDescription: String? {
            switch self {
            case .noSelectableLayouts:
                return L10n.text("Нет доступных включённых раскладок клавиатуры")
            case let .selectionFailed(name, status):
                return L10n.format("Could not select keyboard layout “%@” (%@)", name, String(status))
            case let .selectionNotConfirmed(name):
                return L10n.format("macOS did not confirm switching to “%@”", name)
            }
        }
    }

    var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?
    private var sourceListObserver: NSObjectProtocol?

    init() {
        let center = DistributedNotificationCenter.default()
        observer = center.addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onChange?() }

        sourceListObserver = center.addObserver(
            forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onChange?() }
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        if let sourceListObserver { DistributedNotificationCenter.default().removeObserver(sourceListObserver) }
    }

    var currentLanguage: KeyboardLanguage { snapshot(for: currentSource()) }

    func nextLanguage(beforeSelection: () -> Void) throws -> KeyboardLanguage {
        let sources = selectableSources()
        guard !sources.isEmpty else { throw SwitchError.noSelectableLayouts }

        let currentID = currentLanguage.inputSourceID
        let index = sources.firstIndex { (property(kTISPropertyInputSourceID, from: $0) as? String) == currentID }
        let nextIndex = index.map { ($0 + 1) % sources.count } ?? 0
        let source = sources[nextIndex]
        let requestedID = property(kTISPropertyInputSourceID, from: source) as? String ?? ""
        let requestedName = property(kTISPropertyLocalizedName, from: source) as? String ?? requestedID
        guard requestedID != currentID else { return currentLanguage }
        beforeSelection()
        let status = TISSelectInputSource(source)
        guard status == noErr else { throw SwitchError.selectionFailed(requestedName, status) }

        guard let actual = currentSource(),
              (property(kTISPropertyInputSourceID, from: actual) as? String) == requestedID else {
            throw SwitchError.selectionNotConfirmed(requestedName)
        }
        return snapshot(for: actual)
    }

    private func currentSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private func selectableSources() -> [TISInputSource] {
        guard let category = kTISCategoryKeyboardInputSource else { return [] }
        let properties = [
            kTISPropertyInputSourceCategory: category,
            kTISPropertyInputSourceIsEnabled: kCFBooleanTrue as Any
        ] as CFDictionary
        guard let sources = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }

        var byID: [String: TISInputSource] = [:]
        for source in sources {
            guard let identifier = property(kTISPropertyInputSourceID, from: source) as? String,
                  let type = property(kTISPropertyInputSourceType, from: source) as? String,
                  type == (kTISTypeKeyboardLayout as String),
                  (property(kTISPropertyInputSourceIsSelectCapable, from: source) as? NSNumber)?.boolValue == true else {
                continue
            }
            byID[identifier] = source
        }
        return byID.keys.sorted().compactMap { byID[$0] }
    }

    private func snapshot(for source: TISInputSource?) -> KeyboardLanguage {
        guard let source else {
            return KeyboardLanguage(inputSourceID: nil, sourceName: L10n.text("Источник ввода недоступен"), canTranslate: false, translatedLabels: [:])
        }

        let identifier = property(kTISPropertyInputSourceID, from: source) as? String
        let name = property(kTISPropertyLocalizedName, from: source) as? String ?? identifier ?? L10n.text("Раскладка клавиатуры")
        let languages = property(kTISPropertyInputSourceLanguages, from: source) as? [String]
        let labels = translatedLabels(for: source)
        return KeyboardLanguage(inputSourceID: identifier, sourceName: name, languageCode: languages?.first, canTranslate: labels != nil, translatedLabels: labels ?? [:])
    }

    private func translatedLabels(for source: TISInputSource) -> [UInt16: String]? {
        guard let data = property(kTISPropertyUnicodeKeyLayoutData, from: source) as? Data,
              !data.isEmpty else { return nil }

        let keyCodes: [UInt16] = [
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19,
            20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 37,
            38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 50
        ]
        var labels: [UInt16: String] = [:]
        data.withUnsafeBytes { bytes in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            for keyCode in keyCodes {
                var deadKeyState: UInt32 = 0
                var actualLength = 0
                var characters = [UniChar](repeating: 0, count: 255)
                let status = characters.withUnsafeMutableBufferPointer { buffer in
                    UCKeyTranslate(
                        layout,
                        keyCode,
                        UInt16(kUCKeyActionDisplay),
                        0,
                        UInt32(LMGetKbdType()),
                        OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState,
                        buffer.count,
                        &actualLength,
                        buffer.baseAddress!
                    )
                }
                guard status == noErr, actualLength > 0 else { continue }
                let value = String(utf16CodeUnits: characters, count: actualLength)
                if !value.isEmpty { labels[keyCode] = value }
            }
        }
        return labels.isEmpty ? nil : labels
    }

    private func property(_ key: CFString, from source: TISInputSource) -> Any? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue()
    }
}
