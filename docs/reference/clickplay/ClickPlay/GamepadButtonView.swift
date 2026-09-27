import Cocoa
import Darwin

private enum BackgroundCursorHiding {
    private typealias MainConnectionIDFunction = @convention(c) () -> Int32
    private typealias SetConnectionPropertyFunction = @convention(c) (
        Int32,
        Int32,
        UnsafeRawPointer?,
        UnsafeRawPointer?
    ) -> Int32

    private struct Symbols {
        let frameworkHandle: UnsafeMutableRawPointer
        let mainConnectionID: MainConnectionIDFunction
        let setConnectionProperty: SetConnectionPropertyFunction
    }

    private static let symbols: Symbols? = {
        let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let frameworkHandle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL),
              let mainConnectionIDSymbol = dlsym(frameworkHandle, "CGSMainConnectionID"),
              let setConnectionPropertySymbol = dlsym(frameworkHandle, "CGSSetConnectionProperty") else {
            return nil
        }

        return Symbols(
            frameworkHandle: frameworkHandle,
            mainConnectionID: unsafeBitCast(
                mainConnectionIDSymbol,
                to: MainConnectionIDFunction.self
            ),
            setConnectionProperty: unsafeBitCast(
                setConnectionPropertySymbol,
                to: SetConnectionPropertyFunction.self
            )
        )
    }()

    static func setEnabled(_ enabled: Bool) -> Bool {
        guard let symbols else {
            return false
        }

        let connectionID = symbols.mainConnectionID()
        let property = Unmanaged.passUnretained("SetsCursorInBackground" as CFString).toOpaque()
        let value = Unmanaged.passUnretained(enabled ? kCFBooleanTrue : kCFBooleanFalse).toOpaque()
        return symbols.setConnectionProperty(connectionID, connectionID, property, value) == 0
    }
}

struct JoystickCaptureHUDState: Equatable {
    enum ActionAccent: Equatable {
        case toggleHold
        case turbo
        case action
    }

    struct Axis: Equatable {
        var label: String
        var isActive: Bool
    }

    struct MappingRow: Equatable {
        var title: String
        var value: String
        var isActive: Bool
        var accent: ActionAccent?
    }

    var layerText: String
    var up: Axis
    var down: Axis
    var left: Axis
    var right: Axis
    var rows: [MappingRow]
}

/// Draws a single on-screen gamepad control and maps mouse gestures into keyboard, system, or joystick actions.
final class GamepadButtonView: NSView {

    /// Lightweight centered text view that lets the outer button layer keep ownership of shape and hit testing.
    private final class CenteredLabelView: NSView {
        var stringValue = "" {
            didSet { needsDisplay = true }
        }
        var font: NSFont = .systemFont(ofSize: 11) {
            didSet { needsDisplay = true }
        }
        var textColor: NSColor = .white {
            didSet { needsDisplay = true }
        }

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attributedLabel = NSAttributedString(
                string: stringValue,
                attributes: [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle,
                ]
            )
            let measuredSize = attributedLabel.size()
            let drawRect = CGRect(
                x: 2,
                y: max(0, bounds.midY - ceil(measuredSize.height) / 2),
                width: max(0, bounds.width - 4),
                height: ceil(measuredSize.height)
            )
            attributedLabel.draw(in: drawRect)
        }
    }

    // Press sources are tracked independently so a held main key, joystick click, and scroll action do not collide.
    private enum PressSource {
        case primary
        case secondary
        case joystickLeftClick
        case joystickRightClick
        case joystickScrollUp
        case joystickScrollDown
    }

    private enum ActiveModeOutline: Equatable {
        case toggleHold
        case turbo
        case dwellAction
    }

    private enum OutlineState: Equatable {
        case none
        case hover
        case active(ActiveModeOutline)
    }

    private enum FillState: Equatable {
        case standard
        case currentSubProfile
        case pressed
    }

    private struct VisualPalette {
        let baseColor: NSColor
        let standardFillColor: CGColor
        let currentSubProfileFillColor: CGColor
        let pressedFillColor: CGColor
        let hoverOutlineColor: CGColor
        let toggleHoldOutlineColor: CGColor
        let turboOutlineColor: CGColor
        let dwellActionOutlineColor: CGColor
    }

    private struct ButtonVisualState: Equatable {
        let isJoystick: Bool
        let fillState: FillState
        let visualScale: CGFloat
        let outlineState: OutlineState
        let joystickOffset: CGPoint
        let isJoystickCaptured: Bool
        let isJoystickDragActive: Bool
        let lockedJoystickDirection: JoystickDirection?
    }

    // Each source carries its own pressed bindings and timers for toggle/turbo/sequence behavior.
    private final class PressState {
        var pressedBinding: (keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags)?
        var pressedBindings: [(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags)] = []
        var isPressed = false
        var pressedStartedAt: TimeInterval?
        var autoReleaseWorkItem: DispatchWorkItem?
        var sequenceRepeatWorkItem: DispatchWorkItem?
        var sequentialStepWorkItem: DispatchWorkItem?
        var sequentialPressedBinding: (keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags)?
        var sequentialGeneration: UInt64 = 0
        var isSequentialRepeating = false
        var turboStepWorkItem: DispatchWorkItem?
        var turboPressedBindings: [(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags)] = []
        var turboGeneration: UInt = 0
    }

    // Resolved input normalizes button config plus sub-profile context into the bindings used by press handlers.
    private struct ResolvedInput {
        let bindings: [ButtonKeyBinding]
        let mode: ButtonInteractionMode
        let multiKeyActivationMode: MultiKeyActivationMode
        let turboClicksPerSecond: Int
    }

    private enum JoystickDirection: CaseIterable, Hashable {
        case up
        case upRight
        case right
        case downRight
        case down
        case downLeft
        case left
        case upLeft
    }

    private struct JoystickBinding: Hashable {
        let keyCode: CGKeyCode
        let modifiersRawValue: UInt

        var modifiers: NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(rawValue: modifiersRawValue)
        }
    }

    private enum JoystickVerticalDirection {
        case up
        case down
    }

    private enum JoystickHorizontalDirection {
        case left
        case right
    }

    private enum JoystickScrollDirection {
        case up
        case down
    }

    private enum JoystickHUDControl: Hashable {
        case rightClick
        case scrollUp
        case scrollDown
    }

    // Timing and movement constants tune joystick feel without changing the key-injection contract.
    private static let systemEventHighlightDuration = TurboConfiguration.tapDuration
    private static let joystickDeadzoneRadius: CGFloat = 18
    private static let joystickIdleReturnDelay: TimeInterval = 0.075
    private static let joystickCardinalDominanceRatio: CGFloat = 1.75
    private static let joystickMinimumDeltaForAxisReset: CGFloat = 0.5
    private static let joystickScrollActivationInterval: TimeInterval = 0.18
    private static let joystickNestedLayerScrollSuppressionDuration: TimeInterval = 0.1
    private static let joystickAxisLockEdgeThreshold: CGFloat = 0.88
    private static let joystickAxisUnlockMovementThreshold: CGFloat = 1.5
    private static let joystickAxisUnlockMovementPause: TimeInterval = 0.25

    // Persistent configuration comes from the active profile; runtime flags mirror current mouse/joystick state.
    let button: GamepadButton
    private var config: ButtonConfig
    private var compatibilityModeEnabled: Bool
    private var compatibilityModeDurationMilliseconds: Int
    private var activeSubProfileID: UUID?
    private let primaryState = PressState()
    private let secondaryState = PressState()
    private let joystickLeftClickState = PressState()
    private let joystickRightClickState = PressState()
    private let joystickScrollUpState = PressState()
    private let joystickScrollDownState = PressState()
    private let shapeLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()
    private let joystickOuterLayer = CAShapeLayer()
    private let joystickKnobLayer = CAShapeLayer()
    private let joystickLockIndicatorLayer = CALayer()
    private let joystickLockIndicatorRingLayer = CAShapeLayer()
    private let joystickLockIndicatorShackleLayer = CAShapeLayer()
    private let joystickLockIndicatorBodyLayer = CAShapeLayer()
    private let label = CenteredLabelView(frame: .zero)
    private let symbolImageView = NSImageView(frame: .zero)
    private var isHovered = false
    private var isSwitchPressed = false
    private var isSystemEventPressed = false
    private var isDwellActionPressed = false
    private var isDwellActionActive = false
    private var isJoystickCaptured = false
    private var isVirtualJoystickCaptured = false
    private var virtualJoystickRightClickReturnedToPreviousLayer = false
    private var isJoystickDragActive = false
    private var activeJoystickLayerIndex = 0
    private var joystickOffset = CGPoint.zero
    private var activeJoystickDirection: JoystickDirection?
    private var activeJoystickBindings: [JoystickBinding] = []
    private var heldJoystickBindings: [JoystickBinding] = []
    private var pendingJoystickReleaseWorkItems: [JoystickBinding: DispatchWorkItem] = [:]
    private var pendingJoystickReleaseGenerations: [JoystickBinding: UInt64] = [:]
    private var joystickReleaseGeneration: UInt64 = 0
    private var lockedJoystickDirection: JoystickDirection?
    private var joystickEventTap: CFMachPort?
    private var joystickEventTapRunLoopSource: CFRunLoopSource?
    private var joystickIdleReturnWorkItem: DispatchWorkItem?
    private var joystickIdleReturnGeneration: UInt64 = 0
    private var lastJoystickMovementTime: TimeInterval = 0
    private var isJoystickCursorHidden = false
    private var isJoystickCaptureReleasePending = false
    private var pendingJoystickCaptureReleaseShouldWarp = false
    private var lastJoystickScrollActivation: (direction: JoystickScrollDirection, time: TimeInterval)?
    private var nestedLayerScrollSuppression: (direction: JoystickScrollDirection, time: TimeInterval)?
    private var joystickAxisLockWorkItem: DispatchWorkItem?
    private var pendingJoystickAxisLockDirection: JoystickDirection?
    private var pendingJoystickAxisLockStartedAt: TimeInterval?
    private var lastJoystickAxisLockMovementTime: TimeInterval?
    private var requiresJoystickAxisLockNeutralBeforeLock = false
    private var flashedJoystickHUDControls = Set<JoystickHUDControl>()
    private var joystickHUDFlashWorkItems: [JoystickHUDControl: DispatchWorkItem] = [:]
    private var trackingArea: NSTrackingArea?
    private var visualScale: CGFloat = 1
    private var visualPalette: VisualPalette?
    private var lastAppliedVisualState: ButtonVisualState?
    private var lastPublishedJoystickCaptureHUDState: JoystickCaptureHUDState?
    var onJoystickCaptureChanged: ((Bool) -> Void)?
    var onJoystickCaptureHUDChanged: ((JoystickCaptureHUDState?) -> Void)?
    var onDwellActionToggled: ((GamepadButton, DwellActionConfig) -> Bool)?

    init(
        button: GamepadButton,
        config: ButtonConfig,
        compatibilityModeEnabled: Bool,
        compatibilityModeDurationMilliseconds: Int,
        activeSubProfileID: UUID?
    ) {
        self.button = button
        self.config = config
        self.compatibilityModeEnabled = compatibilityModeEnabled
        self.compatibilityModeDurationMilliseconds = Profile.normalizedCompatibilityModeDurationMilliseconds(
            compatibilityModeDurationMilliseconds
        )
        self.activeSubProfileID = activeSubProfileID
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup and Configuration

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        shapeLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        shapeLayer.strokeColor = nil
        shapeLayer.lineWidth = 0
        outlineLayer.contentsScale = shapeLayer.contentsScale
        outlineLayer.fillColor = NSColor.clear.cgColor
        layer?.addSublayer(shapeLayer)
        layer?.addSublayer(outlineLayer)
        joystickOuterLayer.contentsScale = shapeLayer.contentsScale
        joystickKnobLayer.contentsScale = shapeLayer.contentsScale
        joystickLockIndicatorLayer.contentsScale = shapeLayer.contentsScale
        joystickLockIndicatorLayer.masksToBounds = false
        joystickLockIndicatorRingLayer.contentsScale = shapeLayer.contentsScale
        joystickLockIndicatorShackleLayer.contentsScale = shapeLayer.contentsScale
        joystickLockIndicatorBodyLayer.contentsScale = shapeLayer.contentsScale
        joystickLockIndicatorLayer.addSublayer(joystickLockIndicatorRingLayer)
        joystickLockIndicatorLayer.addSublayer(joystickLockIndicatorShackleLayer)
        joystickLockIndicatorLayer.addSublayer(joystickLockIndicatorBodyLayer)
        layer?.addSublayer(joystickOuterLayer)
        layer?.addSublayer(joystickKnobLayer)
        layer?.addSublayer(joystickLockIndicatorLayer)

        symbolImageView.imageScaling = .scaleProportionallyDown
        symbolImageView.contentTintColor = displayTextColor
        symbolImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolImageView)
        label.stringValue = config.resolvedDisplayLabel
        label.font = displayTextFont
        label.textColor = displayTextColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            symbolImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolImageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.58),
            symbolImageView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.58),
        ])
        refreshVisualPalette()
        updateSystemEventSymbol()

        updateAppearance(animated: false)
        debugLog("[Button \(button.rawValue)] Created frame will be set by parent, keyBindings=\(config.keyBindings.map(\.keyCode))")
    }

    override func layout() {
        super.layout()
        updateShapePath()
        updateSystemEventSymbol()
        updateJoystickLayers(baseColor: NSColor(hex: config.colorHex))
    }

    func updateConfig(
        _ newConfig: ButtonConfig,
        compatibilityModeEnabled: Bool,
        compatibilityModeDurationMilliseconds: Int,
        activeSubProfileID: UUID?
    ) {
        let wasJoystick = isJoystick
        releaseIfNeeded()
        config = newConfig
        self.compatibilityModeEnabled = compatibilityModeEnabled
        self.compatibilityModeDurationMilliseconds = Profile.normalizedCompatibilityModeDurationMilliseconds(
            compatibilityModeDurationMilliseconds
        )
        self.activeSubProfileID = activeSubProfileID
        refreshVisualPalette()
        lastAppliedVisualState = nil
        if wasJoystick || isJoystick {
            resetJoystickRuntimeState()
        }
        if !isDwellAction {
            isDwellActionPressed = false
            isDwellActionActive = false
        }
        label.stringValue = config.resolvedDisplayLabel
        label.font = displayTextFont
        label.textColor = displayTextColor
        symbolImageView.contentTintColor = displayTextColor
        updateSystemEventSymbol()
        updateAppearance(animated: false)
    }

    func releaseIfNeeded() {
        releaseJoystickCapture(warpCursorToCenter: false)
        releaseJoystickDrag()
        isHovered = false
        isSystemEventPressed = false
        isDwellActionPressed = false

        if isSubProfileSwitch {
            isSwitchPressed = false
            updateAppearance(animated: false)
            return
        }

        releaseState(primaryState)
        releaseState(secondaryState)
        updateAppearance(animated: false)
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Mouse Handling

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        debugLog("[Button \(button.rawValue)] acceptsFirstMouse called -> true")
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isJoystick {
            return bounds.contains(point) ? self : nil
        }

        return containsInteractivePoint(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseDown(with event: NSEvent) {
        updateHoverState(with: event, animated: true)
        guard containsInteractivePoint(convert(event.locationInWindow, from: nil)) else {
            return
        }

        debugLog("[Button \(button.rawValue)] mouseDown")
        debugLatencyLog("[Button \(button.rawValue)] mouseDown", eventTimestamp: event.timestamp)
        if config.type == .joystick {
            handleJoystickMouseDown(with: event)
            return
        }

        if isSubProfileSwitch {
            handleSubProfileSwitchPressStarted()
            return
        }

        if isSystemEvent {
            handleSystemEventPressStarted()
            return
        }

        if isDwellAction {
            handleDwellActionPressStarted()
            return
        }

        handlePressStarted(source: .primary)
    }

    override func mouseUp(with event: NSEvent) {
        debugLog("[Button \(button.rawValue)] mouseUp")
        debugLatencyLog("[Button \(button.rawValue)] mouseUp", eventTimestamp: event.timestamp)
        if config.type == .joystick {
            handleJoystickMouseUp(with: event)
            return
        }

        if isSubProfileSwitch {
            handleSubProfileSwitchPressEnded(inside: containsInteractivePoint(convert(event.locationInWindow, from: nil)))
            return
        }

        if isSystemEvent {
            return
        }

        if isDwellAction {
            handleDwellActionPressEnded(inside: containsInteractivePoint(convert(event.locationInWindow, from: nil)))
            return
        }

        handlePressEnded(source: .primary)
    }

    override func rightMouseDown(with event: NSEvent) {
        updateHoverState(with: event, animated: true)
        if config.type == .joystick {
            if isJoystickCaptureMode {
                if isJoystickCaptured {
                    if !returnToPreviousJoystickLayer() {
                        releaseJoystickCapture(warpCursorToCenter: true)
                    }
                }
            } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
                guard activeJoystickLayerIndex == 0 else {
                    _ = returnToPreviousJoystickLayer()
                    return
                }

                debugLog("[Button \(button.rawValue)] joystickRightMouseDown")
                debugLatencyLog("[Button \(button.rawValue)] joystickRightMouseDown", eventTimestamp: event.timestamp)
                handlePressStarted(source: .joystickRightClick)
            }
            return
        }

        guard containsInteractivePoint(convert(event.locationInWindow, from: nil)), !isSubProfileSwitch, !isSystemEvent, !isDwellAction else {
            return
        }

        debugLog("[Button \(button.rawValue)] rightMouseDown")
        debugLatencyLog("[Button \(button.rawValue)] rightMouseDown", eventTimestamp: event.timestamp)
        handlePressStarted(source: .secondary)
    }

    override func rightMouseUp(with event: NSEvent) {
        if config.type == .joystick {
            if isJoystickClickDragMode, activeJoystickLayerIndex == 0 {
                debugLog("[Button \(button.rawValue)] joystickRightMouseUp")
                debugLatencyLog("[Button \(button.rawValue)] joystickRightMouseUp", eventTimestamp: event.timestamp)
                handlePressEnded(source: .joystickRightClick)
            }
            return
        }

        guard !isSubProfileSwitch, !isSystemEvent, !isDwellAction else {
            return
        }

        debugLog("[Button \(button.rawValue)] rightMouseUp")
        debugLatencyLog("[Button \(button.rawValue)] rightMouseUp", eventTimestamp: event.timestamp)
        handlePressEnded(source: .secondary)
    }

    override func mouseDragged(with event: NSEvent) {
        updateHoverState(with: event, animated: true)
        if config.type == .joystick {
            handleJoystickMouseDragged(with: event)
            return
        }

        if isSubProfileSwitch {
            let inside = containsInteractivePoint(convert(event.locationInWindow, from: nil))
            if inside != isSwitchPressed {
                isSwitchPressed = inside
                updateAppearance(animated: true)
            }
            return
        }

        if isSystemEvent {
            return
        }

        if isDwellAction {
            let inside = containsInteractivePoint(convert(event.locationInWindow, from: nil))
            if inside != isDwellActionPressed {
                isDwellActionPressed = inside
                updateAppearance(animated: true)
            }
            return
        }

        handleDrag(source: .primary, event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        updateHoverState(with: event, animated: true)
        if config.type == .joystick {
            if isJoystickCaptureMode, isJoystickCaptured {
                if !returnToPreviousJoystickLayer() {
                    releaseJoystickCapture(warpCursorToCenter: true)
                }
            }
            return
        }

        guard !isSubProfileSwitch, !isSystemEvent, !isDwellAction else {
            return
        }

        handleDrag(source: .secondary, event: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoverState(with: event, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        debugLog("[Button \(button.rawValue)] mouseExited")
        setHovered(false, animated: true)
        if config.type == .joystick {
            return
        }

        if isSubProfileSwitch {
            if isSwitchPressed {
                isSwitchPressed = false
                updateAppearance(animated: true)
            }
            return
        }

        if isSystemEvent {
            return
        }

        if isDwellAction {
            if isDwellActionPressed {
                isDwellActionPressed = false
                updateAppearance(animated: true)
            }
            return
        }

        releaseMomentaryOnExit(source: .primary)
        releaseMomentaryOnExit(source: .secondary)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverState(with: event, animated: true)
    }

    @discardableResult
    func handleVirtualScroll(delta: CGFloat) -> Bool {
        guard canHandleJoystickScroll, delta != 0 else {
            return false
        }

        return handleJoystickScrollDelta(delta)
    }

    override func scrollWheel(with event: NSEvent) {
        if canHandleJoystickScroll, handleJoystickScrollDelta(event.scrollingDeltaY) {
            return
        }

        super.scrollWheel(with: event)
    }

    @discardableResult
    func syncPolledHover(at point: CGPoint) -> Bool {
        let hovered = containsInteractivePoint(point)
        setHovered(hovered, animated: false)
        return hovered
    }

    func clearPolledHover() {
        setHovered(false, animated: false)
    }

    func setDwellActionActive(_ active: Bool) {
        guard isDwellActionActive != active else {
            return
        }

        isDwellActionActive = active
        updateAppearance(animated: true)
    }

    // MARK: - Visual State

    private var isSubProfileSwitch: Bool {
        config.action.targetSubProfileID != nil
    }

    private var isSystemEvent: Bool {
        config.type == .systemEvent
    }

    private var isDwellAction: Bool {
        config.type == .dwellAction
    }

    private var activeJoystickLayer: JoystickLayerConfig? {
        guard activeJoystickLayerIndex > 0,
              activeJoystickLayerIndex - 1 < config.joystick.nestedLayers.count else {
            return nil
        }

        return config.joystick.nestedLayers[activeJoystickLayerIndex - 1]
    }

    private var canEnterNestedJoystickLayer: Bool {
        activeJoystickLayerIndex + 1 < JoystickConfig.maxLayerCount
            && activeJoystickLayerIndex < config.joystick.nestedLayers.count
    }

    private var currentJoystickLayerDisplayIndex: Int {
        activeJoystickLayerIndex + 1
    }

    private var displayTextColor: NSColor {
        (isSystemEvent || isDwellAction) ? ButtonConfig.systemEventSymbolColor(for: config.colorHex) : NSColor(hex: config.labelColorHex)
    }

    private var displayTextFont: NSFont {
        guard isSystemEvent || isDwellAction else {
            return config.resolvedLabelFont
        }

        let symbolSize = max(10, min(bounds.width, bounds.height) * config.systemEventIconSize.symbolScale)
        return NSFont.systemFont(ofSize: symbolSize, weight: .bold)
    }

    private var isCurrentSubProfileSwitch: Bool {
        guard let targetID = config.action.targetSubProfileID else {
            return false
        }

        return targetID == activeSubProfileID
    }

    private var isVisuallyPressed: Bool {
        isSwitchPressed
            || isSystemEventPressed
            || isDwellActionPressed
            || primaryState.isPressed
            || secondaryState.isPressed
            || joystickRightClickState.isPressed
            || isJoystickCaptured
            || isJoystickDragActive
    }

    private var isJoystick: Bool {
        config.type == .joystick
    }

    private var isJoystickCaptureMode: Bool {
        isJoystick && config.joystick.operationMode == .capture
    }

    private var isJoystickClickDragMode: Bool {
        isJoystick && config.joystick.operationMode == .clickDrag
    }

    private var canHandleJoystickScroll: Bool {
        isJoystickClickDragMode || isJoystickCaptured
    }

    private var activeModeOutline: ActiveModeOutline? {
        if isDwellAction, isDwellActionActive {
            return .dwellAction
        }

        guard !isJoystick, !isSubProfileSwitch, !isSystemEvent, !isDwellAction else {
            return nil
        }

        if hasActiveModeOutline(.turbo) {
            return .turbo
        }

        if hasActiveModeOutline(.toggleHold) {
            return .toggleHold
        }

        return nil
    }

    private func hoverOutlineColor(for base: NSColor) -> NSColor {
        guard let color = base.usingColorSpace(.sRGB) else {
            return .white
        }

        let luminance = (0.2126 * color.redComponent) + (0.7152 * color.greenComponent) + (0.0722 * color.blueComponent)
        return luminance >= 0.82 ? .black : .white
    }

    private func hasActiveModeOutline(_ mode: ButtonInteractionMode) -> Bool {
        isActive(source: .primary, mode: mode) || isActive(source: .secondary, mode: mode)
    }

    private func isActive(source: PressSource, mode: ButtonInteractionMode) -> Bool {
        let state = state(for: source)
        guard state.isPressed, let input = resolvedInput(for: source) else {
            return false
        }

        return input.mode == mode
    }

    private func outlineColor(for activeMode: ActiveModeOutline, baseColor: NSColor) -> NSColor {
        switch activeMode {
        case .toggleHold:
            return isRedButtonColor(baseColor) ? .systemYellow : .systemRed
        case .turbo:
            return isGreenButtonColor(baseColor) ? .systemBlue : .systemGreen
        case .dwellAction:
            return .systemBlue
        }
    }

    private func isRedButtonColor(_ color: NSColor) -> Bool {
        guard let color = color.usingColorSpace(.sRGB) else {
            return false
        }

        return color.redComponent > color.greenComponent * 1.25
            && color.redComponent > color.blueComponent * 1.25
            && color.saturationComponent >= 0.35
            && color.brightnessComponent >= 0.20
    }

    private func isGreenButtonColor(_ color: NSColor) -> Bool {
        guard let color = color.usingColorSpace(.sRGB) else {
            return false
        }

        return color.greenComponent > color.redComponent * 1.18
            && color.greenComponent > color.blueComponent * 1.18
            && color.saturationComponent >= 0.35
            && color.brightnessComponent >= 0.20
    }

    private func updateHoverState(with event: NSEvent, animated: Bool) {
        setHovered(containsInteractivePoint(convert(event.locationInWindow, from: nil)), animated: animated)
    }

    private func setHovered(_ hovered: Bool, animated: Bool) {
        guard isHovered != hovered else {
            return
        }

        isHovered = hovered
        updateAppearance(animated: animated)
    }

    // MARK: - Special Button Actions

    private func handleSubProfileSwitchPressStarted() {
        guard !isCurrentSubProfileSwitch else {
            return
        }

        isSwitchPressed = true
        updateAppearance(animated: true)
    }

    private func handleSubProfileSwitchPressEnded(inside: Bool) {
        defer {
            if isSwitchPressed {
                isSwitchPressed = false
                updateAppearance(animated: true)
            }
        }

        guard inside, !isCurrentSubProfileSwitch, let targetID = config.action.targetSubProfileID else {
            return
        }

        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.activateSubProfileIfAllowed(targetID)
        } else {
            ProfileStore.shared.setActiveSubProfile(targetID)
        }
    }

    private func handleSystemEventPressStarted() {
        guard let systemEvent = config.action.systemEvent else {
            return
        }

        isSystemEventPressed = true
        updateAppearance(animated: true)
        SystemEventInjector.shared.trigger(systemEvent)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.systemEventHighlightDuration) { [weak self] in
            guard let self else {
                return
            }

            self.isSystemEventPressed = false
            self.updateAppearance(animated: true)
        }
    }

    private func handleDwellActionPressStarted() {
        isDwellActionPressed = true
        updateAppearance(animated: true)
    }

    private func handleDwellActionPressEnded(inside: Bool) {
        defer {
            if isDwellActionPressed {
                isDwellActionPressed = false
                updateAppearance(animated: true)
            }
        }

        guard inside else {
            return
        }

        isDwellActionActive = onDwellActionToggled?(button, config.dwellAction) ?? false
        updateAppearance(animated: true)
    }

    // MARK: - Joystick Capture

    @discardableResult
    func beginVirtualJoystickCapture() -> Bool {
        guard isJoystickCaptureMode else {
            return false
        }

        guard !isJoystickCaptured else {
            return isVirtualJoystickCaptured
        }

        releaseJoystickScrollStates()
        resetJoystickCaptureStartState()
        isJoystickCaptured = true
        isVirtualJoystickCaptured = true
        onJoystickCaptureChanged?(true)
        updateAppearance(animated: true)
        debugLog("[Button \(button.rawValue)] virtualJoystickCaptureStarted")
        return true
    }

    func updateVirtualJoystickCapture(delta: CGPoint) {
        guard isVirtualJoystickCaptured else {
            return
        }

        updateJoystickCapture(deltaX: delta.x, deltaY: delta.y)
    }

    func handleVirtualJoystickLeftClick(isDown: Bool) {
        guard isVirtualJoystickCaptured else {
            return
        }

        if isDown {
            handlePressStarted(source: .joystickLeftClick)
        } else {
            handlePressEnded(source: .joystickLeftClick)
        }
    }

    @discardableResult
    func handleVirtualJoystickRightClick(isDown: Bool) -> Bool {
        guard isVirtualJoystickCaptured else {
            return false
        }

        if isDown {
            flashJoystickHUDControl(.rightClick)
            virtualJoystickRightClickReturnedToPreviousLayer = returnToPreviousJoystickLayer()
        } else if virtualJoystickRightClickReturnedToPreviousLayer {
            virtualJoystickRightClickReturnedToPreviousLayer = false
        } else if activeJoystickLayerIndex == 0 {
            releaseJoystickCapture(warpCursorToCenter: false)
        }

        return isVirtualJoystickCaptured
    }

    func releaseVirtualJoystickCapture() {
        guard isVirtualJoystickCaptured else {
            return
        }

        releaseJoystickCapture(warpCursorToCenter: false)
    }

    private func beginJoystickCapture(with event: NSEvent) {
        guard !isJoystickCaptured else {
            return
        }

        releaseJoystickScrollStates()
        resetJoystickCaptureStartState()
        guard installJoystickEventMonitors() else {
            updateAppearance(animated: true)
            return
        }

        isJoystickCaptured = true
        isVirtualJoystickCaptured = false
        // Disassociation preserves relative deltas without moving the cursor. Do not warp while captured;
        // macOS can fold a warp into a later mouse delta and briefly activate the wrong direction.
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        hideJoystickCursorIfNeeded()
        onJoystickCaptureChanged?(true)
        updateAppearance(animated: true)
        debugLog("[Button \(button.rawValue)] joystickCaptureStarted")
    }

    private func resetJoystickCaptureStartState() {
        releaseActiveJoystickBindings()
        activeJoystickLayerIndex = 0
        joystickOffset = .zero
        activeJoystickDirection = nil
        lockedJoystickDirection = nil
        requiresJoystickAxisLockNeutralBeforeLock = false
        lastJoystickAxisLockMovementTime = nil
        lastJoystickScrollActivation = nil
        nestedLayerScrollSuppression = nil
        isJoystickCaptureReleasePending = false
        pendingJoystickCaptureReleaseShouldWarp = false
        cancelJoystickAxisLockTimer()
        joystickIdleReturnGeneration &+= 1
        lastJoystickMovementTime = ProcessInfo.processInfo.systemUptime
    }

    private func updateJoystickCapture(deltaX: CGFloat, deltaY: CGFloat) {
        guard isJoystickCaptured else {
            return
        }

        noteJoystickMovementActivity()
        let movementDelta = CGPoint(x: deltaX, y: deltaY)
        joystickOffset = clampedJoystickOffset(joystickOffset(afterApplying: movementDelta))
        unlockJoystickAxisLockAfterMovementIfNeeded(movementDelta)
        updateJoystickAxisLockHoldState()
        updateActiveJoystickDirection()

        scheduleJoystickIdleReturnIfNeeded()
        updateAppearance(animated: false)
    }

    private func noteJoystickMovementActivity() {
        lastJoystickMovementTime = ProcessInfo.processInfo.systemUptime
    }

    private func resetJoystickRuntimeState() {
        releaseActiveJoystickBindings()
        isJoystickDragActive = false
        isVirtualJoystickCaptured = false
        virtualJoystickRightClickReturnedToPreviousLayer = false
        activeJoystickLayerIndex = 0
        joystickOffset = .zero
        activeJoystickDirection = nil
        lockedJoystickDirection = nil
        requiresJoystickAxisLockNeutralBeforeLock = false
        lastJoystickAxisLockMovementTime = nil
        lastJoystickScrollActivation = nil
        nestedLayerScrollSuppression = nil
        joystickIdleReturnWorkItem?.cancel()
        joystickIdleReturnWorkItem = nil
        joystickIdleReturnGeneration &+= 1
        isJoystickCaptureReleasePending = false
        pendingJoystickCaptureReleaseShouldWarp = false
        cancelJoystickAxisLockTimer()
        clearJoystickHUDFlashes()
    }

    private func releaseJoystickCapture(warpCursorToCenter: Bool) {
        guard isJoystickCaptured
            || isJoystickCaptureReleasePending
            || activeJoystickDirection != nil
            || !activeJoystickBindings.isEmpty
            || lockedJoystickDirection != nil
            || joystickAxisLockWorkItem != nil
            || joystickLeftClickState.isPressed
            || joystickRightClickState.isPressed
            || joystickScrollUpState.isPressed
            || joystickScrollDownState.isPressed
            || activeJoystickLayerIndex != 0 else {
            return
        }

        releaseJoystickCaptureInputs()

        if isJoystickCaptured {
            finishJoystickCaptureRelease(warpCursorToCenter: warpCursorToCenter)
        } else {
            isJoystickCaptureReleasePending = false
            pendingJoystickCaptureReleaseShouldWarp = false
        }

        updateAppearance(animated: true)
    }

    private func beginDeferredJoystickCaptureRelease(warpCursorToCenter: Bool) {
        guard isJoystickCaptured else {
            return
        }

        releaseJoystickCaptureInputs()
        isJoystickCaptureReleasePending = true
        pendingJoystickCaptureReleaseShouldWarp = pendingJoystickCaptureReleaseShouldWarp || warpCursorToCenter
        updateAppearance(animated: true)
        debugLog("[Button \(button.rawValue)] joystickCaptureReleasePending")
    }

    private func finishDeferredJoystickCaptureReleaseIfNeeded() {
        guard isJoystickCaptureReleasePending else {
            return
        }

        let shouldWarpCursorToCenter = pendingJoystickCaptureReleaseShouldWarp
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isJoystickCaptureReleasePending else {
                return
            }

            self.finishJoystickCaptureRelease(warpCursorToCenter: shouldWarpCursorToCenter)
            self.updateAppearance(animated: true)
        }
    }

    private func releaseJoystickCaptureInputs() {
        releaseActiveJoystickBindings()
        releaseState(joystickLeftClickState)
        releaseState(joystickRightClickState)
        releaseState(joystickScrollUpState)
        releaseState(joystickScrollDownState)
        activeJoystickLayerIndex = 0
        activeJoystickDirection = nil
        joystickOffset = .zero
        lockedJoystickDirection = nil
        requiresJoystickAxisLockNeutralBeforeLock = false
        lastJoystickAxisLockMovementTime = nil
        lastJoystickScrollActivation = nil
        nestedLayerScrollSuppression = nil
        joystickIdleReturnWorkItem?.cancel()
        joystickIdleReturnWorkItem = nil
        joystickIdleReturnGeneration &+= 1
        cancelJoystickAxisLockTimer()
        clearJoystickHUDFlashes()
    }

    private func releaseJoystickScrollStates() {
        releaseState(joystickScrollUpState)
        releaseState(joystickScrollDownState)
        lastJoystickScrollActivation = nil
        nestedLayerScrollSuppression = nil
    }

    @discardableResult
    private func enterNestedJoystickLayer() -> Bool {
        guard canEnterNestedJoystickLayer else {
            return false
        }

        switchJoystickLayer(to: activeJoystickLayerIndex + 1)
        return true
    }

    @discardableResult
    private func returnToPreviousJoystickLayer() -> Bool {
        guard activeJoystickLayerIndex > 0 else {
            return false
        }

        switchJoystickLayer(to: activeJoystickLayerIndex - 1)
        return true
    }

    private func switchJoystickLayer(to nextLayerIndex: Int) {
        let clampedIndex = min(max(0, nextLayerIndex), JoystickConfig.maxLayerCount - 1)
        guard clampedIndex != activeJoystickLayerIndex else {
            return
        }

        releaseActiveJoystickBindings()
        releaseState(joystickLeftClickState)
        releaseState(joystickRightClickState)
        releaseState(joystickScrollUpState)
        releaseState(joystickScrollDownState)
        activeJoystickLayerIndex = clampedIndex
        activeJoystickDirection = nil
        joystickOffset = .zero
        lockedJoystickDirection = nil
        requiresJoystickAxisLockNeutralBeforeLock = false
        lastJoystickAxisLockMovementTime = nil
        lastJoystickScrollActivation = nil
        nestedLayerScrollSuppression = nil
        joystickIdleReturnWorkItem?.cancel()
        joystickIdleReturnWorkItem = nil
        joystickIdleReturnGeneration &+= 1
        cancelJoystickAxisLockTimer()
        updateAppearance(animated: true)
        debugLog("[Button \(button.rawValue)] joystickLayer=\(currentJoystickLayerDisplayIndex)")
    }

    private func finishJoystickCaptureRelease(warpCursorToCenter: Bool) {
        guard isJoystickCaptured else {
            isJoystickCaptureReleasePending = false
            pendingJoystickCaptureReleaseShouldWarp = false
            return
        }

        isJoystickCaptured = false
        let wasVirtualJoystickCaptured = isVirtualJoystickCaptured
        isVirtualJoystickCaptured = false
        virtualJoystickRightClickReturnedToPreviousLayer = false
        isJoystickCaptureReleasePending = false
        pendingJoystickCaptureReleaseShouldWarp = false

        if !wasVirtualJoystickCaptured {
            removeJoystickEventMonitors()
            if warpCursorToCenter {
                warpCursorToJoystickCenter()
            }
            reassociateMouseAndCursorAfterJoystickCaptureRelease()
            unhideJoystickCursorIfNeeded()
        }

        onJoystickCaptureChanged?(false)
        debugLog("[Button \(button.rawValue)] \(wasVirtualJoystickCaptured ? "virtualJoystickCaptureEnded" : "joystickCaptureEnded")")
    }

    private func handleJoystickMouseDown(with event: NSEvent) {
        if isJoystickCaptureMode {
            beginJoystickCapture(with: event)
            return
        }

        handlePressStarted(source: .joystickLeftClick)
        beginJoystickDrag(with: event)
    }

    private func handleJoystickMouseDragged(with event: NSEvent) {
        guard isJoystickClickDragMode, isJoystickDragActive else {
            return
        }

        updateJoystickDrag(with: event)
    }

    private func handleJoystickMouseUp(with event: NSEvent) {
        guard isJoystickClickDragMode else {
            return
        }

        updateJoystickDrag(with: event)
        handlePressEnded(source: .joystickLeftClick)
        releaseJoystickDrag(clearLock: false, resetLayer: false)
    }

    private func beginJoystickDrag(with event: NSEvent) {
        guard isJoystickClickDragMode else {
            return
        }

        isJoystickDragActive = true
        releaseActiveJoystickBindings()
        activeJoystickDirection = nil
        activeJoystickBindings = []
        lastJoystickScrollActivation = nil
        joystickIdleReturnWorkItem?.cancel()
        joystickIdleReturnWorkItem = nil
        joystickIdleReturnGeneration &+= 1
        updateJoystickDrag(with: event)
        debugLog("[Button \(button.rawValue)] joystickDragStarted")
    }

    private func updateJoystickDrag(with event: NSEvent) {
        guard isJoystickDragActive else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let rawOffset = CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY)
        let previousOffset = joystickOffset
        joystickOffset = clampedJoystickOffsetToTravelEllipse(rawOffset)
        unlockJoystickAxisLockAfterMovementIfNeeded(CGPoint(
            x: joystickOffset.x - previousOffset.x,
            y: joystickOffset.y - previousOffset.y
        ))
        updateJoystickAxisLockHoldState()
        updateActiveJoystickDirection()
        updateAppearance(animated: false)
    }

    private func releaseJoystickDrag(clearLock: Bool = true, resetLayer: Bool = true) {
        guard isJoystickDragActive
            || activeJoystickDirection != nil
            || !activeJoystickBindings.isEmpty
            || lockedJoystickDirection != nil
            || joystickAxisLockWorkItem != nil
            || joystickLeftClickState.isPressed
            || joystickRightClickState.isPressed
            || joystickScrollUpState.isPressed
            || joystickScrollDownState.isPressed
            || activeJoystickLayerIndex != 0 else {
            return
        }

        isJoystickDragActive = false
        releaseActiveJoystickBindings()
        releaseState(joystickLeftClickState)
        releaseState(joystickRightClickState)
        releaseState(joystickScrollUpState)
        releaseState(joystickScrollDownState)
        if resetLayer {
            activeJoystickLayerIndex = 0
        }
        activeJoystickDirection = nil
        joystickOffset = .zero
        if clearLock {
            lockedJoystickDirection = nil
            requiresJoystickAxisLockNeutralBeforeLock = false
            lastJoystickAxisLockMovementTime = nil
        }
        cancelJoystickAxisLockTimer()
        if !clearLock, lockedJoystickDirection != nil {
            updateActiveJoystickDirection()
        }
        updateAppearance(animated: true)
        debugLog("[Button \(button.rawValue)] joystickDragEnded")
    }

    @discardableResult
    private func installJoystickEventMonitors() -> Bool {
        removeJoystickEventMonitors()

        let eventMask = Self.joystickEventMask
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.joystickEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            errorLog("[Button \(button.rawValue)] ERROR: joystickEventTapCreationFailed")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        joystickEventTap = eventTap
        joystickEventTapRunLoopSource = source
        return true
    }

    private func removeJoystickEventMonitors() {
        joystickIdleReturnWorkItem?.cancel()
        joystickIdleReturnWorkItem = nil
        joystickIdleReturnGeneration &+= 1
        cancelJoystickAxisLockTimer()

        if let joystickEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), joystickEventTapRunLoopSource, .commonModes)
            self.joystickEventTapRunLoopSource = nil
        }

        if let joystickEventTap {
            CGEvent.tapEnable(tap: joystickEventTap, enable: false)
            self.joystickEventTap = nil
        }
    }

    private func hideJoystickCursorIfNeeded() {
        guard !isJoystickCursorHidden else {
            return
        }

        guard BackgroundCursorHiding.setEnabled(true) else {
            errorLog("[Button \(button.rawValue)] ERROR: joystickBackgroundCursorHidingUnavailable")
            return
        }

        let result = CGDisplayHideCursor(CGMainDisplayID())
        guard result == .success else {
            _ = BackgroundCursorHiding.setEnabled(false)
            errorLog("[Button \(button.rawValue)] ERROR: joystickCursorHideFailed code=\(result.rawValue)")
            return
        }
        isJoystickCursorHidden = true
    }

    private func unhideJoystickCursorIfNeeded() {
        guard isJoystickCursorHidden else {
            return
        }

        let result = CGDisplayShowCursor(CGMainDisplayID())
        guard result == .success else {
            errorLog("[Button \(button.rawValue)] ERROR: joystickCursorShowFailed code=\(result.rawValue)")
            return
        }
        isJoystickCursorHidden = false

        if !BackgroundCursorHiding.setEnabled(false) {
            errorLog("[Button \(button.rawValue)] ERROR: joystickBackgroundCursorHidingResetFailed")
        }
    }

    private func scheduleJoystickIdleReturnIfNeeded() {
        joystickIdleReturnWorkItem?.cancel()
        joystickIdleReturnGeneration &+= 1

        guard hypot(joystickOffset.x, joystickOffset.y) > 0.5 else {
            joystickIdleReturnWorkItem = nil
            return
        }

        let generation = joystickIdleReturnGeneration
        let workItem = DispatchWorkItem { [weak self] in
            self?.returnJoystickToDeadzoneIfIdle(generation: generation)
        }
        joystickIdleReturnWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.joystickIdleReturnDelay, execute: workItem)
    }

    private func returnJoystickToDeadzoneIfIdle(generation: UInt64) {
        guard isJoystickCaptured else {
            return
        }

        guard generation == joystickIdleReturnGeneration else {
            return
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - lastJoystickMovementTime
        guard elapsed >= Self.joystickIdleReturnDelay else {
            let remainingDelay = max(0.001, Self.joystickIdleReturnDelay - elapsed)
            let workItem = DispatchWorkItem { [weak self] in
                self?.returnJoystickToDeadzoneIfIdle(generation: generation)
            }
            joystickIdleReturnWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay, execute: workItem)
            return
        }

        joystickIdleReturnWorkItem = nil
        joystickOffset = .zero
        if config.joystick.axisLockMode == .holdDirection, lockedJoystickDirection == nil {
            requiresJoystickAxisLockNeutralBeforeLock = false
            cancelJoystickAxisLockTimer()
        }
        updateActiveJoystickDirection()
        updateAppearance(animated: true)
    }

    // MARK: - Joystick Direction and Cursor Control

    private func joystickOffset(afterApplying movementDelta: CGPoint) -> CGPoint {
        var nextOffset = CGPoint(
            x: joystickOffset.x + movementDelta.x,
            y: joystickOffset.y + movementDelta.y
        )

        let absoluteX = abs(movementDelta.x)
        let absoluteY = abs(movementDelta.y)
        let minimumDelta = Self.joystickMinimumDeltaForAxisReset

        if absoluteY >= minimumDelta,
           absoluteY >= absoluteX * Self.joystickCardinalDominanceRatio {
            nextOffset.x = 0
        } else if absoluteX >= minimumDelta,
                  absoluteX >= absoluteY * Self.joystickCardinalDominanceRatio {
            nextOffset.y = 0
        }

        return nextOffset
    }

    private func joystickDirection(for offset: CGPoint) -> JoystickDirection? {
        if let lockedJoystickDirection {
            return joystickDirection(forLockedDirection: lockedJoystickDirection, offset: offset)
        }

        return unlockedJoystickDirection(for: offset)
    }

    private func unlockedJoystickDirection(for offset: CGPoint) -> JoystickDirection? {
        let distance = hypot(offset.x, offset.y)
        let deadzoneRadius = effectiveJoystickDeadzoneRadius
        guard distance >= deadzoneRadius else {
            return nil
        }

        let axisThreshold = deadzoneRadius * 0.55
        let wantsRight = offset.x > axisThreshold
        let wantsLeft = offset.x < -axisThreshold
        let wantsUp = offset.y > axisThreshold
        let wantsDown = offset.y < -axisThreshold

        if wantsUp {
            if wantsRight {
                return .upRight
            }
            if wantsLeft {
                return .upLeft
            }
            return .up
        }

        if wantsDown {
            if wantsRight {
                return .downRight
            }
            if wantsLeft {
                return .downLeft
            }
            return .down
        }

        if wantsRight {
            return .right
        }

        if wantsLeft {
            return .left
        }

        return abs(offset.x) >= abs(offset.y)
            ? (offset.x >= 0 ? .right : .left)
            : (offset.y >= 0 ? .up : .down)
    }

    private func joystickDirection(forLockedDirection lockedDirection: JoystickDirection, offset: CGPoint) -> JoystickDirection {
        switch lockedDirection {
        case .up:
            switch joystickHorizontalDirection(for: offset) {
            case .right:
                return .upRight
            case .left:
                return .upLeft
            case nil:
                return .up
            }
        case .down:
            switch joystickHorizontalDirection(for: offset) {
            case .right:
                return .downRight
            case .left:
                return .downLeft
            case nil:
                return .down
            }
        case .left:
            switch joystickVerticalDirection(for: offset) {
            case .up:
                return .upLeft
            case .down:
                return .downLeft
            case nil:
                return .left
            }
        case .right:
            switch joystickVerticalDirection(for: offset) {
            case .up:
                return .upRight
            case .down:
                return .downRight
            case nil:
                return .right
            }
        case .upRight:
            return .upRight
        case .downRight:
            return .downRight
        case .downLeft:
            return .downLeft
        case .upLeft:
            return .upLeft
        }
    }

    private func joystickVerticalDirection(for offset: CGPoint) -> JoystickVerticalDirection? {
        let deadzoneRadius = effectiveJoystickDeadzoneRadius
        let axisThreshold = deadzoneRadius * 0.55

        if offset.y > axisThreshold {
            return .up
        }

        if offset.y < -axisThreshold {
            return .down
        }

        return nil
    }

    private func joystickHorizontalDirection(for offset: CGPoint) -> JoystickHorizontalDirection? {
        let deadzoneRadius = effectiveJoystickDeadzoneRadius
        let axisThreshold = deadzoneRadius * 0.55

        if offset.x > axisThreshold {
            return .right
        }

        if offset.x < -axisThreshold {
            return .left
        }

        return nil
    }

    private func updateActiveJoystickDirection() {
        let nextDirection = joystickDirection(for: joystickOffset)
        if nextDirection != activeJoystickDirection {
            setActiveJoystickDirection(nextDirection)
        }
    }

    private func setActiveJoystickDirection(_ direction: JoystickDirection?) {
        let nextBindings = direction.map { uniqueJoystickBindings(bindings(for: $0)) } ?? []
        let heldBindingSet = Set(heldJoystickBindings)
        let nextBindingSet = Set(nextBindings)

        for binding in nextBindings {
            if pendingJoystickReleaseWorkItems[binding] != nil {
                cancelPendingJoystickRelease(for: binding)
            } else if !heldBindingSet.contains(binding) {
                KeyInjector.shared.pressRaw(binding.keyCode, modifiers: binding.modifiers)
                heldJoystickBindings.append(binding)
            }
        }

        for binding in activeJoystickBindings.reversed() where !nextBindingSet.contains(binding) {
            scheduleJoystickRelease(for: binding)
        }

        activeJoystickBindings = nextBindings
        activeJoystickDirection = direction
        debugLog("[Button \(button.rawValue)] joystickDirection=\(String(describing: direction)) bindings=\(activeJoystickBindings.map { $0.keyCode })")
    }

    private func releaseActiveJoystickBindings() {
        pendingJoystickReleaseWorkItems.values.forEach { $0.cancel() }
        pendingJoystickReleaseWorkItems.removeAll()
        pendingJoystickReleaseGenerations.removeAll()
        joystickReleaseGeneration &+= 1

        for binding in heldJoystickBindings.reversed() {
            KeyInjector.shared.releaseRaw(binding.keyCode, modifiers: binding.modifiers)
        }
        heldJoystickBindings = []
        activeJoystickBindings = []
    }

    private func scheduleJoystickRelease(for binding: JoystickBinding) {
        guard heldJoystickBindings.contains(binding), pendingJoystickReleaseWorkItems[binding] == nil else {
            return
        }

        let delayMilliseconds = JoystickConfig.normalizedReleaseDelayMilliseconds(config.joystick.releaseDelayMilliseconds)
        guard delayMilliseconds > 0 else {
            releaseHeldJoystickBinding(binding)
            return
        }

        joystickReleaseGeneration &+= 1
        let generation = joystickReleaseGeneration
        pendingJoystickReleaseGenerations[binding] = generation
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.pendingJoystickReleaseGenerations[binding] == generation,
                  !self.activeJoystickBindings.contains(binding) else {
                return
            }

            self.pendingJoystickReleaseWorkItems[binding] = nil
            self.pendingJoystickReleaseGenerations[binding] = nil
            self.releaseHeldJoystickBinding(binding)
        }
        pendingJoystickReleaseWorkItems[binding] = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (Double(delayMilliseconds) / 1_000.0),
            execute: workItem
        )
    }

    private func cancelPendingJoystickRelease(for binding: JoystickBinding) {
        pendingJoystickReleaseWorkItems.removeValue(forKey: binding)?.cancel()
        pendingJoystickReleaseGenerations[binding] = nil
    }

    private func releaseHeldJoystickBinding(_ binding: JoystickBinding) {
        guard let heldIndex = heldJoystickBindings.firstIndex(of: binding) else {
            return
        }

        heldJoystickBindings.remove(at: heldIndex)
        KeyInjector.shared.releaseRaw(binding.keyCode, modifiers: binding.modifiers)
    }

    private func uniqueJoystickBindings(_ bindings: [ButtonKeyBinding]) -> [JoystickBinding] {
        var seenBindings = Set<JoystickBinding>()
        return bindings.compactMap { binding in
            let joystickBinding = JoystickBinding(
                keyCode: CGKeyCode(binding.keyCode),
                modifiersRawValue: UInt(binding.keyModifiers)
            )
            return seenBindings.insert(joystickBinding).inserted ? joystickBinding : nil
        }
    }

    private func bindings(for direction: JoystickDirection) -> [ButtonKeyBinding] {
        switch direction {
        case .up:
            return [activeJoystickLayer?.up ?? config.joystick.up]
        case .upRight:
            return [activeJoystickLayer?.up ?? config.joystick.up, activeJoystickLayer?.right ?? config.joystick.right]
        case .right:
            return [activeJoystickLayer?.right ?? config.joystick.right]
        case .downRight:
            return [activeJoystickLayer?.down ?? config.joystick.down, activeJoystickLayer?.right ?? config.joystick.right]
        case .down:
            return [activeJoystickLayer?.down ?? config.joystick.down]
        case .downLeft:
            return [activeJoystickLayer?.down ?? config.joystick.down, activeJoystickLayer?.left ?? config.joystick.left]
        case .left:
            return [activeJoystickLayer?.left ?? config.joystick.left]
        case .upLeft:
            return [activeJoystickLayer?.up ?? config.joystick.up, activeJoystickLayer?.left ?? config.joystick.left]
        }
    }

    private func warpCursorToJoystickCenter() {
        warpCursor(to: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    // MARK: - Joystick Event Tap

    private static var joystickEventMask: CGEventMask {
        eventMask(for: .mouseMoved)
            | eventMask(for: .leftMouseDown)
            | eventMask(for: .leftMouseUp)
            | eventMask(for: .leftMouseDragged)
            | eventMask(for: .rightMouseDown)
            | eventMask(for: .rightMouseUp)
            | eventMask(for: .rightMouseDragged)
            | eventMask(for: .scrollWheel)
    }

    private static let joystickEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let view = Unmanaged<GamepadButtonView>.fromOpaque(userInfo).takeUnretainedValue()
        return view.handleJoystickEventTap(type: type, event: event)
    }

    private static func eventMask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1 << type.rawValue)
    }

    private func handleJoystickEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isJoystickCaptured else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let joystickEventTap {
                CGEvent.tapEnable(tap: joystickEventTap, enable: true)
            }
            hideJoystickCursorIfNeeded()
            return nil

        case _ where isJoystickCaptureReleasePending:
            if type == .rightMouseUp {
                finishDeferredJoystickCaptureReleaseIfNeeded()
            }
            return nil

        case .rightMouseDown, .rightMouseDragged:
            flashJoystickHUDControl(.rightClick)
            if returnToPreviousJoystickLayer() {
                return nil
            }

            beginDeferredJoystickCaptureRelease(warpCursorToCenter: true)
            return nil

        case .rightMouseUp:
            finishDeferredJoystickCaptureReleaseIfNeeded()
            return nil

        case .leftMouseDown:
            handlePressStarted(source: .joystickLeftClick)
            return nil

        case .leftMouseUp:
            handlePressEnded(source: .joystickLeftClick)
            return nil

        case .scrollWheel:
            handleJoystickScroll(event)
            return nil

        case .mouseMoved, .leftMouseDragged:
            let deltaX = CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
            let deltaY = CGFloat(-event.getIntegerValueField(.mouseEventDeltaY))

            guard deltaX != 0 || deltaY != 0 else {
                return nil
            }

            updateJoystickCapture(deltaX: deltaX, deltaY: deltaY)
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func updateJoystickAxisLockHoldState() {
        guard config.joystick.axisLockMode == .holdDirection,
              isJoystickCaptured || isJoystickDragActive else {
            cancelJoystickAxisLockTimer()
            return
        }

        guard lockedJoystickDirection == nil else {
            cancelJoystickAxisLockTimer()
            return
        }

        guard let edgeDirection = joystickEdgeDirection(for: joystickOffset) else {
            requiresJoystickAxisLockNeutralBeforeLock = false
            cancelJoystickAxisLockTimer()
            return
        }

        guard !requiresJoystickAxisLockNeutralBeforeLock else {
            cancelJoystickAxisLockTimer()
            return
        }

        guard pendingJoystickAxisLockDirection != edgeDirection else {
            return
        }

        cancelJoystickAxisLockTimer()
        pendingJoystickAxisLockDirection = edgeDirection
        pendingJoystickAxisLockStartedAt = ProcessInfo.processInfo.systemUptime

        let delay = effectiveJoystickAxisLockHoldDuration
        let workItem = DispatchWorkItem { [weak self] in
            self?.completeJoystickAxisLockHold(direction: edgeDirection)
        }
        joystickAxisLockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func completeJoystickAxisLockHold(direction: JoystickDirection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard config.joystick.axisLockMode == .holdDirection,
              isJoystickCaptured || isJoystickDragActive,
              joystickEdgeDirection(for: joystickOffset) == direction,
              pendingJoystickAxisLockDirection == direction,
              let pendingJoystickAxisLockStartedAt else {
            cancelJoystickAxisLockTimer()
            return
        }

        let elapsed = now - pendingJoystickAxisLockStartedAt
        let remaining = effectiveJoystickAxisLockHoldDuration - elapsed
        guard remaining <= 0 else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.completeJoystickAxisLockHold(direction: direction)
            }
            joystickAxisLockWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: workItem)
            return
        }

        lockedJoystickDirection = direction
        requiresJoystickAxisLockNeutralBeforeLock = false
        lastJoystickAxisLockMovementTime = lastJoystickMovementTime
        cancelJoystickAxisLockTimer()
        updateActiveJoystickDirection()
        scheduleJoystickIdleReturnIfNeeded()
        updateAppearance(animated: true)
        debugLog("[Button \(button.rawValue)] joystickAxisLocked direction=\(direction)")
    }

    private func cancelJoystickAxisLockTimer() {
        joystickAxisLockWorkItem?.cancel()
        joystickAxisLockWorkItem = nil
        pendingJoystickAxisLockDirection = nil
        pendingJoystickAxisLockStartedAt = nil
    }

    private func unlockJoystickAxisLockAfterMovementIfNeeded(_ movementDelta: CGPoint) {
        guard config.joystick.axisLockMode == .holdDirection,
              let currentLockedJoystickDirection = lockedJoystickDirection else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard let movementDirection = joystickDirection(forMovementDelta: movementDelta) else {
            return
        }

        let previousMovementTime = lastJoystickAxisLockMovementTime
        lastJoystickAxisLockMovementTime = now

        if isContinuousMovement(movementDirection, forLockedDirection: currentLockedJoystickDirection),
           let previousMovementTime,
           now - previousMovementTime <= Self.joystickAxisUnlockMovementPause {
            return
        }

        lockedJoystickDirection = nil
        requiresJoystickAxisLockNeutralBeforeLock = true
        lastJoystickAxisLockMovementTime = nil
        cancelJoystickAxisLockTimer()
        debugLog("[Button \(button.rawValue)] joystickAxisUnlockedByMovement direction=\(currentLockedJoystickDirection)")
    }

    private func joystickDirection(forMovementDelta movementDelta: CGPoint) -> JoystickDirection? {
        let wantsRight = movementDelta.x >= Self.joystickAxisUnlockMovementThreshold
        let wantsLeft = movementDelta.x <= -Self.joystickAxisUnlockMovementThreshold
        let wantsUp = movementDelta.y >= Self.joystickAxisUnlockMovementThreshold
        let wantsDown = movementDelta.y <= -Self.joystickAxisUnlockMovementThreshold

        if wantsUp {
            if wantsRight {
                return .upRight
            }
            if wantsLeft {
                return .upLeft
            }
            return .up
        }

        if wantsDown {
            if wantsRight {
                return .downRight
            }
            if wantsLeft {
                return .downLeft
            }
            return .down
        }

        if wantsRight {
            return .right
        }

        if wantsLeft {
            return .left
        }

        return nil
    }

    private func isContinuousMovement(_ movementDirection: JoystickDirection, forLockedDirection lockedDirection: JoystickDirection) -> Bool {
        let movement = directionComponents(for: movementDirection)
        let locked = directionComponents(for: lockedDirection)
        let conflicts = (movement.x != 0 && locked.x != 0 && movement.x != locked.x)
            || (movement.y != 0 && locked.y != 0 && movement.y != locked.y)
        guard !conflicts else {
            return false
        }

        return (movement.x != 0 && movement.x == locked.x)
            || (movement.y != 0 && movement.y == locked.y)
    }

    private func directionComponents(for direction: JoystickDirection) -> (x: Int, y: Int) {
        switch direction {
        case .up:
            return (0, 1)
        case .upRight:
            return (1, 1)
        case .right:
            return (1, 0)
        case .downRight:
            return (1, -1)
        case .down:
            return (0, -1)
        case .downLeft:
            return (-1, -1)
        case .left:
            return (-1, 0)
        case .upLeft:
            return (-1, 1)
        }
    }

    private func joystickEdgeDirection(for offset: CGPoint) -> JoystickDirection? {
        let travelLimits = joystickTravelLimits
        guard travelLimits.width > 0, travelLimits.height > 0 else {
            return nil
        }

        let normalizedX = abs(offset.x / travelLimits.width)
        let normalizedY = abs(offset.y / travelLimits.height)
        guard max(normalizedX, normalizedY) >= Self.joystickAxisLockEdgeThreshold else {
            return nil
        }

        return unlockedJoystickDirection(for: offset)
    }

    private var effectiveJoystickAxisLockHoldDuration: TimeInterval {
        max(0.1, config.joystick.axisLockHoldDuration)
    }

    private func handleJoystickScroll(_ event: CGEvent) {
        let rawDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        guard rawDelta != 0 else {
            return
        }

        _ = handleJoystickScrollDelta(CGFloat(rawDelta))
    }

    @discardableResult
    private func handleJoystickScrollDelta(_ delta: CGFloat) -> Bool {
        guard delta != 0 else {
            return false
        }

        let direction: JoystickScrollDirection = delta > 0 ? .up : .down
        guard !shouldSuppressNestedLayerScroll(direction) else {
            return true
        }

        let action = joystickScrollAction(for: direction)

        switch action.kind {
        case .off:
            return false
        case .axisLock:
            guard config.joystick.axisLockMode == .scrollWheel else {
                return false
            }
        case .keyCombo:
            break
        case .nestedJoystick:
            guard canEnterNestedJoystickLayer else {
                return false
            }
        }

        guard shouldActivateJoystickScroll(direction) else {
            return true
        }

        flashJoystickHUDControl(direction == .up ? .scrollUp : .scrollDown)

        switch action.kind {
        case .off:
            break
        case .axisLock:
            toggleJoystickAxisLock(for: direction)
        case .keyCombo:
            triggerJoystickScrollInput(for: direction)
        case .nestedJoystick:
            if enterNestedJoystickLayer() {
                suppressTrailingNestedLayerScroll(direction)
            }
        }

        return true
    }

    private func shouldActivateJoystickScroll(_ direction: JoystickScrollDirection) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastJoystickScrollActivation,
           lastJoystickScrollActivation.direction == direction,
           now - lastJoystickScrollActivation.time < Self.joystickScrollActivationInterval {
            return false
        }

        lastJoystickScrollActivation = (direction: direction, time: now)
        return true
    }

    /// A trackpad or high-resolution wheel can emit trailing events after one scroll gesture.
    /// Keep those events from invoking the newly active layer's scroll action immediately.
    private func shouldSuppressNestedLayerScroll(_ direction: JoystickScrollDirection) -> Bool {
        guard let nestedLayerScrollSuppression else {
            return false
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - nestedLayerScrollSuppression.time
        guard elapsed < Self.joystickNestedLayerScrollSuppressionDuration else {
            self.nestedLayerScrollSuppression = nil
            return false
        }

        return nestedLayerScrollSuppression.direction == direction
    }

    private func suppressTrailingNestedLayerScroll(_ direction: JoystickScrollDirection) {
        nestedLayerScrollSuppression = (direction: direction, time: ProcessInfo.processInfo.systemUptime)
    }

    private func joystickScrollAction(for direction: JoystickScrollDirection) -> JoystickScrollAction {
        switch direction {
        case .up:
            return activeJoystickLayer?.scrollUpAction ?? config.joystick.scrollUpAction
        case .down:
            return activeJoystickLayer?.scrollDownAction ?? config.joystick.scrollDownAction
        }
    }

    private func toggleJoystickAxisLock(for direction: JoystickScrollDirection) {
        let nextDirection: JoystickDirection = direction == .up ? .up : .down
        if lockedJoystickDirection == nextDirection {
            lockedJoystickDirection = nil
        } else {
            lockedJoystickDirection = nextDirection
        }

        requiresJoystickAxisLockNeutralBeforeLock = false
        lastJoystickAxisLockMovementTime = nil
        cancelJoystickAxisLockTimer()
        updateActiveJoystickDirection()
        scheduleJoystickIdleReturnIfNeeded()
        updateAppearance(animated: true)
    }

    private func triggerJoystickScrollInput(for direction: JoystickScrollDirection) {
        let source: PressSource = direction == .up ? .joystickScrollUp : .joystickScrollDown
        guard let input = resolvedInput(for: source) else {
            return
        }

        handleDiscreteActivation(source: source, input: input)
    }

    private func warpCursor(to localPoint: CGPoint) {
        guard let quartzPoint = quartzPoint(for: localPoint) else {
            return
        }

        CGWarpMouseCursorPosition(quartzPoint)
    }

    private func reassociateMouseAndCursorAfterJoystickCaptureRelease() {
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        refreshMouseHoverAfterJoystickCaptureRelease()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            self?.refreshMouseHoverAfterJoystickCaptureRelease()
        }
    }

    private func refreshMouseHoverAfterJoystickCaptureRelease() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let location = quartzPoint(for: CGPoint(x: bounds.midX, y: bounds.midY)),
              let event = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: location,
                mouseButton: .left
              ) else {
            return
        }

        event.post(tap: .cghidEventTap)
    }

    private func quartzPoint(for localPoint: CGPoint) -> CGPoint? {
        guard let window, let screen = window.screen else {
            return nil
        }

        let windowPoint = convert(localPoint, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        return CGPoint(
            x: screenPoint.x,
            y: screen.frame.maxY - screenPoint.y
        )
    }

    // MARK: - Press State Machine

    private func handlePressStarted(source: PressSource) {
        if performJoystickTriggerActionIfNeeded(source: source) {
            return
        }

        guard let input = resolvedInput(for: source) else {
            return
        }

        if input.mode == .turbo {
            toggleTurboRepeat(source: source, input: input)
            return
        }

        if usesSequentialMultiKey(input) {
            if input.mode == .toggleHold {
                toggleSequentialRepeat(source: source, input: input)
                return
            }

            playSequentialBindings(source: source, input: input)
            return
        }

        if usesSimultaneousMultiKey(input) {
            if input.mode == .toggleHold {
                setSimultaneousPressed(!state(for: source).isPressed, source: source, input: input)
                return
            }

            setSimultaneousPressed(true, source: source, input: input)
            return
        }

        if input.mode == .toggleHold {
            setPressed(!state(for: source).isPressed, source: source, input: input)
            return
        }

        setPressed(true, source: source, input: input)
    }

    private func performJoystickTriggerActionIfNeeded(source: PressSource) -> Bool {
        switch source {
        case .joystickLeftClick:
            guard isJoystickCaptureMode,
                  joystickLeftClickAction().kind == .nestedJoystick else {
                return false
            }

            return enterNestedJoystickLayer()
        case .joystickRightClick:
            guard isJoystickClickDragMode,
                  activeJoystickLayerIndex == 0,
                  config.joystick.rightClickAction.kind == .nestedJoystick else {
                return false
            }

            return enterNestedJoystickLayer()
        case .primary, .secondary, .joystickScrollUp, .joystickScrollDown:
            return false
        }
    }

    private func handlePressEnded(source: PressSource) {
        guard let input = resolvedInput(for: source) else {
            return
        }

        guard input.mode != .turbo,
              !usesSequentialMultiKey(input),
              input.mode != .toggleHold else {
            return
        }

        if usesCompatibilityTap(input) {
            releaseCurrentPressedRespectingMinimumDuration(source: source, input: input)
            return
        }

        if usesSimultaneousMultiKey(input) {
            setSimultaneousPressed(false, source: source, input: input)
            return
        }

        setPressed(false, source: source, input: input)
    }

    private func handleDiscreteActivation(source: PressSource, input: ResolvedInput) {
        if input.mode == .turbo {
            toggleTurboRepeat(source: source, input: input)
            return
        }

        if usesSequentialMultiKey(input) {
            if input.mode == .toggleHold {
                toggleSequentialRepeat(source: source, input: input)
                return
            }

            playSequentialBindings(source: source, input: input)
            return
        }

        if usesSimultaneousMultiKey(input) {
            if input.mode == .toggleHold {
                setSimultaneousPressed(!state(for: source).isPressed, source: source, input: input)
                return
            }

            setSimultaneousPressed(true, source: source, input: input)
            scheduleCompatibilityRelease(source: source, input: input)
            return
        }

        if input.mode == .toggleHold {
            setPressed(!state(for: source).isPressed, source: source, input: input)
            return
        }

        setPressed(true, source: source, input: input)
        scheduleCompatibilityRelease(source: source, input: input)
    }

    private func handleDrag(source: PressSource, event: NSEvent) {
        guard let input = resolvedInput(for: source),
              input.mode != .turbo,
              !usesSequentialMultiKey(input),
              input.mode != .toggleHold else {
            return
        }

        let inside = containsInteractivePoint(convert(event.locationInWindow, from: nil))
        let state = state(for: source)
        if inside {
            state.autoReleaseWorkItem?.cancel()
            state.autoReleaseWorkItem = nil
        }

        if inside != state.isPressed {
            if inside || !usesCompatibilityTap(input) {
                setCurrentPressed(inside, source: source, input: input)
            } else {
                releaseCurrentPressedRespectingMinimumDuration(source: source, input: input)
            }
        }
    }

    private func releaseMomentaryOnExit(source: PressSource) {
        guard let input = resolvedInput(for: source),
              input.mode != .turbo,
              !usesSequentialMultiKey(input),
              input.mode != .toggleHold,
              state(for: source).isPressed else {
            return
        }

        if usesCompatibilityTap(input) {
            releaseCurrentPressedRespectingMinimumDuration(source: source, input: input)
        } else {
            setCurrentPressed(false, source: source, input: input)
        }
    }

    private func resolvedInput(for source: PressSource) -> ResolvedInput? {
        let primaryBindings = config.keyBindings.isEmpty
            ? [ButtonKeyBinding(keyCode: config.keyCode, keyModifiers: config.keyModifiers)]
            : config.keyBindings

        switch source {
        case .primary:
            return ResolvedInput(
                bindings: primaryBindings,
                mode: config.interactionMode,
                multiKeyActivationMode: config.multiKeyActivationMode,
                turboClicksPerSecond: config.turboClicksPerSecond
            )
        case .secondary:
            let usesPrimaryMode = config.rightClickInteractionMode == nil
            let turboClicksPerSecond = usesPrimaryMode
                ? config.turboClicksPerSecond
                : config.rightClickTurboClicksPerSecond
            if let rightClickBindings = config.rightClickKeyBindings, !rightClickBindings.isEmpty {
                return ResolvedInput(
                    bindings: rightClickBindings,
                    mode: config.rightClickInteractionMode ?? config.interactionMode,
                    multiKeyActivationMode: config.multiKeyActivationMode,
                    turboClicksPerSecond: turboClicksPerSecond
                )
            }

            guard config.rightClickFallsBackToPrimary else {
                return nil
            }

            return ResolvedInput(
                bindings: primaryBindings,
                mode: config.rightClickInteractionMode ?? config.interactionMode,
                multiKeyActivationMode: config.multiKeyActivationMode,
                turboClicksPerSecond: turboClicksPerSecond
            )
        case .joystickLeftClick:
            return resolvedInput(for: joystickLeftClickAction())
        case .joystickRightClick:
            return isJoystickClickDragMode && activeJoystickLayerIndex == 0
                ? resolvedInput(for: config.joystick.rightClickAction)
                : nil
        case .joystickScrollUp:
            return resolvedInput(for: joystickScrollAction(for: .up))
        case .joystickScrollDown:
            return resolvedInput(for: joystickScrollAction(for: .down))
        }
    }

    private func joystickLeftClickAction() -> JoystickTriggerAction {
        activeJoystickLayer?.leftClickAction ?? config.joystick.leftClickAction
    }

    private func resolvedInput(for action: JoystickTriggerAction) -> ResolvedInput? {
        guard action.kind == .keyCombo else {
            return nil
        }

        return resolvedInput(for: action.input)
    }

    private func resolvedInput(for action: JoystickScrollAction) -> ResolvedInput? {
        guard action.kind == .keyCombo else {
            return nil
        }

        return resolvedInput(for: action.input)
    }

    private func resolvedInput(for input: JoystickInputConfig) -> ResolvedInput? {
        guard !input.keyBindings.isEmpty else {
            return nil
        }

        return ResolvedInput(
            bindings: input.keyBindings,
            mode: input.interactionMode,
            multiKeyActivationMode: input.multiKeyActivationMode,
            turboClicksPerSecond: input.turboClicksPerSecond
        )
    }

    private func state(for source: PressSource) -> PressState {
        switch source {
        case .primary:
            return primaryState
        case .secondary:
            return secondaryState
        case .joystickLeftClick:
            return joystickLeftClickState
        case .joystickRightClick:
            return joystickRightClickState
        case .joystickScrollUp:
            return joystickScrollUpState
        case .joystickScrollDown:
            return joystickScrollDownState
        }
    }

    private func usesCompatibilityTap(_ input: ResolvedInput) -> Bool {
        compatibilityModeEnabled && input.mode == .momentary
    }

    private var compatibilityInputDuration: TimeInterval {
        let milliseconds = Profile.normalizedCompatibilityModeDurationMilliseconds(
            compatibilityModeDurationMilliseconds
        )
        return Double(milliseconds) / 1_000.0
    }

    private func usesSequentialMultiKey(_ input: ResolvedInput) -> Bool {
        input.bindings.count > 1 && input.multiKeyActivationMode == .sequential
    }

    private func usesSimultaneousMultiKey(_ input: ResolvedInput) -> Bool {
        input.bindings.count > 1 && input.multiKeyActivationMode == .simultaneous
    }

    private func scheduleCompatibilityRelease(source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        state.autoReleaseWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.setCurrentPressed(false, source: source, input: input)
        }
        state.autoReleaseWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + compatibilityInputDuration, execute: workItem)
    }

    private func releaseCurrentPressedRespectingMinimumDuration(source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        guard state.isPressed else {
            return
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - (state.pressedStartedAt ?? ProcessInfo.processInfo.systemUptime)
        let remainingDuration = compatibilityInputDuration - elapsed
        guard remainingDuration > 0 else {
            setCurrentPressed(false, source: source, input: input)
            return
        }

        state.autoReleaseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.setCurrentPressed(false, source: source, input: input)
        }
        state.autoReleaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDuration, execute: workItem)
    }

    private func playSequentialBindings(source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        stopSequentialPlayback(state)
        state.isPressed = true
        updateAppearance(animated: true)

        debugLog("[Button \(button.rawValue)] playSequential source=\(source) keyBindings=\(input.bindings.map(\.keyCode)) mode=\(input.mode.rawValue) compatibilityMode=\(compatibilityModeEnabled)")
        runSequentialStep(source: source, input: input, index: 0, generation: state.sequentialGeneration)
    }

    private func toggleSequentialRepeat(source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        if state.isSequentialRepeating {
            stopSequentialRepeat(source: source)
            return
        }

        stopSequentialPlayback(state)
        state.isPressed = true
        state.isSequentialRepeating = true
        updateAppearance(animated: true)
        debugLog("[Button \(button.rawValue)] startSequentialRepeat source=\(source) keyBindings=\(input.bindings.map(\.keyCode))")
        runSequentialStep(source: source, input: input, index: 0, generation: state.sequentialGeneration)
    }

    private func toggleTurboRepeat(source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        if state.isPressed {
            stopTurboRepeat(source: source)
            return
        }

        state.turboGeneration &+= 1
        state.isPressed = true
        updateAppearance(animated: true)
        debugLog("[Button \(button.rawValue)] startTurboRepeat source=\(source) keyBindings=\(input.bindings.map(\.keyCode)) activationMode=\(input.multiKeyActivationMode.rawValue) clicksPerSecond=\(input.turboClicksPerSecond)")
        beginTurboCycle(source: source, input: input)
    }

    private func runSequentialStep(
        source: PressSource,
        input: ResolvedInput,
        index: Int,
        generation: UInt64
    ) {
        let state = state(for: source)
        guard state.isPressed,
              state.sequentialGeneration == generation,
              input.bindings.indices.contains(index) else {
            return
        }

        let binding = input.bindings[index]
        let pressedBinding = (
            keyCode: CGKeyCode(binding.keyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
        )
        state.sequentialPressedBinding = pressedBinding
        KeyInjector.shared.pressRaw(pressedBinding.keyCode, modifiers: pressedBinding.modifiers)

        let workItem = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state,
                  state.isPressed,
                  state.sequentialGeneration == generation else {
                return
            }

            self.releaseSequentialBinding(state)
            state.sequentialStepWorkItem = nil

            let nextIndex = index + 1
            if input.bindings.indices.contains(nextIndex) {
                self.runSequentialStep(source: source, input: input, index: nextIndex, generation: generation)
            } else if state.isSequentialRepeating {
                self.runSequentialStep(source: source, input: input, index: 0, generation: generation)
            } else {
                state.isPressed = false
                self.updateAppearance(animated: true)
            }
        }
        state.sequentialStepWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + compatibilityInputDuration, execute: workItem)
    }

    private func stopSequentialRepeat(source: PressSource) {
        let state = state(for: source)
        stopSequentialPlayback(state)
        updateAppearance(animated: true)
        debugLog("[Button \(button.rawValue)] stopSequentialRepeat source=\(source)")
    }

    private func stopSequentialPlayback(_ state: PressState) {
        state.sequentialStepWorkItem?.cancel()
        state.sequentialStepWorkItem = nil
        state.sequentialGeneration &+= 1
        state.isSequentialRepeating = false
        releaseSequentialBinding(state)
        state.isPressed = false
    }

    private func releaseSequentialBinding(_ state: PressState) {
        guard let binding = state.sequentialPressedBinding else {
            return
        }

        KeyInjector.shared.releaseRaw(binding.keyCode, modifiers: binding.modifiers)
        state.sequentialPressedBinding = nil
    }

    private func beginTurboCycle(source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        guard state.isPressed else { return }

        let cycleStartedAt = ProcessInfo.processInfo.systemUptime
        if usesSequentialMultiKey(input) {
            runTurboSequentialStep(source: source, input: input, index: 0, cycleStartedAt: cycleStartedAt)
            return
        }

        let bindings = usesSimultaneousMultiKey(input)
            ? uniqueInputBindings(input.bindings)
            : uniqueInputBindings(Array(input.bindings.prefix(1)))
        pressTurboBindings(bindings, state: state)
        scheduleTurboStep(source: source, after: TurboConfiguration.tapDuration) { [weak self] in
            guard let self else { return }
            let state = self.state(for: source)
            self.releaseTurboBindings(state)
            self.scheduleNextTurboCycle(source: source, input: input, cycleStartedAt: cycleStartedAt)
        }
    }

    private func runTurboSequentialStep(
        source: PressSource,
        input: ResolvedInput,
        index: Int,
        cycleStartedAt: TimeInterval
    ) {
        let state = state(for: source)
        guard state.isPressed, input.bindings.indices.contains(index) else { return }

        let binding = input.bindings[index]
        pressTurboBindings(
            [(keyCode: CGKeyCode(binding.keyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers)))],
            state: state
        )
        scheduleTurboStep(source: source, after: TurboConfiguration.tapDuration) { [weak self] in
            guard let self else { return }
            let state = self.state(for: source)
            self.releaseTurboBindings(state)
            guard state.isPressed else { return }

            let nextIndex = index + 1
            if input.bindings.indices.contains(nextIndex) {
                self.runTurboSequentialStep(
                    source: source,
                    input: input,
                    index: nextIndex,
                    cycleStartedAt: cycleStartedAt
                )
            } else {
                self.scheduleNextTurboCycle(source: source, input: input, cycleStartedAt: cycleStartedAt)
            }
        }
    }

    private func scheduleTurboStep(source: PressSource, after delay: TimeInterval, action: @escaping () -> Void) {
        let state = state(for: source)
        state.turboStepWorkItem?.cancel()
        let generation = state.turboGeneration

        let workItem = DispatchWorkItem { [weak state] in
            guard state?.isPressed == true, state?.turboGeneration == generation else { return }
            state?.turboStepWorkItem = nil
            action()
        }
        state.turboStepWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleNextTurboCycle(source: PressSource, input: ResolvedInput, cycleStartedAt: TimeInterval) {
        let state = state(for: source)
        guard state.isPressed else { return }

        let clicksPerSecond = TurboConfiguration.normalizedClicksPerSecond(input.turboClicksPerSecond)
        let cycleInterval = 1.0 / Double(clicksPerSecond)
        let elapsed = ProcessInfo.processInfo.systemUptime - cycleStartedAt
        let delay = max(0, cycleInterval - elapsed)
        let generation = state.turboGeneration

        let workItem = DispatchWorkItem { [weak self, weak state] in
            guard state?.isPressed == true, state?.turboGeneration == generation else { return }
            state?.sequenceRepeatWorkItem = nil
            self?.beginTurboCycle(source: source, input: input)
        }
        state.sequenceRepeatWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func pressTurboBindings(
        _ bindings: [(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags)],
        state: PressState
    ) {
        guard state.turboPressedBindings.isEmpty else { return }
        state.turboPressedBindings = bindings
        for binding in bindings {
            KeyInjector.shared.pressRaw(binding.keyCode, modifiers: binding.modifiers)
        }
    }

    private func releaseTurboBindings(_ state: PressState) {
        for binding in state.turboPressedBindings.reversed() {
            KeyInjector.shared.releaseRaw(binding.keyCode, modifiers: binding.modifiers)
        }
        state.turboPressedBindings = []
    }

    private func stopTurboRepeat(source: PressSource) {
        let state = state(for: source)
        state.sequenceRepeatWorkItem?.cancel()
        state.sequenceRepeatWorkItem = nil
        state.turboStepWorkItem?.cancel()
        state.turboStepWorkItem = nil
        state.turboGeneration &+= 1
        releaseTurboBindings(state)
        state.isPressed = false
        updateAppearance(animated: true)
        debugLog("[Button \(button.rawValue)] stopTurboRepeat source=\(source)")
    }

    private func setPressed(_ pressed: Bool, source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        if pressed {
            state.autoReleaseWorkItem?.cancel()
            state.autoReleaseWorkItem = nil
        }
        guard pressed != state.isPressed, let binding = input.bindings.first else { return }
        state.isPressed = pressed
        let keyCode = CGKeyCode(binding.keyCode)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
        debugLog("[Button \(button.rawValue)] setPressed=\(pressed) source=\(source) keyCode=\(keyCode) modifiers=\(binding.keyModifiers) mode=\(input.mode.rawValue) compatibilityMode=\(compatibilityModeEnabled)")
        debugLatencyLog("[Button \(button.rawValue)] setPressed=\(pressed) source=\(source) keyCode=\(keyCode) modifiers=\(binding.keyModifiers)")
        if pressed {
            state.pressedStartedAt = ProcessInfo.processInfo.systemUptime
            state.pressedBinding = (keyCode: keyCode, modifiers: modifiers)
            KeyInjector.shared.pressRaw(keyCode, modifiers: modifiers)
        } else {
            let bindingToRelease = state.pressedBinding ?? (keyCode: keyCode, modifiers: modifiers)
            KeyInjector.shared.releaseRaw(bindingToRelease.keyCode, modifiers: bindingToRelease.modifiers)
            state.pressedBinding = nil
            state.autoReleaseWorkItem?.cancel()
            state.autoReleaseWorkItem = nil
            state.pressedStartedAt = nil
        }
        updateAppearance(animated: true)
    }

    private func setCurrentPressed(_ pressed: Bool, source: PressSource, input: ResolvedInput) {
        if usesSimultaneousMultiKey(input) {
            setSimultaneousPressed(pressed, source: source, input: input)
        } else {
            setPressed(pressed, source: source, input: input)
        }
    }

    private func setSimultaneousPressed(_ pressed: Bool, source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        if pressed {
            state.autoReleaseWorkItem?.cancel()
            state.autoReleaseWorkItem = nil
        }
        guard pressed != state.isPressed else { return }
        state.isPressed = pressed
        debugLog("[Button \(button.rawValue)] setSimultaneousPressed=\(pressed) source=\(source) keyBindings=\(input.bindings.map(\.keyCode)) mode=\(input.mode.rawValue) compatibilityMode=\(compatibilityModeEnabled)")
        debugLatencyLog("[Button \(button.rawValue)] setSimultaneousPressed=\(pressed) source=\(source) keyBindings=\(input.bindings.map(\.keyCode))")

        if pressed {
            state.pressedStartedAt = ProcessInfo.processInfo.systemUptime
            state.pressedBindings = uniqueInputBindings(input.bindings)

            for binding in state.pressedBindings {
                KeyInjector.shared.pressRaw(binding.keyCode, modifiers: binding.modifiers)
            }
        } else {
            releasePressedBindings(state)
        }

        updateAppearance(animated: true)
    }

    private func releaseState(_ state: PressState) {
        state.autoReleaseWorkItem?.cancel()
        state.autoReleaseWorkItem = nil
        state.sequenceRepeatWorkItem?.cancel()
        state.sequenceRepeatWorkItem = nil
        stopSequentialPlayback(state)
        state.turboStepWorkItem?.cancel()
        state.turboStepWorkItem = nil
        state.turboGeneration &+= 1
        releaseTurboBindings(state)
        state.pressedStartedAt = nil

        if let pressedBinding = state.pressedBinding {
            KeyInjector.shared.releaseRaw(pressedBinding.keyCode, modifiers: pressedBinding.modifiers)
            state.pressedBinding = nil
        }

        releasePressedBindings(state)
        state.isPressed = false
    }

    private func releasePressedBindings(_ state: PressState) {
        for binding in state.pressedBindings.reversed() {
            KeyInjector.shared.releaseRaw(binding.keyCode, modifiers: binding.modifiers)
        }

        state.pressedBindings = []
        state.autoReleaseWorkItem?.cancel()
        state.autoReleaseWorkItem = nil
        state.pressedStartedAt = nil
        state.isPressed = false
    }

    private func uniqueInputBindings(_ bindings: [ButtonKeyBinding]) -> [(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags)] {
        var seenBindings = Set<ButtonKeyBinding>()
        return bindings.compactMap { binding in
            guard seenBindings.insert(binding).inserted else {
                return nil
            }

            return (
                keyCode: CGKeyCode(binding.keyCode),
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
            )
        }
    }

    deinit {
        releaseIfNeeded()
    }

    // MARK: - Drawing

    private func updateAppearance(animated _: Bool) {
        let palette = visualPalette ?? refreshVisualPalette()
        let nextState = currentVisualState()
        let previousState = lastAppliedVisualState
        let shouldUpdatePaths = previousState.map { $0.visualScale != nextState.visualScale } ?? true
        let shouldUpdateFill = previousState.map {
            $0.fillState != nextState.fillState || $0.isJoystick != nextState.isJoystick
        } ?? true
        let shouldUpdateOutline = previousState.map {
            $0.outlineState != nextState.outlineState || $0.isJoystick != nextState.isJoystick
        } ?? true
        let shouldUpdateJoystick = nextState.isJoystick && (
            previousState.map {
                $0.isJoystick != nextState.isJoystick
                    || $0.joystickOffset != nextState.joystickOffset
                    || $0.isJoystickCaptured != nextState.isJoystickCaptured
                    || $0.isJoystickDragActive != nextState.isJoystickDragActive
                    || $0.lockedJoystickDirection != nextState.lockedJoystickDirection
                    || $0.outlineState != nextState.outlineState
            } ?? true
        )
        let shouldUpdateVisibility = previousState.map { $0.isJoystick != nextState.isJoystick } ?? true

        if let previousState, previousState == nextState {
            publishJoystickCaptureHUDStateIfNeeded()
            return
        }

        // Button visuals need to track mouse-down/drag instantly; implicit layer animations make outlines feel delayed.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        visualScale = nextState.visualScale

        if shouldUpdatePaths {
            updateShapePath()
        }

        if shouldUpdateVisibility {
            updateLayerVisibility(isJoystick: nextState.isJoystick)
        }

        if nextState.isJoystick {
            if shouldUpdateJoystick {
                updateJoystickLayers(baseColor: palette.baseColor)
            }
        } else {
            if shouldUpdateFill {
                shapeLayer.fillColor = fillColor(for: nextState.fillState, palette: palette)
            }

            if shouldUpdateOutline {
                applyOutline(nextState.outlineState, palette: palette)
            }
        }

        lastAppliedVisualState = nextState
        CATransaction.commit()

        publishJoystickCaptureHUDStateIfNeeded()

        if shouldUpdateOutline {
            CATransaction.flush()
        }
    }

    @discardableResult
    private func refreshVisualPalette() -> VisualPalette {
        let base = NSColor(hex: config.colorHex)
        let palette = VisualPalette(
            baseColor: base,
            standardFillColor: base.withAlphaComponent(0.75).cgColor,
            currentSubProfileFillColor: base.withAlphaComponent(0.32).cgColor,
            pressedFillColor: base.withAlphaComponent(1.0).cgColor,
            hoverOutlineColor: hoverOutlineColor(for: base).cgColor,
            toggleHoldOutlineColor: outlineColor(for: .toggleHold, baseColor: base).cgColor,
            turboOutlineColor: outlineColor(for: .turbo, baseColor: base).cgColor,
            dwellActionOutlineColor: outlineColor(for: .dwellAction, baseColor: base).cgColor
        )
        visualPalette = palette
        return palette
    }

    private func currentVisualState() -> ButtonVisualState {
        let fillState: FillState
        if isVisuallyPressed {
            fillState = .pressed
        } else if isCurrentSubProfileSwitch {
            fillState = .currentSubProfile
        } else {
            fillState = .standard
        }

        let outlineState: OutlineState
        if let activeModeOutline {
            outlineState = .active(activeModeOutline)
        } else if isHovered {
            outlineState = .hover
        } else {
            outlineState = .none
        }

        return ButtonVisualState(
            isJoystick: isJoystick,
            fillState: fillState,
            visualScale: isVisuallyPressed ? 0.92 : 1.0,
            outlineState: outlineState,
            joystickOffset: joystickOffset,
            isJoystickCaptured: isJoystickCaptured,
            isJoystickDragActive: isJoystickDragActive,
            lockedJoystickDirection: lockedJoystickDirection
        )
    }

    private func fillColor(for fillState: FillState, palette: VisualPalette) -> CGColor {
        switch fillState {
        case .standard:
            return palette.standardFillColor
        case .currentSubProfile:
            return palette.currentSubProfileFillColor
        case .pressed:
            return palette.pressedFillColor
        }
    }

    private func applyOutline(_ outlineState: OutlineState, palette: VisualPalette) {
        switch outlineState {
        case .none:
            outlineLayer.strokeColor = nil
            outlineLayer.lineWidth = 0
        case .hover:
            outlineLayer.strokeColor = palette.hoverOutlineColor
            outlineLayer.lineWidth = 2
        case .active(.toggleHold):
            outlineLayer.strokeColor = palette.toggleHoldOutlineColor
            outlineLayer.lineWidth = 3
        case .active(.turbo):
            outlineLayer.strokeColor = palette.turboOutlineColor
            outlineLayer.lineWidth = 3
        case .active(.dwellAction):
            outlineLayer.strokeColor = palette.dwellActionOutlineColor
            outlineLayer.lineWidth = 3
        }
    }

    private func updateLayerVisibility(isJoystick: Bool) {
        label.isHidden = isJoystick
        symbolImageView.isHidden = true
        shapeLayer.isHidden = isJoystick
        outlineLayer.isHidden = isJoystick
        joystickOuterLayer.isHidden = !isJoystick
        joystickKnobLayer.isHidden = !isJoystick
        joystickLockIndicatorLayer.isHidden = !isJoystick || lockedJoystickDirection == nil
    }

    private func updateShapePath() {
        shapeLayer.frame = bounds
        outlineLayer.frame = bounds
        let path = buttonPath(in: visualBounds)
        shapeLayer.path = path
        outlineLayer.path = path
    }

    private var visualBounds: CGRect {
        guard visualScale < 1, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let horizontalInset = bounds.width * (1 - visualScale) / 2
        let verticalInset = bounds.height * (1 - visualScale) / 2
        return bounds.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    private func updateSystemEventSymbol() {
        guard isSystemEvent || isDwellAction else {
            symbolImageView.image = nil
            symbolImageView.isHidden = true
            label.stringValue = config.resolvedDisplayLabel
            label.font = config.resolvedLabelFont
            label.textColor = NSColor(hex: config.labelColorHex)
            return
        }

        symbolImageView.image = nil
        symbolImageView.isHidden = true
        label.stringValue = config.resolvedDisplayLabel
        label.font = displayTextFont
        label.textColor = displayTextColor
    }

    private func updateJoystickLayers(baseColor: NSColor) {
        let showsJoystick = isJoystick
        label.isHidden = showsJoystick
        symbolImageView.isHidden = true
        joystickOuterLayer.isHidden = !showsJoystick
        joystickKnobLayer.isHidden = !showsJoystick
        joystickLockIndicatorLayer.isHidden = !showsJoystick || lockedJoystickDirection == nil
        shapeLayer.isHidden = showsJoystick
        outlineLayer.isHidden = showsJoystick

        guard showsJoystick else {
            return
        }

        let outerRect = joystickVisualOuterRect
        let isActiveJoystick = isJoystickCaptured || isJoystickDragActive
        joystickOuterLayer.frame = bounds
        joystickOuterLayer.path = CGPath(roundedRect: outerRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        joystickOuterLayer.fillColor = baseColor.withAlphaComponent(isActiveJoystick ? 0.42 : 0.26).cgColor
        joystickOuterLayer.strokeColor = isHovered
            ? (visualPalette ?? refreshVisualPalette()).hoverOutlineColor
            : NSColor.white.withAlphaComponent(isActiveJoystick ? 0.65 : 0.32).cgColor
        joystickOuterLayer.lineWidth = isHovered ? 2.5 : 2

        let knobDiameter = joystickVisualKnobDiameter
        let clampedOffset = joystickVisualOffset
        let knobRect = CGRect(
            x: bounds.midX + clampedOffset.x - knobDiameter / 2,
            y: bounds.midY + clampedOffset.y - knobDiameter / 2,
            width: knobDiameter,
            height: knobDiameter
        )
        joystickKnobLayer.frame = bounds
        joystickKnobLayer.path = CGPath(ellipseIn: knobRect, transform: nil)
        joystickKnobLayer.fillColor = baseColor.withAlphaComponent(isActiveJoystick ? 0.95 : 0.72).cgColor
        joystickKnobLayer.strokeColor = NSColor.white.withAlphaComponent(0.78).cgColor
        joystickKnobLayer.lineWidth = 1

        updateJoystickLockIndicatorLayer(baseColor: baseColor)
    }

    private func publishJoystickCaptureHUDStateIfNeeded() {
        let nextState = makeJoystickCaptureHUDState()
        guard nextState != lastPublishedJoystickCaptureHUDState else {
            return
        }

        lastPublishedJoystickCaptureHUDState = nextState
        onJoystickCaptureHUDChanged?(nextState)
    }

    private func makeJoystickCaptureHUDState() -> JoystickCaptureHUDState? {
        guard isJoystickCaptureMode, isJoystickCaptured else {
            return nil
        }

        let layer = activeJoystickLayer
        let components = activeJoystickDirection.map(joystickAxisComponents(for:)) ?? []
        let totalLayers = 1 + config.joystick.nestedLayers.count
        let leftClickAction = joystickLeftClickAction()
        let scrollUpAction = joystickScrollAction(for: .up)
        let scrollDownAction = joystickScrollAction(for: .down)

        return JoystickCaptureHUDState(
            layerText: "Layer \(currentJoystickLayerDisplayIndex) / \(max(1, totalLayers))",
            up: JoystickCaptureHUDState.Axis(
                label: bindingDisplayName(layer?.up ?? config.joystick.up),
                isActive: components.contains(.up)
            ),
            down: JoystickCaptureHUDState.Axis(
                label: bindingDisplayName(layer?.down ?? config.joystick.down),
                isActive: components.contains(.down)
            ),
            left: JoystickCaptureHUDState.Axis(
                label: bindingDisplayName(layer?.left ?? config.joystick.left),
                isActive: components.contains(.left)
            ),
            right: JoystickCaptureHUDState.Axis(
                label: bindingDisplayName(layer?.right ?? config.joystick.right),
                isActive: components.contains(.right)
            ),
            rows: [
                JoystickCaptureHUDState.MappingRow(
                    title: "Right click",
                    value: activeJoystickLayerIndex > 0 ? "Previous layer" : "Release",
                    isActive: flashedJoystickHUDControls.contains(.rightClick) || isJoystickCaptureReleasePending,
                    accent: .action
                ),
                JoystickCaptureHUDState.MappingRow(
                    title: "Left click",
                    value: triggerActionDisplayName(leftClickAction),
                    isActive: joystickLeftClickState.isPressed,
                    accent: actionAccent(for: leftClickAction)
                ),
                JoystickCaptureHUDState.MappingRow(
                    title: "Scroll up",
                    value: scrollActionDisplayName(scrollUpAction),
                    isActive: joystickScrollUpState.isPressed || flashedJoystickHUDControls.contains(.scrollUp),
                    accent: actionAccent(for: scrollUpAction)
                ),
                JoystickCaptureHUDState.MappingRow(
                    title: "Scroll down",
                    value: scrollActionDisplayName(scrollDownAction),
                    isActive: joystickScrollDownState.isPressed || flashedJoystickHUDControls.contains(.scrollDown),
                    accent: actionAccent(for: scrollDownAction)
                ),
            ]
        )
    }

    private func bindingDisplayName(_ binding: ButtonKeyBinding) -> String {
        ButtonConfig.keyDisplayName(
            code: binding.keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
        )
    }

    private func inputDisplayName(_ input: JoystickInputConfig) -> String {
        guard !input.keyBindings.isEmpty else {
            return "Off"
        }

        if input.keyBindings.count == 1, let binding = input.keyBindings.first {
            return bindingDisplayName(binding)
        }

        return "[" + input.keyBindings.map(bindingDisplayName).joined() + "]"
    }

    private func triggerActionDisplayName(_ action: JoystickTriggerAction) -> String {
        switch action.kind {
        case .off:
            return "Off"
        case .keyCombo:
            return inputDisplayName(action.input)
        case .nestedJoystick:
            return canEnterNestedJoystickLayer ? "Next layer" : "Next layer unavailable"
        }
    }

    private func scrollActionDisplayName(_ action: JoystickScrollAction) -> String {
        switch action.kind {
        case .off:
            return "Off"
        case .axisLock:
            return "Axis lock"
        case .keyCombo:
            return inputDisplayName(action.input)
        case .nestedJoystick:
            return canEnterNestedJoystickLayer ? "Next layer" : "Next layer unavailable"
        }
    }

    private func actionAccent(for action: JoystickTriggerAction) -> JoystickCaptureHUDState.ActionAccent? {
        guard action.kind == .keyCombo else {
            return action.kind == .nestedJoystick ? .action : nil
        }

        return actionAccent(for: action.input)
    }

    private func actionAccent(for action: JoystickScrollAction) -> JoystickCaptureHUDState.ActionAccent? {
        switch action.kind {
        case .off:
            return nil
        case .axisLock, .nestedJoystick:
            return .action
        case .keyCombo:
            return actionAccent(for: action.input)
        }
    }

    private func actionAccent(for input: JoystickInputConfig) -> JoystickCaptureHUDState.ActionAccent? {
        switch input.interactionMode {
        case .momentary:
            return nil
        case .toggleHold:
            return .toggleHold
        case .turbo:
            return .turbo
        }
    }

    private func joystickAxisComponents(for direction: JoystickDirection) -> Set<JoystickDirection> {
        switch direction {
        case .up:
            return [.up]
        case .upRight:
            return [.up, .right]
        case .right:
            return [.right]
        case .downRight:
            return [.down, .right]
        case .down:
            return [.down]
        case .downLeft:
            return [.down, .left]
        case .left:
            return [.left]
        case .upLeft:
            return [.up, .left]
        }
    }

    private func flashJoystickHUDControl(_ control: JoystickHUDControl) {
        joystickHUDFlashWorkItems[control]?.cancel()
        flashedJoystickHUDControls.insert(control)
        updateAppearance(animated: false)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            self.flashedJoystickHUDControls.remove(control)
            self.joystickHUDFlashWorkItems[control] = nil
            self.updateAppearance(animated: false)
        }
        joystickHUDFlashWorkItems[control] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func clearJoystickHUDFlashes() {
        joystickHUDFlashWorkItems.values.forEach { $0.cancel() }
        joystickHUDFlashWorkItems.removeAll()
        flashedJoystickHUDControls.removeAll()
    }

    private func updateJoystickLockIndicatorLayer(baseColor _: NSColor) {
        guard let lockedJoystickDirection else {
            joystickLockIndicatorLayer.isHidden = true
            return
        }

        let frameSize = max(24, min(44, min(visualBounds.width, visualBounds.height) * 0.36))
        let center = joystickLockIndicatorCenter(for: lockedJoystickDirection, frameSize: frameSize)
        joystickLockIndicatorLayer.isHidden = false
        joystickLockIndicatorLayer.frame = CGRect(
            x: center.x - frameSize / 2,
            y: center.y - frameSize / 2,
            width: frameSize,
            height: frameSize
        )
        joystickLockIndicatorLayer.backgroundColor = NSColor.clear.cgColor
        joystickLockIndicatorLayer.contentsScale = window?.backingScaleFactor ?? shapeLayer.contentsScale

        let localBounds = CGRect(origin: .zero, size: CGSize(width: frameSize, height: frameSize))
        let scale = frameSize / 1024
        var svgTransform = CGAffineTransform(translationX: 0, y: frameSize).scaledBy(x: scale, y: -scale)
        let ringLineWidth = max(1.5, 50 * scale)
        joystickLockIndicatorRingLayer.frame = localBounds
        joystickLockIndicatorRingLayer.path = CGPath(
            ellipseIn: CGRect(x: 87, y: 87, width: 850, height: 850),
            transform: &svgTransform
        )
        joystickLockIndicatorRingLayer.fillColor = NSColor.black.withAlphaComponent(0.72).cgColor
        joystickLockIndicatorRingLayer.strokeColor = NSColor.white.cgColor
        joystickLockIndicatorRingLayer.lineWidth = ringLineWidth

        var bodyTransform = CGAffineTransform(translationX: 0, y: frameSize).scaledBy(x: scale, y: -scale)
        let lockBody = CGRect(x: 332, y: 462, width: 359.538452, height: 342)
        joystickLockIndicatorBodyLayer.frame = localBounds
        joystickLockIndicatorBodyLayer.path = CGPath(
            roundedRect: lockBody,
            cornerWidth: 40,
            cornerHeight: 40,
            transform: &bodyTransform
        )
        joystickLockIndicatorBodyLayer.fillColor = NSColor.white.cgColor
        joystickLockIndicatorBodyLayer.strokeColor = nil
        joystickLockIndicatorBodyLayer.lineWidth = 0

        let shackleTransform = CGAffineTransform(translationX: 0, y: frameSize).scaledBy(x: scale, y: -scale)
        let shacklePath = CGMutablePath()
        shacklePath.move(to: CGPoint(x: 387, y: 540), transform: shackleTransform)
        shacklePath.addCurve(
            to: CGPoint(x: 496, y: 649),
            control1: CGPoint(x: 387, y: 600.199036),
            control2: CGPoint(x: 435.800964, y: 649),
            transform: shackleTransform
        )
        shacklePath.addLine(to: CGPoint(x: 528, y: 649), transform: shackleTransform)
        shacklePath.addCurve(
            to: CGPoint(x: 637, y: 540),
            control1: CGPoint(x: 588.199036, y: 649),
            control2: CGPoint(x: 637, y: 600.199036),
            transform: shackleTransform
        )
        shacklePath.addLine(to: CGPoint(x: 637, y: 329.100952), transform: shackleTransform)
        shacklePath.addCurve(
            to: CGPoint(x: 528, y: 220.100952),
            control1: CGPoint(x: 637, y: 268.901855),
            control2: CGPoint(x: 588.199036, y: 220.100952),
            transform: shackleTransform
        )
        shacklePath.addLine(to: CGPoint(x: 496, y: 220.100952), transform: shackleTransform)
        shacklePath.addCurve(
            to: CGPoint(x: 387, y: 329.100952),
            control1: CGPoint(x: 435.800964, y: 220.100952),
            control2: CGPoint(x: 387, y: 268.901855),
            transform: shackleTransform
        )
        shacklePath.closeSubpath()
        joystickLockIndicatorShackleLayer.frame = localBounds
        joystickLockIndicatorShackleLayer.path = shacklePath
        joystickLockIndicatorShackleLayer.fillColor = nil
        joystickLockIndicatorShackleLayer.strokeColor = NSColor.white.cgColor
        joystickLockIndicatorShackleLayer.lineWidth = max(1.25, 32 * scale)
        joystickLockIndicatorShackleLayer.lineCap = .round
        joystickLockIndicatorShackleLayer.lineJoin = .round
    }

    private func joystickLockIndicatorCenter(for direction: JoystickDirection, frameSize: CGFloat) -> CGPoint {
        let outerRect = joystickVisualOuterRect
        let x: CGFloat
        let y: CGFloat

        switch direction {
        case .up, .down:
            x = outerRect.midX
        case .upRight, .right, .downRight:
            x = outerRect.maxX
        case .upLeft, .left, .downLeft:
            x = outerRect.minX
        }

        switch direction {
        case .left, .right:
            y = outerRect.midY
        case .up, .upRight, .upLeft:
            y = outerRect.maxY
        case .down, .downRight, .downLeft:
            y = outerRect.minY
        }

        return CGPoint(x: x, y: y)
    }

    private var joystickVisualOffset: CGPoint {
        let travelLimits = joystickVisualTravelLimits
        var offset = clampedJoystickOffset(joystickOffset, travelLimits: travelLimits)
        guard !isJoystickCaptured else {
            return offset
        }

        guard let lockedJoystickDirection else {
            return offset
        }

        switch lockedJoystickDirection {
        case .up, .upRight, .upLeft:
            offset.y = travelLimits.height
        case .down, .downRight, .downLeft:
            offset.y = -travelLimits.height
        case .left, .right:
            break
        }

        switch lockedJoystickDirection {
        case .right, .upRight, .downRight:
            offset.x = travelLimits.width
        case .left, .upLeft, .downLeft:
            offset.x = -travelLimits.width
        case .up, .down:
            break
        }
        return offset
    }

    private func clampedJoystickOffset(_ offset: CGPoint) -> CGPoint {
        clampedJoystickOffset(offset, travelLimits: joystickTravelLimits)
    }

    private func clampedJoystickOffset(_ offset: CGPoint, travelLimits: CGSize) -> CGPoint {
        return CGPoint(
            x: min(max(offset.x, -travelLimits.width), travelLimits.width),
            y: min(max(offset.y, -travelLimits.height), travelLimits.height)
        )
    }

    private func clampedJoystickOffsetToTravelEllipse(_ offset: CGPoint) -> CGPoint {
        let travelLimits = joystickTravelLimits
        guard travelLimits.width > 0, travelLimits.height > 0 else {
            return .zero
        }

        let normalizedX = offset.x / travelLimits.width
        let normalizedY = offset.y / travelLimits.height
        let distance = hypot(normalizedX, normalizedY)
        guard distance > 1 else {
            return offset
        }

        return CGPoint(
            x: (normalizedX / distance) * travelLimits.width,
            y: (normalizedY / distance) * travelLimits.height
        )
    }

    private var joystickOuterRect: CGRect {
        let inset = max(
            CGFloat(ButtonSizing.joystickMinimumOuterInset),
            min(bounds.width, bounds.height) * CGFloat(ButtonSizing.joystickOuterInsetFraction)
        )
        return bounds.insetBy(dx: inset, dy: inset)
    }

    private var joystickVisualOuterRect: CGRect {
        let rect = visualBounds
        let inset = max(
            CGFloat(ButtonSizing.joystickMinimumOuterInset),
            min(rect.width, rect.height) * CGFloat(ButtonSizing.joystickOuterInsetFraction)
        )
        return rect.insetBy(dx: inset, dy: inset)
    }

    private var joystickKnobDiameter: CGFloat {
        let shortestSide = min(bounds.width, bounds.height)
        guard shortestSide > 0 else {
            return CGFloat(ButtonSizing.joystickMinimumKnobDiameter)
        }

        let scaledDiameter = shortestSide * CGFloat(ButtonSizing.joystickKnobDiameterFraction)
        let boundedDiameter = min(
            max(CGFloat(ButtonSizing.joystickMinimumKnobDiameter), scaledDiameter),
            CGFloat(ButtonSizing.joystickMaximumKnobDiameter)
        )
        return min(boundedDiameter, max(6, shortestSide * 0.45))
    }

    private var joystickVisualKnobDiameter: CGFloat {
        let shortestSide = min(visualBounds.width, visualBounds.height)
        guard shortestSide > 0 else {
            return CGFloat(ButtonSizing.joystickMinimumKnobDiameter)
        }

        let scaledDiameter = shortestSide * CGFloat(ButtonSizing.joystickKnobDiameterFraction)
        let boundedDiameter = min(
            max(CGFloat(ButtonSizing.joystickMinimumKnobDiameter), scaledDiameter),
            CGFloat(ButtonSizing.joystickMaximumKnobDiameter)
        )
        return min(boundedDiameter, max(6, shortestSide * 0.45))
    }

    private var joystickTravelLimits: CGSize {
        let outerRect = joystickOuterRect
        let knobRadius = joystickKnobDiameter / 2
        return CGSize(
            width: max(0, outerRect.width / 2 - knobRadius),
            height: max(0, outerRect.height / 2 - knobRadius)
        )
    }

    private var joystickVisualTravelLimits: CGSize {
        let outerRect = joystickVisualOuterRect
        let knobRadius = joystickVisualKnobDiameter / 2
        return CGSize(
            width: max(0, outerRect.width / 2 - knobRadius),
            height: max(0, outerRect.height / 2 - knobRadius)
        )
    }

    private var effectiveJoystickDeadzoneRadius: CGFloat {
        let shortestTravel = min(joystickTravelLimits.width, joystickTravelLimits.height)
        guard shortestTravel > 0 else {
            return Self.joystickDeadzoneRadius
        }

        return min(Self.joystickDeadzoneRadius, max(4, shortestTravel * 0.45))
    }

    private func buttonPath(in rect: CGRect) -> CGPath {
        switch config.shape {
        case .roundedRectangle:
            return CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        case .square:
            return CGPath(rect: rect, transform: nil)
        case .oval:
            return CGPath(ellipseIn: rect, transform: nil)
        }
    }

    private func containsInteractivePoint(_ point: CGPoint) -> Bool {
        guard bounds.contains(point) else {
            return false
        }

        if isJoystick {
            return joystickOuterRect.contains(point)
        }

        switch config.shape {
        case .roundedRectangle:
            return buttonPath(in: bounds).contains(point)
        case .square:
            return true
        case .oval:
            guard bounds.width > 0, bounds.height > 0 else {
                return false
            }

            let normalizedX = (point.x - bounds.midX) / (bounds.width / 2)
            let normalizedY = (point.y - bounds.midY) / (bounds.height / 2)
            return (normalizedX * normalizedX) + (normalizedY * normalizedY) <= 1
        }
    }

}
