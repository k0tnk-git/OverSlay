import Foundation

public enum ProfileSelection {
    /// Ambiguous on-disk bindings must never choose an arbitrary game layout.
    public static func matching(_ bundleIdentifier: String, in profiles: [Profile]) -> Profile? {
        let matches = profiles.filter { $0.bundleIdentifier == bundleIdentifier }
        return matches.count == 1 ? matches[0] : nil
    }
}

public struct ProfileActivationState {
    public private(set) var lastExternalBundleIdentifier: String?
    private var manualOverride = false

    public init() {}

    public mutating func selectManually() { manualOverride = true }
    public mutating func clearOverride() { manualOverride = false }

    /// Own windows preserve the last game and manual override, including targets without a bundle ID.
    public mutating func activate(bundle: String?, isOwnApplication: Bool, automatic: Bool,
                                  profiles: [Profile], defaultID: UUID) -> UUID? {
        guard !isOwnApplication else { return nil }
        if bundle != lastExternalBundleIdentifier { manualOverride = false }
        lastExternalBundleIdentifier = bundle
        guard automatic, !manualOverride else { return nil }
        return bundle.flatMap { ProfileSelection.matching($0, in: profiles)?.id } ?? defaultID
    }
}
