import Cocoa

/// Serializes CGEvent keyboard injection and keeps reference counts so overlapping buttons cannot release each other early.
final class KeyInjector {

    static let shared = KeyInjector()
    private init() {
        queue.setSpecific(key: queueSpecificKey, value: ())
    }

    // Logical bindings include modifiers so "A" and "Shift+A" are tracked as different held inputs.
    private struct KeyBinding: Hashable {
        let keyCode: CGKeyCode
        let modifiersRawValue: UInt
    }

    // Physical chords are posted as modifier key-downs followed by the primary key, then released in reverse order.
    private struct PhysicalChord {
        let modifierKeyCodes: [CGKeyCode]
        let primaryKeyCode: CGKeyCode?
    }

    // Logical counts track callers; physical counts track the actual keys currently held in the OS event stream.
    private var heldKeyCounts: [KeyBinding: Int] = [:]
    private var physicalKeyCounts: [CGKeyCode: Int] = [:]
    private let queue = DispatchQueue(label: "com.gamepad.keyinjector", qos: .userInteractive)
    private let queueSpecificKey = DispatchSpecificKey<Void>()

    // MARK: - Public Press/Release API

    func pressRaw(_ keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags = []) {
        let enqueuedAt = ProcessInfo.processInfo.systemUptime
        debugLatencyLog("[KeyInjector] enqueue pressRaw \(keyCode) modifiers=\(modifiers.rawValue)")
        queue.async { [self] in
            debugLatencyLog("[KeyInjector] begin pressRaw \(keyCode) queueWait=\(formatMilliseconds(ProcessInfo.processInfo.systemUptime - enqueuedAt)) modifiers=\(modifiers.rawValue)")
            let supportedModifiers = supportedModifiers(from: modifiers)
            let binding = KeyBinding(keyCode: keyCode, modifiersRawValue: supportedModifiers.rawValue)
            if let heldCount = heldKeyCounts[binding], heldCount > 0 {
                heldKeyCounts[binding] = heldCount + 1
                debugLog("[KeyInjector] pressRaw \(keyCode) modifiers=\(binding.modifiersRawValue) - already held, owners=\(heldCount + 1), skipping")
                return
            }

            let chord = physicalChord(keyCode: keyCode, modifiers: supportedModifiers)
            var acquiredKeys: [CGKeyCode] = []
            var ok = true

            for modifierKeyCode in chord.modifierKeyCodes {
                guard pressPhysicalKey(modifierKeyCode, modifiers: [], acquiredKeys: &acquiredKeys) else {
                    ok = false
                    break
                }
            }

            if ok, let primaryKeyCode = chord.primaryKeyCode {
                ok = pressPhysicalKey(primaryKeyCode, modifiers: supportedModifiers, acquiredKeys: &acquiredKeys)
            }

            if !ok {
                for acquiredKey in acquiredKeys.reversed() {
                    releasePhysicalKey(acquiredKey, modifiers: [])
                }
            }

            if ok {
                heldKeyCounts[binding] = 1
            }
            debugLog("[KeyInjector] pressRaw \(keyCode) modifiers=\(binding.modifiersRawValue) posted=\(ok)")
        }
    }

    func releaseRaw(_ keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags = []) {
        let enqueuedAt = ProcessInfo.processInfo.systemUptime
        debugLatencyLog("[KeyInjector] enqueue releaseRaw \(keyCode) modifiers=\(modifiers.rawValue)")
        queue.async { [self] in
            debugLatencyLog("[KeyInjector] begin releaseRaw \(keyCode) queueWait=\(formatMilliseconds(ProcessInfo.processInfo.systemUptime - enqueuedAt)) modifiers=\(modifiers.rawValue)")
            let supportedModifiers = supportedModifiers(from: modifiers)
            let binding = KeyBinding(keyCode: keyCode, modifiersRawValue: supportedModifiers.rawValue)
            guard let heldCount = heldKeyCounts[binding], heldCount > 0 else {
                debugLog("[KeyInjector] releaseRaw \(keyCode) modifiers=\(binding.modifiersRawValue) - not held, skipping")
                return
            }

            if heldCount > 1 {
                heldKeyCounts[binding] = heldCount - 1
                debugLog("[KeyInjector] releaseRaw \(keyCode) modifiers=\(binding.modifiersRawValue) owners=\(heldCount - 1), keeping held")
                return
            }

            heldKeyCounts.removeValue(forKey: binding)
            let chord = physicalChord(keyCode: keyCode, modifiers: supportedModifiers)
            var ok = true

            if let primaryKeyCode = chord.primaryKeyCode {
                ok = releasePhysicalKey(primaryKeyCode, modifiers: supportedModifiers) && ok
            }

            for modifierKeyCode in chord.modifierKeyCodes.reversed() {
                ok = releasePhysicalKey(modifierKeyCode, modifiers: []) && ok
            }

            debugLog("[KeyInjector] releaseRaw \(keyCode) modifiers=\(binding.modifiersRawValue) posted=\(ok)")
        }
    }

    // MARK: - Held-Key Cleanup

    func releaseAllHeldKeys() {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            releaseAllHeldKeysOnQueue()
            return
        }

        queue.sync {
            releaseAllHeldKeysOnQueue()
        }
    }

    private func releaseAllHeldKeysOnQueue() {
        let keysToRelease = physicalKeyCounts.keys.sorted { lhs, rhs in
            let lhsIsModifier = cgEventFlag(forModifierKeyCode: lhs) != nil
            let rhsIsModifier = cgEventFlag(forModifierKeyCode: rhs) != nil

            if lhsIsModifier != rhsIsModifier {
                return !lhsIsModifier
            }

            return lhs < rhs
        }
        heldKeyCounts.removeAll()

        for keyCode in keysToRelease {
            physicalKeyCounts.removeValue(forKey: keyCode)
            let ok = postEvent(keyCode: keyCode, modifiers: [], keyDown: false)
            debugLog("[KeyInjector] releaseAllHeldKeys \(keyCode) posted=\(ok)")
        }
    }

    // MARK: - Physical Event Posting

    @discardableResult
    private func pressPhysicalKey(
        _ keyCode: CGKeyCode,
        modifiers: NSEvent.ModifierFlags,
        acquiredKeys: inout [CGKeyCode]
    ) -> Bool {
        if let heldCount = physicalKeyCounts[keyCode], heldCount > 0 {
            physicalKeyCounts[keyCode] = heldCount + 1
            acquiredKeys.append(keyCode)
            debugLog("[KeyInjector] pressPhysicalKey \(keyCode) already held, owners=\(heldCount + 1), skipping")
            return true
        }

        let ok = postEvent(keyCode: keyCode, modifiers: modifiers, keyDown: true)
        if ok {
            physicalKeyCounts[keyCode] = 1
            acquiredKeys.append(keyCode)
        }
        debugLog("[KeyInjector] pressPhysicalKey \(keyCode) posted=\(ok)")
        return ok
    }

    @discardableResult
    private func releasePhysicalKey(_ keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let heldCount = physicalKeyCounts[keyCode], heldCount > 0 else {
            debugLog("[KeyInjector] releasePhysicalKey \(keyCode) - not held, skipping")
            return true
        }

        if heldCount > 1 {
            physicalKeyCounts[keyCode] = heldCount - 1
            debugLog("[KeyInjector] releasePhysicalKey \(keyCode) owners=\(heldCount - 1), keeping held")
            return true
        }

        physicalKeyCounts.removeValue(forKey: keyCode)
        let ok = postEvent(keyCode: keyCode, modifiers: modifiers, keyDown: false)
        debugLog("[KeyInjector] releasePhysicalKey \(keyCode) posted=\(ok)")
        return ok
    }

    @discardableResult
    private func postEvent(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags, keyDown: Bool) -> Bool {
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            errorLog("[KeyInjector] ERROR: CGEventSource returned nil")
            return false
        }
        guard let evt = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: keyDown) else {
            errorLog("[KeyInjector] ERROR: CGEvent creation failed for keyCode \(keyCode)")
            return false
        }
        evt.flags = cgEventFlags(from: modifiers, keyCode: keyCode, keyDown: keyDown)
        let postStartedAt = ProcessInfo.processInfo.systemUptime
        evt.post(tap: .cghidEventTap)
        let postEndedAt = ProcessInfo.processInfo.systemUptime
        debugLatencyLog("[KeyInjector] postEvent keyCode=\(keyCode) keyDown=\(keyDown) modifiers=\(modifiers.rawValue) postDuration=\(formatMilliseconds(postEndedAt - postStartedAt))")
        return true
    }

    private func formatMilliseconds(_ seconds: TimeInterval) -> String {
        String(format: "%.3fms", seconds * 1000)
    }

    // MARK: - Modifier Translation

    private func supportedModifiers(from modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        modifiers.intersection([.command, .option, .control, .shift])
    }

    private func cgEventFlags(from modifiers: NSEvent.ModifierFlags, keyCode: CGKeyCode, keyDown: Bool) -> CGEventFlags {
        var flags = heldModifierFlags()

        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if keyDown, let modifierFlag = cgEventFlag(forModifierKeyCode: keyCode) {
            flags.insert(modifierFlag)
        }

        return flags
    }

    private func heldModifierFlags() -> CGEventFlags {
        physicalKeyCounts.keys.reduce(into: CGEventFlags()) { flags, keyCode in
            if let modifierFlag = cgEventFlag(forModifierKeyCode: keyCode) {
                flags.insert(modifierFlag)
            }
        }
    }

    private func physicalChord(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> PhysicalChord {
        var modifierKeyCodes: [CGKeyCode] = []
        var genericModifiers = modifiers

        if let ownModifier = nsEventModifierFlag(forModifierKeyCode: keyCode) {
            genericModifiers.remove(ownModifier)
        }

        if genericModifiers.contains(.command) { appendUnique(55, to: &modifierKeyCodes) }
        if genericModifiers.contains(.option) { appendUnique(58, to: &modifierKeyCodes) }
        if genericModifiers.contains(.control) { appendUnique(59, to: &modifierKeyCodes) }
        if genericModifiers.contains(.shift) { appendUnique(56, to: &modifierKeyCodes) }

        if cgEventFlag(forModifierKeyCode: keyCode) != nil {
            appendUnique(keyCode, to: &modifierKeyCodes)
            return PhysicalChord(modifierKeyCodes: modifierKeyCodes, primaryKeyCode: nil)
        }

        return PhysicalChord(modifierKeyCodes: modifierKeyCodes, primaryKeyCode: keyCode)
    }

    private func appendUnique(_ keyCode: CGKeyCode, to keyCodes: inout [CGKeyCode]) {
        guard !keyCodes.contains(keyCode) else {
            return
        }

        keyCodes.append(keyCode)
    }

    private func nsEventModifierFlag(forModifierKeyCode keyCode: CGKeyCode) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55:
            return .command
        case 56, 60:
            return .shift
        case 58, 61:
            return .option
        case 59, 62:
            return .control
        default:
            return nil
        }
    }

    private func cgEventFlag(forModifierKeyCode keyCode: CGKeyCode) -> CGEventFlags? {
        switch keyCode {
        case 54, 55:
            return .maskCommand
        case 56, 60:
            return .maskShift
        case 57:
            return .maskAlphaShift
        case 58, 61:
            return .maskAlternate
        case 59, 62:
            return .maskControl
        default:
            return nil
        }
    }
}

/// Sends one-shot macOS media/brightness/system shortcuts from system-event buttons.
final class SystemEventInjector {

    static let shared = SystemEventInjector()
    private init() {}

    // Prefer opening first-party system apps for Mission Control/Launchpad, then fall back to key/system events.
    func trigger(_ event: SystemEvent) {
        switch event {
        case .missionControl:
            triggerMissionControl()
        case .brightnessDown:
            postSystemKeyTap(type: 3)
        case .brightnessUp:
            postSystemKeyTap(type: 2)
        case .volumeDown:
            postSystemKeyTap(type: 1)
        case .volumeUp:
            postSystemKeyTap(type: 0)
        case .mute:
            postSystemKeyTap(type: 7)
        case .playPause:
            postSystemKeyTap(type: 16)
        case .nextTrack:
            postSystemKeyTap(type: 17)
        case .previousTrack:
            postSystemKeyTap(type: 18)
        case .launchpad:
            guard !openSystemApplication(named: "Apps.app") else {
                return
            }
            postSystemKeyTap(type: 13)
        }
    }

    private func triggerMissionControl() {
        guard !openSystemApplication(named: "Mission Control.app") else {
            return
        }

        postShortcutTap(keyCode: 126, modifiers: .control)
    }

    private func openSystemApplication(named appName: String) -> Bool {
        let appURL = URL(fileURLWithPath: "/System/Applications").appendingPathComponent(appName)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            return false
        }

        let ok = NSWorkspace.shared.open(appURL)
        debugLog("[SystemEventInjector] open \(appName) posted=\(ok)")
        return ok
    }

    private func postShortcutTap(
        keyCode: CGKeyCode,
        modifiers: NSEvent.ModifierFlags
    ) {
        KeyInjector.shared.pressRaw(keyCode, modifiers: modifiers)
        KeyInjector.shared.releaseRaw(keyCode, modifiers: modifiers)
    }

    private func postSystemKeyTap(type: Int) {
        postSystemKey(type: type, isDown: true)
        postSystemKey(type: type, isDown: false)
    }

    private func postSystemKey(type: Int, isDown: Bool) {
        let keyState = isDown ? 0xA : 0xB
        let data1 = (type << 16) | (keyState << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyState << 8)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )?.cgEvent else {
            errorLog("[SystemEventInjector] ERROR: system event creation failed for type \(type)")
            return
        }

        event.post(tap: .cghidEventTap)
    }
}
