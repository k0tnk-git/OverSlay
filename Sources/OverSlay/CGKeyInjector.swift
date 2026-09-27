import AppKit
import Carbon.HIToolbox
import OverSlayCore

// Adapted from ClickPlay ba12e003 (Apache-2.0); see THIRD_PARTY_NOTICES.md.

final class CGKeyInjector: InputSink, MacroSink {
    static let eventMarker: Int64 = 0x4F766572536C6179
    private let queue = DispatchQueue(label: "io.github.k0tnk-git.OverSlay.key-injector", qos: .userInteractive)
    private var physicalCounts: [UInt16: Int] = [:]
    private var logicalCounts: [KeyBinding: Int] = [:]
    private var pendingPulses: [UUID: KeyBinding] = [:]


    func press(_ binding: KeyBinding) { queue.async { [weak self] in self?.pressOnQueue(binding) } }
    func release(_ binding: KeyBinding) { queue.async { [weak self] in self?.releaseOnQueue(binding) } }
    func releaseAll() { queue.sync { releaseAllOnQueue() } }

    // Target is captured before enqueueing. Queue-local sessions own only macro acquisitions.
    private var macroRun: UUID?
    private var macroTarget: pid_t?
    private var macroOwners: [(UUID, KeyAction)] = []

    func beginMacro(run: UUID) {
        let target = NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async { [self] in
            macroRun = run; macroTarget = target
        }
    }

    private func macroReady(_ run: UUID) -> Bool {
        guard macroRun == run, AXIsProcessTrusted(), let target = macroTarget,
              target != ProcessInfo.processInfo.processIdentifier else { return false }
        // Query the system on the injection queue without synchronously calling AppKit's main thread.
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        var pid: pid_t = 0
        return AXUIElementGetPid(value as! AXUIElement, &pid) == .success && pid == target
    }

    func macroPress(_ action: KeyAction, owner: UUID, run: UUID, latestStart: TimeInterval?, completion: @escaping (MacroError?) -> Void) {
        queue.async { [self] in
            guard macroReady(run) else { DispatchQueue.main.async { completion(.targetChanged) }; return }
            let inherited = Set(macroOwners.flatMap { $0.1.bindings.flatMap { physicalChord(for: $0) } })
            let expected = Set(action.bindings.flatMap { physicalChord(for: $0) }).union(inherited)
            let physicalModifiers: [UInt16] = [54, 55, 56, 60, 58, 61, 59, 62]
            let unexpected = physicalCounts.keys.contains { modifierFlag($0) != nil && !expected.contains($0) }
                || physicalModifiers.contains { CGEventSource.keyState(.hidSystemState, key: $0) && !expected.contains($0) }
            let primaryConflict = action.bindings.contains { binding in
                modifierFlag(binding.keyCode) == nil && (physicalCounts[binding.keyCode, default: 0] > 0
                    || CGEventSource.keyState(.hidSystemState, key: binding.keyCode))
            }
            guard !unexpected, !primaryConflict else { DispatchQueue.main.async { completion(.inputConflict) }; return }
            if let latestStart, ProcessInfo.processInfo.systemUptime > latestStart {
                DispatchQueue.main.async { completion(.timingOverrun) }; return
            }
            var acquired: [KeyBinding] = []
            // Explicit modifier keys must precede primary keys regardless of picker order.
            let ordered = action.macroChord.bindings
            for binding in ordered {
                guard pressOnQueue(binding) else {
                    for prior in acquired.reversed() { releaseOnQueue(prior) }
                    DispatchQueue.main.async { completion(.deliveryFailed) }; return
                }
                acquired.append(binding)
            }
            macroOwners.append((owner, KeyAction(bindings: ordered)))
            DispatchQueue.main.async { completion(nil) }
        }
    }

    func macroRelease(owner: UUID, run: UUID, completion: @escaping () -> Void) {
        queue.async { [self] in
            if macroRun == run, let index = macroOwners.firstIndex(where: { $0.0 == owner }) {
                let action = macroOwners.remove(at: index).1
                for binding in action.bindings.reversed() { releaseOnQueue(binding) }
            }
            DispatchQueue.main.async { completion() }
        }
    }

    func macroText(_ character: String, run: UUID, completion: @escaping (MacroError?) -> Void) {
        queue.async { [self] in
            guard macroReady(run) else { DispatchQueue.main.async { completion(.targetChanged) }; return }
            let mods: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            guard physicalCounts.isEmpty, CGEventSource.flagsState(.hidSystemState).intersection(mods).isEmpty else {
                DispatchQueue.main.async { completion(.inputConflict) }; return
            }
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                DispatchQueue.main.async { completion(.deliveryFailed) }; return
            }
            let units = Array(character.utf16)
            for event in [down, up] {
                event.flags = []
                units.withUnsafeBufferPointer { buffer in
                    if let base = buffer.baseAddress { event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base) }
                }
                event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
                event.post(tap: .cghidEventTap)
            }
            DispatchQueue.main.async { completion(nil) }
        }
    }

    func cancelMacro(run: UUID) {
        queue.async { [self] in
            guard macroRun == run else { return }
            macroRun = nil; macroTarget = nil
            for (_, action) in macroOwners.reversed() {
                for binding in action.bindings.reversed() { releaseOnQueue(binding) }
            }
            macroOwners.removeAll()
        }
    }
    func pulse(_ binding: KeyBinding, durationMilliseconds: Int = 33) {
        queue.async { [weak self] in
            guard let self else { return }
            let id = UUID()
            self.pendingPulses[id] = binding
            self.pressOnQueue(binding)
            self.queue.asyncAfter(deadline: .now() + .milliseconds(max(1, durationMilliseconds))) { [weak self] in
                guard let self, let binding = self.pendingPulses.removeValue(forKey: id) else { return }
                self.releaseOnQueue(binding)
            }
        }
    }

    @discardableResult private func pressOnQueue(_ binding: KeyBinding) -> Bool {
        let logical = logicalCounts[binding, default: 0]
        if logical > 0 { logicalCounts[binding] = logical + 1; return true }
        var acquired: [UInt16] = []
        for keyCode in physicalChord(for: binding) {
            let count = physicalCounts[keyCode, default: 0]
            physicalCounts[keyCode] = count + 1
            if count == 0 && !post(keyCode: keyCode, down: true) {
                physicalCounts.removeValue(forKey: keyCode)
                for code in acquired.reversed() {
                    let remaining = physicalCounts[code, default: 1] - 1
                    if remaining == 0 { physicalCounts.removeValue(forKey: code); post(keyCode: code, down: false) }
                    else { physicalCounts[code] = remaining }
                }
                return false
            }
            acquired.append(keyCode)
        }
        logicalCounts[binding] = 1
        return true
    }
    private func releaseOnQueue(_ binding: KeyBinding) {
        guard let logical = logicalCounts[binding], logical > 0 else { return }
        if logical > 1 { logicalCounts[binding] = logical - 1; return }
        logicalCounts.removeValue(forKey: binding)
        for keyCode in physicalChord(for: binding).reversed() {
            guard let count = physicalCounts[keyCode], count > 0 else { continue }
            if count == 1 { physicalCounts.removeValue(forKey: keyCode); post(keyCode: keyCode, down: false) }
            else { physicalCounts[keyCode] = count - 1 }
        }
    }

    private func releaseAllOnQueue() {
        macroRun = nil; macroTarget = nil; macroOwners.removeAll()
        pendingPulses.removeAll()
        let keys = physicalCounts.keys.sorted {
            let left = modifierFlag($0) != nil
            let right = modifierFlag($1) != nil
            return left == right ? $0 < $1 : !left
        }
        for keyCode in keys {
            physicalCounts.removeValue(forKey: keyCode)
            post(keyCode: keyCode, down: false)
        }
        logicalCounts.removeAll()
    }

    private func physicalChord(for binding: KeyBinding) -> [UInt16] {
        var result: [UInt16] = []
        let flags = NSEvent.ModifierFlags(rawValue: UInt(binding.modifiers))
        if flags.contains(.control) { result.append(UInt16(kVK_Control)) }
        if flags.contains(.option) { result.append(UInt16(kVK_Option)) }
        if flags.contains(.shift) { result.append(UInt16(kVK_Shift)) }
        if flags.contains(.command) { result.append(UInt16(kVK_Command)) }
        if !result.contains(binding.keyCode) { result.append(binding.keyCode) }
        return result
    }

    private func modifierFlag(_ keyCode: UInt16) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        default: return nil
        }
    }

    @discardableResult private func post(keyCode: UInt16, down: Bool) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down) else { return false }
        event.flags = physicalCounts.keys.reduce(CGEventFlags()) { flags, code in
            guard let flag = modifierFlag(code) else { return flags }
            return flags.union(flag)
        }
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
        event.post(tap: .cghidEventTap)
        return true
    }
}
