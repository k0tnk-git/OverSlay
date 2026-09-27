import ApplicationServices
import OverSlayCore

final class PermissionsManager {
    var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    func requestIfNeeded() -> Bool {
        guard !isTrusted else { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    var summary: String { L10n.text(isTrusted ? L10n.text("Accessibility: разрешено") : L10n.text("Accessibility: требуется разрешение")) }
}
