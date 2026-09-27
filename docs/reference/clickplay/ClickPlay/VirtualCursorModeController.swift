import Cocoa

/// Coordinates Virtual Cursor Mode event routing, activation, and emergency release.
final class VirtualCursorModeController {
    enum VirtualMouseButton {
        case left
        case right
    }

    static let shared = VirtualCursorModeController()

    static let stateDidChange = Notification.Name("VirtualCursorModeControllerStateDidChange")
    private static let escapeUnlockCount = 5
    private static let escapeSequenceMaximumGap: TimeInterval = 2
    private static let escapeKeyCode: Int64 = 53

    var onVirtualMouseDelta: ((CGPoint) -> Void)?
    var onVirtualMouseButton: ((VirtualMouseButton, Bool) -> Void)?
    var onVirtualScroll: ((CGFloat) -> Void)?
    var onModeDeactivated: (() -> Void)?

    private(set) var isModePending = false
    private(set) var isModeActive = false
    private(set) var modeCountdownSeconds = 0
    private(set) var isModeTemporarilyReleased = false
    private(set) var temporaryReleaseCountdownSeconds = 0
    private(set) var isModeAvailable = false
    private(set) var modeArmDelaySeconds = Profile.defaultVirtualCursorModeArmDelaySeconds
    private(set) var temporaryReleaseDurationSeconds = Profile.defaultVirtualCursorModeTemporaryReleaseSeconds

    private var mouseEventTap: CFMachPort?
    private var mouseEventTapRunLoopSource: CFRunLoopSource?
    private var keyboardEventTap: CFMachPort?
    private var keyboardEventTapRunLoopSource: CFRunLoopSource?
    private var modeActivationTimer: Timer?
    private var temporaryReleaseTimer: Timer?
    private var escapePressCount = 0
    private var lastEscapePressTime: TimeInterval?

    private init() {}

    deinit {
        cancelTemporaryRelease(reason: "deinit")
        deactivateMode(reason: "deinit")
        cancelPendingMode(reason: "deinit")
    }

    var hasModeState: Bool {
        isModePending || isModeActive || isModeTemporarilyReleased
    }

    func configureMode(
        isAvailable: Bool,
        armDelaySeconds: Int,
        temporaryReleaseSeconds: Int
    ) {
        isModeAvailable = isAvailable
        modeArmDelaySeconds = max(1, armDelaySeconds)
        temporaryReleaseDurationSeconds = max(1, temporaryReleaseSeconds)

        if !isAvailable {
            cancelMode(reason: "profileDisabled")
        }
    }

    @discardableResult
    func setModeEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            return armMode()
        }

        cancelPendingMode(reason: "manual")
        cancelTemporaryRelease(reason: "manual")
        deactivateMode(reason: "manual")
        return true
    }

    @discardableResult
    func toggleMode() -> Bool {
        setModeEnabled(!hasModeState)
    }

    func cancelMode(reason: String) {
        cancelPendingMode(reason: reason)
        cancelTemporaryRelease(reason: reason)
        deactivateMode(reason: reason)
    }

    @discardableResult
    func toggleTemporaryRelease() -> Bool {
        if isModeTemporarilyReleased {
            return resumeModeAfterTemporaryRelease(reason: "manual")
        }

        return temporarilyReleaseMode()
    }

    @discardableResult
    private func armMode() -> Bool {
        guard isModeAvailable else {
            return false
        }

        guard !isModeActive else {
            return true
        }

        guard !isModeTemporarilyReleased else {
            return true
        }

        guard !isModePending else {
            return true
        }

        guard installKeyboardEventTapIfNeeded() else {
            return false
        }

        isModePending = true
        modeCountdownSeconds = modeArmDelaySeconds
        resetEscapeSequence()
        scheduleModeActivationTimer()
        debugLog("[VirtualCursorMode] armed delaySeconds=\(modeArmDelaySeconds)")
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        return true
    }

    private func cancelPendingMode(reason: String) {
        guard isModePending else {
            modeActivationTimer?.invalidate()
            modeActivationTimer = nil
            return
        }

        modeActivationTimer?.invalidate()
        modeActivationTimer = nil
        isModePending = false
        modeCountdownSeconds = 0
        resetEscapeSequence()
        uninstallKeyboardEventTapIfIdle()
        debugLog("[VirtualCursorMode] disarmed reason=\(reason)")
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
    }

    private func scheduleModeActivationTimer() {
        modeActivationTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, self.isModePending else {
                timer.invalidate()
                return
            }

            self.modeCountdownSeconds = max(0, self.modeCountdownSeconds - 1)
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)

            guard self.modeCountdownSeconds <= 0 else {
                return
            }

            timer.invalidate()
            self.modeActivationTimer = nil
            self.isModePending = false
            _ = self.activateMode()
        }
        RunLoop.main.add(timer, forMode: .common)
        modeActivationTimer = timer
    }

    @discardableResult
    private func activateMode() -> Bool {
        guard !isModeActive else {
            return true
        }

        guard installMouseEventTapIfNeeded() else {
            uninstallKeyboardEventTapIfIdle()
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)
            return false
        }

        guard installKeyboardEventTapIfNeeded() else {
            uninstallMouseEventTapIfIdle()
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)
            return false
        }

        isModeActive = true
        modeCountdownSeconds = 0
        resetEscapeSequence()
        debugLog("[VirtualCursorMode] activated")
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        return true
    }

    private func deactivateMode(reason: String) {
        guard isModeActive else { return }

        isModeActive = false
        resetEscapeSequence()
        debugLog("[VirtualCursorMode] deactivated reason=\(reason)")
        onModeDeactivated?()
        uninstallMouseEventTapIfIdle()
        uninstallKeyboardEventTapIfIdle()
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
    }

    @discardableResult
    private func temporarilyReleaseMode() -> Bool {
        guard isModeActive else {
            return false
        }

        isModeActive = false
        isModeTemporarilyReleased = true
        temporaryReleaseCountdownSeconds = temporaryReleaseDurationSeconds
        resetEscapeSequence()
        debugLog("[VirtualCursorMode] temporarilyReleased durationSeconds=\(temporaryReleaseDurationSeconds)")
        onModeDeactivated?()
        uninstallMouseEventTapIfIdle()
        scheduleTemporaryReleaseTimer()
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        return true
    }

    @discardableResult
    private func resumeModeAfterTemporaryRelease(reason: String) -> Bool {
        guard isModeTemporarilyReleased else {
            return true
        }

        temporaryReleaseTimer?.invalidate()
        temporaryReleaseTimer = nil
        isModeTemporarilyReleased = false
        temporaryReleaseCountdownSeconds = 0
        resetEscapeSequence()
        debugLog("[VirtualCursorMode] temporaryReleaseEnded reason=\(reason)")

        let activated = activateMode()
        if !activated {
            uninstallKeyboardEventTapIfIdle()
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        }
        return activated
    }

    private func cancelTemporaryRelease(reason: String) {
        guard isModeTemporarilyReleased else {
            temporaryReleaseTimer?.invalidate()
            temporaryReleaseTimer = nil
            temporaryReleaseCountdownSeconds = 0
            return
        }

        temporaryReleaseTimer?.invalidate()
        temporaryReleaseTimer = nil
        isModeTemporarilyReleased = false
        temporaryReleaseCountdownSeconds = 0
        resetEscapeSequence()
        debugLog("[VirtualCursorMode] temporaryReleaseCancelled reason=\(reason)")
        uninstallKeyboardEventTapIfIdle()
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
    }

    private func scheduleTemporaryReleaseTimer() {
        temporaryReleaseTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, self.isModeTemporarilyReleased else {
                timer.invalidate()
                return
            }

            self.temporaryReleaseCountdownSeconds = max(0, self.temporaryReleaseCountdownSeconds - 1)
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)

            guard self.temporaryReleaseCountdownSeconds <= 0 else {
                return
            }

            timer.invalidate()
            self.temporaryReleaseTimer = nil
            _ = self.resumeModeAfterTemporaryRelease(reason: "timer")
        }
        RunLoop.main.add(timer, forMode: .common)
        temporaryReleaseTimer = timer
    }

    @discardableResult
    private func installMouseEventTapIfNeeded() -> Bool {
        guard mouseEventTap == nil else {
            return true
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.mouseEventMask,
            callback: Self.mouseEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            errorLog("[VirtualCursorMode] ERROR: mouseEventTapCreationFailed")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        mouseEventTap = tap
        mouseEventTapRunLoopSource = source
        debugLog("[VirtualCursorMode] mouseEventTapInstalled")
        return true
    }

    private func uninstallMouseEventTapIfIdle() {
        guard !isModeActive else {
            return
        }

        uninstallMouseEventTap()
    }

    private func uninstallMouseEventTap() {
        guard mouseEventTap != nil || mouseEventTapRunLoopSource != nil else {
            return
        }

        if let mouseEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), mouseEventTapRunLoopSource, .commonModes)
            self.mouseEventTapRunLoopSource = nil
        }

        if let mouseEventTap {
            CGEvent.tapEnable(tap: mouseEventTap, enable: false)
            self.mouseEventTap = nil
        }

        debugLog("[VirtualCursorMode] mouseEventTapUninstalled")
    }

    @discardableResult
    private func installKeyboardEventTapIfNeeded() -> Bool {
        guard keyboardEventTap == nil else {
            return true
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.keyboardEventMask,
            callback: Self.keyboardEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            errorLog("[VirtualCursorMode] ERROR: keyboardEventTapCreationFailed")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        keyboardEventTap = tap
        keyboardEventTapRunLoopSource = source
        debugLog("[VirtualCursorMode] keyboardEventTapInstalled")
        return true
    }

    private func uninstallKeyboardEventTapIfIdle() {
        guard !isModePending, !isModeActive, !isModeTemporarilyReleased else {
            return
        }

        uninstallKeyboardEventTap()
    }

    private func uninstallKeyboardEventTap() {
        guard keyboardEventTap != nil || keyboardEventTapRunLoopSource != nil else {
            return
        }

        if let keyboardEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyboardEventTapRunLoopSource, .commonModes)
            self.keyboardEventTapRunLoopSource = nil
        }

        if let keyboardEventTap {
            CGEvent.tapEnable(tap: keyboardEventTap, enable: false)
            self.keyboardEventTap = nil
        }

        debugLog("[VirtualCursorMode] keyboardEventTapUninstalled")
    }

    private static var mouseEventMask: CGEventMask {
        eventMask(for: .mouseMoved)
            | eventMask(for: .leftMouseDown)
            | eventMask(for: .leftMouseUp)
            | eventMask(for: .leftMouseDragged)
            | eventMask(for: .rightMouseDown)
            | eventMask(for: .rightMouseUp)
            | eventMask(for: .rightMouseDragged)
            | eventMask(for: .otherMouseDown)
            | eventMask(for: .otherMouseUp)
            | eventMask(for: .otherMouseDragged)
            | eventMask(for: .scrollWheel)
    }

    private static var keyboardEventMask: CGEventMask {
        eventMask(for: .keyDown)
    }

    private static let mouseEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<VirtualCursorModeController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handleMouseEventTap(type: type, event: event)
    }

    private static let keyboardEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<VirtualCursorModeController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handleKeyboardEventTap(type: type, event: event)
    }

    private static func eventMask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1 << type.rawValue)
    }

    private func handleMouseEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            errorLog("[VirtualCursorMode] mouseEventTapDisabled type=\(type.rawValue); reenable=true")
            if let mouseEventTap {
                CGEvent.tapEnable(tap: mouseEventTap, enable: true)
            }
            return nil

        default:
            routeMouseEvent(type: type, event: event)
            return isModeActive ? nil : Unmanaged.passUnretained(event)
        }
    }

    private func routeMouseEvent(type: CGEventType, event: CGEvent) {
        guard isModeActive else {
            return
        }

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let deltaX = CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
            let deltaY = CGFloat(-event.getIntegerValueField(.mouseEventDeltaY))
            guard deltaX != 0 || deltaY != 0 else {
                return
            }

            onVirtualMouseDelta?(CGPoint(x: deltaX, y: deltaY))

        case .leftMouseDown:
            onVirtualMouseButton?(.left, true)
        case .leftMouseUp:
            onVirtualMouseButton?(.left, false)
        case .rightMouseDown:
            onVirtualMouseButton?(.right, true)
        case .rightMouseUp:
            onVirtualMouseButton?(.right, false)
        case .scrollWheel:
            let delta = CGFloat(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            onVirtualScroll?(delta)
        default:
            return
        }
    }

    private func handleKeyboardEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            errorLog("[VirtualCursorMode] keyboardEventTapDisabled type=\(type.rawValue); reenable=true")
            if let keyboardEventTap {
                CGEvent.tapEnable(tap: keyboardEventTap, enable: true)
            }
            return nil

        case .keyDown:
            handleKeyDown(event)
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) {
        guard hasModeState else {
            resetEscapeSequence()
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Self.escapeKeyCode else {
            resetEscapeSequence()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let lastEscapePressTime,
           now - lastEscapePressTime > Self.escapeSequenceMaximumGap {
            escapePressCount = 0
        }

        escapePressCount += 1
        lastEscapePressTime = now
        debugLog("[VirtualCursorMode] escapeUnlockProgress count=\(escapePressCount)")

        guard escapePressCount >= Self.escapeUnlockCount else {
            return
        }

        cancelPendingMode(reason: "escape")
        cancelTemporaryRelease(reason: "escape")
        deactivateMode(reason: "escape")
    }

    private func resetEscapeSequence() {
        escapePressCount = 0
        lastEscapePressTime = nil
    }

}
