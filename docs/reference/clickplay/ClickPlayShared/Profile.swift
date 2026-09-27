import Foundation

// MARK: - Button Model Enums

enum ButtonInteractionMode: String, Codable, Equatable {
    case momentary
    case toggleHold
    case turbo
}

enum TurboConfiguration {
    static let defaultClicksPerSecond = 15
    static let minimumClicksPerSecond = 1
    static let maximumClicksPerSecond = 30
    static let tapDuration: TimeInterval = 0.033

    static func normalizedClicksPerSecond(_ value: Int) -> Int {
        min(max(value, minimumClicksPerSecond), maximumClicksPerSecond)
    }
}

enum ButtonShape: String, Codable {
    case roundedRectangle
    case square
    case oval
}

enum ButtonType: String, Codable {
    case keyboard
    case joystick
    case systemEvent
    case dwellAction
}

enum JoystickOperationMode: String, Codable, Equatable {
    case capture
    case clickDrag
}

enum JoystickAxisLockMode: String, Codable, Equatable {
    case off
    case scrollWheel
    case holdDirection
}

// MARK: - Sizing and Coordinates

enum ButtonSizing {
    static let minimumButtonWidth = 20.0
    static let minimumButtonHeight = 14.0
    static let minimumJoystickWidth = 40.0
    static let minimumJoystickHeight = 40.0
    static let joystickOuterInsetFraction = 0.08
    static let joystickMinimumOuterInset = 4.0
    static let joystickKnobDiameterFraction = 0.26
    static let joystickMinimumKnobDiameter = 10.0
    static let joystickMaximumKnobDiameter = 32.0

    static func minimumSize(for type: ButtonType) -> (width: Double, height: Double) {
        switch type {
        case .keyboard:
            return (minimumButtonWidth, minimumButtonHeight)
        case .joystick:
            return (minimumJoystickWidth, minimumJoystickHeight)
        case .systemEvent:
            return (minimumButtonWidth, minimumButtonHeight)
        case .dwellAction:
            return (minimumButtonWidth, minimumButtonWidth)
        }
    }
}

// MARK: - Input Bindings and System Events

enum EditorCoordinateMode: String, Codable {
    case legacyTopLeft
    case centered
}

enum MultiKeyActivationMode: String, Codable, Equatable {
    case sequential
    case simultaneous
}

struct ButtonKeyBinding: Codable, Hashable {
    var keyCode: Int
    var keyModifiers: Int
}

enum SystemEvent: String, Codable, Equatable {
    case brightnessDown
    case brightnessUp
    case volumeDown
    case volumeUp
    case mute
    case playPause
    case nextTrack
    case previousTrack
    case launchpad
    case missionControl
}

enum SystemEventIconSize: String, Codable, Equatable {
    case extraSmall
    case small
    case medium
    case large
    case extraLarge
}

enum DwellActionKind: String, Codable, Equatable {
    case leftClick
    case doubleClick
    case rightClick
    case middleClick
    case holdLeftClick
    case holdRightClick
    case holdMiddleClick
    case scrollUp
    case scrollDown
}

extension DwellActionKind {
    var displayName: String {
        switch self {
        case .leftClick:
            return "Left Click"
        case .doubleClick:
            return "Double Click"
        case .rightClick:
            return "Right Click"
        case .middleClick:
            return "Middle Click"
        case .holdLeftClick:
            return "Hold Left Click"
        case .holdRightClick:
            return "Hold Right Click"
        case .holdMiddleClick:
            return "Hold Middle Click"
        case .scrollUp:
            return "Scroll Up"
        case .scrollDown:
            return "Scroll Down"
        }
    }

    var fallbackLabel: String {
        switch self {
        case .leftClick:
            return "􀭆"
        case .doubleClick:
            return "􀭇"
        case .rightClick:
            return "􀭈"
        case .middleClick:
            return "􂲥"
        case .holdLeftClick:
            return "􀣡"
        case .holdRightClick:
            return "􀯪"
        case .holdMiddleClick:
            return "􀬂"
        case .scrollUp:
            return "􃗆"
        case .scrollDown:
            return "􃗈"
        }
    }
}

struct DwellActionConfig: Codable, Equatable {
    static let defaultTimerDuration = 2.0
    static let defaultMovementTolerance = 5.0

    var kind: DwellActionKind
    var timerDuration: Double
    var movementTolerance: Double

    private enum CodingKeys: String, CodingKey {
        case kind
        case timerDuration
        case movementTolerance
    }

    static let `default` = DwellActionConfig(
        kind: .leftClick,
        timerDuration: defaultTimerDuration,
        movementTolerance: defaultMovementTolerance
    )

    init(
        kind: DwellActionKind = .leftClick,
        timerDuration: Double = DwellActionConfig.defaultTimerDuration,
        movementTolerance: Double = DwellActionConfig.defaultMovementTolerance
    ) {
        self.kind = kind
        self.timerDuration = max(0.1, timerDuration)
        self.movementTolerance = max(0, movementTolerance)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(DwellActionKind.self, forKey: .kind) ?? .leftClick
        timerDuration = max(
            0.1,
            try container.decodeIfPresent(Double.self, forKey: .timerDuration) ?? Self.defaultTimerDuration
        )
        movementTolerance = max(
            0,
            try container.decodeIfPresent(Double.self, forKey: .movementTolerance) ?? Self.defaultMovementTolerance
        )
    }
}

struct JoystickInputConfig: Codable, Equatable {
    var keyBindings: [ButtonKeyBinding]
    var interactionMode: ButtonInteractionMode
    var multiKeyActivationMode: MultiKeyActivationMode
    var turboClicksPerSecond: Int

    private enum CodingKeys: String, CodingKey {
        case keyBindings
        case interactionMode
        case multiKeyActivationMode
        case turboClicksPerSecond
    }

    init(
        keyBindings: [ButtonKeyBinding],
        interactionMode: ButtonInteractionMode,
        multiKeyActivationMode: MultiKeyActivationMode,
        turboClicksPerSecond: Int = TurboConfiguration.defaultClicksPerSecond
    ) {
        self.keyBindings = keyBindings
        self.interactionMode = interactionMode
        self.multiKeyActivationMode = multiKeyActivationMode
        self.turboClicksPerSecond = TurboConfiguration.normalizedClicksPerSecond(turboClicksPerSecond)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyBindings = try container.decodeIfPresent([ButtonKeyBinding].self, forKey: .keyBindings) ?? []
        interactionMode = try container.decodeIfPresent(ButtonInteractionMode.self, forKey: .interactionMode) ?? .momentary
        multiKeyActivationMode = try container.decodeIfPresent(MultiKeyActivationMode.self, forKey: .multiKeyActivationMode) ?? .sequential
        turboClicksPerSecond = TurboConfiguration.normalizedClicksPerSecond(
            try container.decodeIfPresent(Int.self, forKey: .turboClicksPerSecond)
                ?? TurboConfiguration.defaultClicksPerSecond
        )
    }

    static let empty = JoystickInputConfig(
        keyBindings: [],
        interactionMode: .momentary,
        multiKeyActivationMode: .sequential
    )
}

enum JoystickTriggerActionKind: String, Codable, Equatable {
    case off
    case keyCombo
    case nestedJoystick
}

struct JoystickTriggerAction: Codable, Equatable {
    var kind: JoystickTriggerActionKind
    var input: JoystickInputConfig

    static let off = JoystickTriggerAction(kind: .off, input: .empty)
    static let nestedJoystick = JoystickTriggerAction(kind: .nestedJoystick, input: .empty)
}

enum JoystickScrollActionKind: String, Codable, Equatable {
    case off
    case axisLock
    case keyCombo
    case nestedJoystick
}

struct JoystickScrollAction: Codable, Equatable {
    var kind: JoystickScrollActionKind
    var input: JoystickInputConfig

    static let off = JoystickScrollAction(kind: .off, input: .empty)
    static let axisLock = JoystickScrollAction(kind: .axisLock, input: .empty)
    static let nestedJoystick = JoystickScrollAction(kind: .nestedJoystick, input: .empty)
}

struct JoystickLayerConfig: Codable, Equatable {
    var up: ButtonKeyBinding
    var down: ButtonKeyBinding
    var left: ButtonKeyBinding
    var right: ButtonKeyBinding
    var leftClickAction: JoystickTriggerAction
    var scrollUpAction: JoystickScrollAction
    var scrollDownAction: JoystickScrollAction

    static let defaultBindings = JoystickLayerConfig(
        up: ButtonKeyBinding(keyCode: 13, keyModifiers: 0),
        down: ButtonKeyBinding(keyCode: 1, keyModifiers: 0),
        left: ButtonKeyBinding(keyCode: 0, keyModifiers: 0),
        right: ButtonKeyBinding(keyCode: 2, keyModifiers: 0),
        leftClickAction: .off,
        scrollUpAction: .off,
        scrollDownAction: .off
    )
}

/// Four directional bindings plus optional click/scroll behavior for joystick-style controls.
struct JoystickConfig: Codable, Equatable {
    static let maxLayerCount = 5
    static let defaultAxisLockHoldDuration = 5.0
    static let defaultAxisUnlockHoldDuration = 1.0
    static let defaultReleaseDelayMilliseconds = 0
    static let maximumReleaseDelayMilliseconds = 1_000

    var operationMode: JoystickOperationMode
    var axisLockMode: JoystickAxisLockMode
    var axisLockHoldDuration: Double
    var axisUnlockHoldDuration: Double
    var releaseDelayMilliseconds: Int
    var up: ButtonKeyBinding
    var down: ButtonKeyBinding
    var left: ButtonKeyBinding
    var right: ButtonKeyBinding
    var leftClickAction: JoystickTriggerAction
    var rightClickAction: JoystickTriggerAction
    var scrollUpAction: JoystickScrollAction
    var scrollDownAction: JoystickScrollAction
    var nestedLayers: [JoystickLayerConfig]

    private enum CodingKeys: String, CodingKey {
        case operationMode
        case axisLockMode
        case axisLockHoldDuration
        case axisUnlockHoldDuration
        case releaseDelayMilliseconds
        case up
        case down
        case left
        case right
        case leftClickAction
        case rightClickAction
        case leftClickInput
        case rightClickInput
        case scrollUpAction
        case scrollDownAction
        case nestedLayers
    }

    static let defaultBindings = JoystickConfig(
        operationMode: .capture,
        axisLockMode: .scrollWheel,
        axisLockHoldDuration: defaultAxisLockHoldDuration,
        axisUnlockHoldDuration: defaultAxisUnlockHoldDuration,
        releaseDelayMilliseconds: defaultReleaseDelayMilliseconds,
        up: ButtonKeyBinding(keyCode: 13, keyModifiers: 0),
        down: ButtonKeyBinding(keyCode: 1, keyModifiers: 0),
        left: ButtonKeyBinding(keyCode: 0, keyModifiers: 0),
        right: ButtonKeyBinding(keyCode: 2, keyModifiers: 0),
        leftClickAction: .off,
        rightClickAction: .off,
        scrollUpAction: .off,
        scrollDownAction: .off,
        nestedLayers: []
    )

    init(
        operationMode: JoystickOperationMode = .capture,
        axisLockMode: JoystickAxisLockMode = .scrollWheel,
        axisLockHoldDuration: Double = JoystickConfig.defaultAxisLockHoldDuration,
        axisUnlockHoldDuration: Double = JoystickConfig.defaultAxisUnlockHoldDuration,
        releaseDelayMilliseconds: Int = JoystickConfig.defaultReleaseDelayMilliseconds,
        up: ButtonKeyBinding,
        down: ButtonKeyBinding,
        left: ButtonKeyBinding,
        right: ButtonKeyBinding,
        leftClickAction: JoystickTriggerAction = .off,
        rightClickAction: JoystickTriggerAction = .off,
        scrollUpAction: JoystickScrollAction = .off,
        scrollDownAction: JoystickScrollAction = .off,
        nestedLayers: [JoystickLayerConfig] = []
    ) {
        self.operationMode = operationMode
        self.axisLockMode = axisLockMode
        self.axisLockHoldDuration = axisLockHoldDuration
        self.axisUnlockHoldDuration = axisUnlockHoldDuration
        self.releaseDelayMilliseconds = Self.normalizedReleaseDelayMilliseconds(releaseDelayMilliseconds)
        self.up = up
        self.down = down
        self.left = left
        self.right = right
        self.leftClickAction = leftClickAction
        self.rightClickAction = rightClickAction
        self.scrollUpAction = scrollUpAction
        self.scrollDownAction = scrollDownAction
        self.nestedLayers = Array(nestedLayers.prefix(Self.maxLayerCount - 1))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operationMode = try container.decodeIfPresent(JoystickOperationMode.self, forKey: .operationMode) ?? .capture
        axisLockMode = try container.decodeIfPresent(JoystickAxisLockMode.self, forKey: .axisLockMode) ?? .scrollWheel
        axisLockHoldDuration = try container.decodeIfPresent(Double.self, forKey: .axisLockHoldDuration) ?? Self.defaultAxisLockHoldDuration
        axisUnlockHoldDuration = try container.decodeIfPresent(Double.self, forKey: .axisUnlockHoldDuration) ?? Self.defaultAxisUnlockHoldDuration
        releaseDelayMilliseconds = Self.normalizedReleaseDelayMilliseconds(
            try container.decodeIfPresent(Int.self, forKey: .releaseDelayMilliseconds)
                ?? Self.defaultReleaseDelayMilliseconds
        )
        up = try container.decode(ButtonKeyBinding.self, forKey: .up)
        down = try container.decode(ButtonKeyBinding.self, forKey: .down)
        left = try container.decode(ButtonKeyBinding.self, forKey: .left)
        right = try container.decode(ButtonKeyBinding.self, forKey: .right)
        leftClickAction = try container.decodeIfPresent(JoystickTriggerAction.self, forKey: .leftClickAction)
            ?? Self.triggerAction(fromLegacyInput: try container.decodeIfPresent(JoystickInputConfig.self, forKey: .leftClickInput))
        rightClickAction = try container.decodeIfPresent(JoystickTriggerAction.self, forKey: .rightClickAction)
            ?? Self.triggerAction(fromLegacyInput: try container.decodeIfPresent(JoystickInputConfig.self, forKey: .rightClickInput))
        scrollUpAction = try container.decodeIfPresent(JoystickScrollAction.self, forKey: .scrollUpAction) ?? .off
        scrollDownAction = try container.decodeIfPresent(JoystickScrollAction.self, forKey: .scrollDownAction) ?? .off
        nestedLayers = Array(
            (try container.decodeIfPresent([JoystickLayerConfig].self, forKey: .nestedLayers) ?? [])
                .prefix(Self.maxLayerCount - 1)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operationMode, forKey: .operationMode)
        try container.encode(axisLockMode, forKey: .axisLockMode)
        try container.encode(axisLockHoldDuration, forKey: .axisLockHoldDuration)
        try container.encode(axisUnlockHoldDuration, forKey: .axisUnlockHoldDuration)
        try container.encode(Self.normalizedReleaseDelayMilliseconds(releaseDelayMilliseconds), forKey: .releaseDelayMilliseconds)
        try container.encode(up, forKey: .up)
        try container.encode(down, forKey: .down)
        try container.encode(left, forKey: .left)
        try container.encode(right, forKey: .right)
        try container.encode(leftClickAction, forKey: .leftClickAction)
        try container.encode(rightClickAction, forKey: .rightClickAction)
        try container.encode(legacyInput(from: leftClickAction), forKey: .leftClickInput)
        try container.encode(legacyInput(from: rightClickAction), forKey: .rightClickInput)
        try container.encode(scrollUpAction, forKey: .scrollUpAction)
        try container.encode(scrollDownAction, forKey: .scrollDownAction)
        try container.encode(Array(nestedLayers.prefix(Self.maxLayerCount - 1)), forKey: .nestedLayers)
    }

    static func normalizedReleaseDelayMilliseconds(_ value: Int) -> Int {
        min(max(0, value), maximumReleaseDelayMilliseconds)
    }

    private static func triggerAction(fromLegacyInput input: JoystickInputConfig?) -> JoystickTriggerAction {
        guard let input, !input.keyBindings.isEmpty else {
            return .off
        }

        return JoystickTriggerAction(kind: .keyCombo, input: input)
    }

    private func legacyInput(from action: JoystickTriggerAction) -> JoystickInputConfig {
        action.kind == .keyCombo ? action.input : .empty
    }
}

/// Codable button action payload that preserves old keyboard-only profiles by defaulting missing type to keyboard.
enum ButtonAction: Codable, Equatable {
    case keyboard
    case systemEvent(SystemEvent)
    case subProfileSwitch(UUID)

    private enum CodingKeys: String, CodingKey {
        case type
        case systemEvent
        case targetSubProfileID
    }

    private enum ActionType: String, Codable {
        case keyboard
        case systemEvent
        case subProfileSwitch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(ActionType.self, forKey: .type) ?? .keyboard

        switch type {
        case .keyboard:
            self = .keyboard
        case .systemEvent:
            self = .systemEvent(try container.decodeIfPresent(SystemEvent.self, forKey: .systemEvent) ?? .brightnessDown)
        case .subProfileSwitch:
            if let targetID = try container.decodeIfPresent(UUID.self, forKey: .targetSubProfileID) {
                self = .subProfileSwitch(targetID)
            } else {
                self = .keyboard
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .keyboard:
            try container.encode(ActionType.keyboard, forKey: .type)
        case .systemEvent(let systemEvent):
            try container.encode(ActionType.systemEvent, forKey: .type)
            try container.encode(systemEvent, forKey: .systemEvent)
        case .subProfileSwitch(let targetID):
            try container.encode(ActionType.subProfileSwitch, forKey: .type)
            try container.encode(targetID, forKey: .targetSubProfileID)
        }
    }

    var targetSubProfileID: UUID? {
        if case .subProfileSwitch(let targetID) = self {
            return targetID
        }

        return nil
    }

    var systemEvent: SystemEvent? {
        if case .systemEvent(let systemEvent) = self {
            return systemEvent
        }

        return nil
    }

    var isProtectedSwitch: Bool {
        targetSubProfileID != nil
    }
}

// MARK: - ButtonConfig
// Per-button layout and appearance settings stored in a profile.

struct ButtonConfig: Codable {
    var type: ButtonType
    var x: Double           // center X, as fraction of pad width  (0.0–1.0)
    var y: Double           // center Y, as fraction of pad height (0.0–1.0)
    var width: Double       // as fraction of pad width
    var height: Double      // as fraction of pad height
    var editorWidth: Double
    var editorHeight: Double
    var colorHex: String    // "#RRGGBB"
    var keyCode: Int        // CGKeyCode raw value
    var keyModifiers: Int   // NSEvent.ModifierFlags raw value
    var keyBindings: [ButtonKeyBinding]
    var multiKeyActivationMode: MultiKeyActivationMode
    var label: String       // display label (can differ from button name)
    var labelFontSize: Double
    var labelBold: Bool
    var labelItalic: Bool
    var labelColorHex: String
    var shape: ButtonShape
    var enabled: Bool
    var interactionMode: ButtonInteractionMode
    var turboClicksPerSecond: Int
    var rightClickKeyBindings: [ButtonKeyBinding]?
    var rightClickFallsBackToPrimary: Bool
    var rightClickInteractionMode: ButtonInteractionMode?
    var rightClickTurboClicksPerSecond: Int
    var action: ButtonAction
    var joystick: JoystickConfig
    var systemEventIconSize: SystemEventIconSize
    var dwellAction: DwellActionConfig

    private enum CodingKeys: String, CodingKey {
        case type
        case x
        case y
        case width
        case height
        case editorWidth
        case editorHeight
        case colorHex
        case keyCode
        case keyModifiers
        case keyBindings
        case multiKeyActivationMode
        case label
        case labelFontSize
        case labelBold
        case labelItalic
        case labelColorHex
        case shape
        case enabled
        case interactionMode
        case turboClicksPerSecond
        case rightClickKeyBindings
        case rightClickFallsBackToPrimary
        case rightClickInteractionMode
        case rightClickTurboClicksPerSecond
        case action
        case joystick
        case systemEventIconSize
        case dwellAction
    }

    init(
        type: ButtonType = .keyboard,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        editorWidth: Double = 0,
        editorHeight: Double = 0,
        colorHex: String,
        keyCode: Int,
        keyModifiers: Int = 0,
        keyBindings: [ButtonKeyBinding]? = nil,
        multiKeyActivationMode: MultiKeyActivationMode = .sequential,
        label: String,
        labelFontSize: Double = 11,
        labelBold: Bool = true,
        labelItalic: Bool = false,
        labelColorHex: String = "#FFFFFF",
        shape: ButtonShape = .roundedRectangle,
        enabled: Bool,
        interactionMode: ButtonInteractionMode = .momentary,
        turboClicksPerSecond: Int = TurboConfiguration.defaultClicksPerSecond,
        rightClickKeyBindings: [ButtonKeyBinding]? = nil,
        rightClickFallsBackToPrimary: Bool = true,
        rightClickInteractionMode: ButtonInteractionMode? = nil,
        rightClickTurboClicksPerSecond: Int = TurboConfiguration.defaultClicksPerSecond,
        action: ButtonAction = .keyboard,
        joystick: JoystickConfig = .defaultBindings,
        systemEventIconSize: SystemEventIconSize = .large,
        dwellAction: DwellActionConfig = .default
    ) {
        self.type = type
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.editorWidth = editorWidth
        self.editorHeight = editorHeight
        self.colorHex = colorHex
        self.keyCode = keyCode
        self.keyModifiers = keyModifiers
        self.keyBindings = Self.normalizedKeyBindings(
            keyBindings ?? [ButtonKeyBinding(keyCode: keyCode, keyModifiers: keyModifiers)],
            fallbackKeyCode: keyCode,
            fallbackKeyModifiers: keyModifiers
        )
        self.multiKeyActivationMode = multiKeyActivationMode
        self.keyCode = self.keyBindings[0].keyCode
        self.keyModifiers = self.keyBindings[0].keyModifiers
        self.label = label
        self.labelFontSize = labelFontSize
        self.labelBold = labelBold
        self.labelItalic = labelItalic
        self.labelColorHex = labelColorHex
        self.shape = shape
        self.enabled = enabled
        self.interactionMode = interactionMode
        self.turboClicksPerSecond = TurboConfiguration.normalizedClicksPerSecond(turboClicksPerSecond)
        self.rightClickKeyBindings = rightClickKeyBindings?.isEmpty == true ? nil : rightClickKeyBindings
        self.rightClickFallsBackToPrimary = rightClickFallsBackToPrimary
        self.rightClickInteractionMode = rightClickInteractionMode
        self.rightClickTurboClicksPerSecond = TurboConfiguration.normalizedClicksPerSecond(rightClickTurboClicksPerSecond)
        self.action = action
        self.joystick = joystick
        self.systemEventIconSize = systemEventIconSize
        self.dwellAction = dwellAction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(ButtonType.self, forKey: .type) ?? .keyboard
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        editorWidth = try container.decodeIfPresent(Double.self, forKey: .editorWidth) ?? 0
        editorHeight = try container.decodeIfPresent(Double.self, forKey: .editorHeight) ?? 0
        colorHex = try container.decode(String.self, forKey: .colorHex)
        let decodedKeyCode = try container.decodeIfPresent(Int.self, forKey: .keyCode) ?? 49
        let decodedKeyModifiers = try container.decodeIfPresent(Int.self, forKey: .keyModifiers) ?? 0
        keyBindings = Self.normalizedKeyBindings(
            try container.decodeIfPresent([ButtonKeyBinding].self, forKey: .keyBindings),
            fallbackKeyCode: decodedKeyCode,
            fallbackKeyModifiers: decodedKeyModifiers
        )
        keyCode = keyBindings[0].keyCode
        keyModifiers = keyBindings[0].keyModifiers
        multiKeyActivationMode = try container.decodeIfPresent(MultiKeyActivationMode.self, forKey: .multiKeyActivationMode) ?? .sequential
        label = try container.decode(String.self, forKey: .label)
        labelFontSize = try container.decodeIfPresent(Double.self, forKey: .labelFontSize) ?? 11
        labelBold = try container.decodeIfPresent(Bool.self, forKey: .labelBold) ?? true
        labelItalic = try container.decodeIfPresent(Bool.self, forKey: .labelItalic) ?? false
        labelColorHex = try container.decodeIfPresent(String.self, forKey: .labelColorHex) ?? "#FFFFFF"
        shape = try container.decodeIfPresent(ButtonShape.self, forKey: .shape) ?? .roundedRectangle
        enabled = try container.decode(Bool.self, forKey: .enabled)
        interactionMode = try container.decodeIfPresent(ButtonInteractionMode.self, forKey: .interactionMode) ?? .momentary
        turboClicksPerSecond = TurboConfiguration.normalizedClicksPerSecond(
            try container.decodeIfPresent(Int.self, forKey: .turboClicksPerSecond)
                ?? TurboConfiguration.defaultClicksPerSecond
        )
        let decodedRightClickBindings = try container.decodeIfPresent([ButtonKeyBinding].self, forKey: .rightClickKeyBindings)
        rightClickKeyBindings = decodedRightClickBindings?.isEmpty == true ? nil : decodedRightClickBindings
        rightClickFallsBackToPrimary = try container.decodeIfPresent(Bool.self, forKey: .rightClickFallsBackToPrimary) ?? true
        rightClickInteractionMode = try container.decodeIfPresent(ButtonInteractionMode.self, forKey: .rightClickInteractionMode)
        rightClickTurboClicksPerSecond = TurboConfiguration.normalizedClicksPerSecond(
            try container.decodeIfPresent(Int.self, forKey: .rightClickTurboClicksPerSecond)
                ?? TurboConfiguration.defaultClicksPerSecond
        )
        action = try container.decodeIfPresent(ButtonAction.self, forKey: .action) ?? .keyboard
        if type == .systemEvent, action.systemEvent == nil {
            action = .systemEvent(.brightnessDown)
        }
        joystick = try container.decodeIfPresent(JoystickConfig.self, forKey: .joystick) ?? .defaultBindings
        systemEventIconSize = try container.decodeIfPresent(SystemEventIconSize.self, forKey: .systemEventIconSize) ?? .large
        dwellAction = try container.decodeIfPresent(DwellActionConfig.self, forKey: .dwellAction) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let normalizedBindings = Self.normalizedKeyBindings(
            keyBindings,
            fallbackKeyCode: keyCode,
            fallbackKeyModifiers: keyModifiers
        )
        let firstBinding = normalizedBindings[0]

        try container.encode(type, forKey: .type)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(editorWidth, forKey: .editorWidth)
        try container.encode(editorHeight, forKey: .editorHeight)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(firstBinding.keyCode, forKey: .keyCode)
        try container.encode(firstBinding.keyModifiers, forKey: .keyModifiers)
        try container.encode(normalizedBindings, forKey: .keyBindings)
        try container.encode(multiKeyActivationMode, forKey: .multiKeyActivationMode)
        try container.encode(label, forKey: .label)
        try container.encode(labelFontSize, forKey: .labelFontSize)
        try container.encode(labelBold, forKey: .labelBold)
        try container.encode(labelItalic, forKey: .labelItalic)
        try container.encode(labelColorHex, forKey: .labelColorHex)
        try container.encode(shape, forKey: .shape)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(interactionMode, forKey: .interactionMode)
        try container.encode(TurboConfiguration.normalizedClicksPerSecond(turboClicksPerSecond), forKey: .turboClicksPerSecond)
        try container.encodeIfPresent(rightClickKeyBindings?.isEmpty == true ? nil : rightClickKeyBindings, forKey: .rightClickKeyBindings)
        try container.encode(rightClickFallsBackToPrimary, forKey: .rightClickFallsBackToPrimary)
        try container.encodeIfPresent(rightClickInteractionMode, forKey: .rightClickInteractionMode)
        try container.encode(TurboConfiguration.normalizedClicksPerSecond(rightClickTurboClicksPerSecond), forKey: .rightClickTurboClicksPerSecond)
        try container.encode(action, forKey: .action)
        try container.encode(joystick, forKey: .joystick)
        try container.encode(systemEventIconSize, forKey: .systemEventIconSize)
        try container.encode(dwellAction, forKey: .dwellAction)
    }

    private static func normalizedKeyBindings(
        _ bindings: [ButtonKeyBinding]?,
        fallbackKeyCode: Int,
        fallbackKeyModifiers: Int
    ) -> [ButtonKeyBinding] {
        guard let bindings, !bindings.isEmpty else {
            return [ButtonKeyBinding(keyCode: fallbackKeyCode, keyModifiers: fallbackKeyModifiers)]
        }

        return bindings
    }
}

/// Optional editor grouping metadata; runtime input still reads each button's own config.
struct ButtonGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var memberButtonIDs: [String]

    init(id: UUID = UUID(), name: String, memberButtonIDs: [String]) {
        self.id = id
        self.name = name
        self.memberButtonIDs = memberButtonIDs
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - Profile

/// Persisted profile container for one visible layout plus any nested layers/sub-profiles.
struct Profile: Codable, Identifiable {
    static let defaultBackgroundColorHex = "#000000"
    static let defaultBackgroundFrostedGlassIntensity = 0
    static let defaultVirtualCursorModeArmDelaySeconds = 10
    static let defaultVirtualCursorModeTemporaryReleaseSeconds = 15
    static let defaultCompatibilityModeDurationMilliseconds = 33
    static let maximumCompatibilityModeDurationMilliseconds = 1_000

    var id: UUID
    var name: String
    var opacity: Double                              // 0.25–1.0
    var showPointerLocation: Bool
    var backgroundColorHex: String                   // "#RRGGBB"
    var backgroundFrostedGlassIntensity: Int         // 0–100
    var virtualCursorModeEnabled: Bool
    var virtualCursorModeArmDelaySeconds: Int
    var virtualCursorModeTemporaryReleaseSeconds: Int
    var compatibilityMode: Bool
    var compatibilityModeDurationMilliseconds: Int
    var editorCoordinateMode: EditorCoordinateMode
    var padWidth: Double                             // absolute pts
    var padHeight: Double
    var displayPadWidth: Double
    var displayPadHeight: Double
    var buttons: [String: ButtonConfig]              // keyed by GamepadButton.rawValue
    var buttonGroups: [ButtonGroup]
    var subProfiles: [Profile]
    var activeSubProfileID: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case opacity
        case showPointerLocation
        case backgroundColorHex
        case backgroundFrostedGlassIntensity
        // Preserve the original serialized keys so existing profiles remain compatible.
        case virtualCursorModeEnabled = "mouseCaptureEnabled"
        case virtualCursorModeArmDelaySeconds = "mouseCaptureArmDelaySeconds"
        case virtualCursorModeTemporaryReleaseSeconds = "mouseCaptureTemporaryReleaseSeconds"
        case compatibilityMode
        case compatibilityModeDurationMilliseconds
        case editorCoordinateMode
        case padWidth
        case padHeight
        case displayPadWidth
        case displayPadHeight
        case buttons
        case buttonGroups
        case subProfiles
        case activeSubProfileID
    }

    init(
        id: UUID,
        name: String,
        opacity: Double,
        showPointerLocation: Bool = false,
        backgroundColorHex: String = Profile.defaultBackgroundColorHex,
        backgroundFrostedGlassIntensity: Int = Profile.defaultBackgroundFrostedGlassIntensity,
        virtualCursorModeEnabled: Bool = false,
        virtualCursorModeArmDelaySeconds: Int = Profile.defaultVirtualCursorModeArmDelaySeconds,
        virtualCursorModeTemporaryReleaseSeconds: Int = Profile.defaultVirtualCursorModeTemporaryReleaseSeconds,
        compatibilityMode: Bool = false,
        compatibilityModeDurationMilliseconds: Int = Profile.defaultCompatibilityModeDurationMilliseconds,
        editorCoordinateMode: EditorCoordinateMode = .legacyTopLeft,
        padWidth: Double,
        padHeight: Double,
        displayPadWidth: Double? = nil,
        displayPadHeight: Double? = nil,
        buttons: [String: ButtonConfig],
        buttonGroups: [ButtonGroup] = [],
        subProfiles: [Profile] = [],
        activeSubProfileID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.opacity = opacity
        self.showPointerLocation = showPointerLocation
        self.backgroundColorHex = backgroundColorHex
        self.backgroundFrostedGlassIntensity = backgroundFrostedGlassIntensity
        self.virtualCursorModeEnabled = virtualCursorModeEnabled
        self.virtualCursorModeArmDelaySeconds = max(1, virtualCursorModeArmDelaySeconds)
        self.virtualCursorModeTemporaryReleaseSeconds = max(1, virtualCursorModeTemporaryReleaseSeconds)
        self.compatibilityMode = compatibilityMode
        self.compatibilityModeDurationMilliseconds = Self.normalizedCompatibilityModeDurationMilliseconds(
            compatibilityModeDurationMilliseconds
        )
        self.editorCoordinateMode = editorCoordinateMode
        self.padWidth = padWidth
        self.padHeight = padHeight
        self.displayPadWidth = displayPadWidth ?? padWidth
        self.displayPadHeight = displayPadHeight ?? padHeight
        self.buttons = buttons
        self.buttonGroups = Self.sanitizedButtonGroups(buttonGroups, validButtonIDs: Set(buttons.keys))
        self.subProfiles = subProfiles
        self.activeSubProfileID = activeSubProfileID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        opacity = try container.decode(Double.self, forKey: .opacity)
        showPointerLocation = try container.decodeIfPresent(Bool.self, forKey: .showPointerLocation) ?? false
        backgroundColorHex = try container.decodeIfPresent(String.self, forKey: .backgroundColorHex) ?? Self.defaultBackgroundColorHex
        let legacyContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let legacyFrostedGlassKey = DynamicCodingKey("background" + "S" + "moke" + "Intensity")
        backgroundFrostedGlassIntensity = try container.decodeIfPresent(Int.self, forKey: .backgroundFrostedGlassIntensity)
            ?? (try legacyContainer.decodeIfPresent(Int.self, forKey: legacyFrostedGlassKey) ?? Self.defaultBackgroundFrostedGlassIntensity)
        virtualCursorModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .virtualCursorModeEnabled) ?? false
        virtualCursorModeArmDelaySeconds = max(
            1,
            try container.decodeIfPresent(Int.self, forKey: .virtualCursorModeArmDelaySeconds)
                ?? Self.defaultVirtualCursorModeArmDelaySeconds
        )
        virtualCursorModeTemporaryReleaseSeconds = max(
            1,
            try container.decodeIfPresent(Int.self, forKey: .virtualCursorModeTemporaryReleaseSeconds)
                ?? Self.defaultVirtualCursorModeTemporaryReleaseSeconds
        )
        compatibilityMode = try container.decodeIfPresent(Bool.self, forKey: .compatibilityMode) ?? false
        compatibilityModeDurationMilliseconds = Self.normalizedCompatibilityModeDurationMilliseconds(
            try container.decodeIfPresent(Int.self, forKey: .compatibilityModeDurationMilliseconds)
                ?? Self.defaultCompatibilityModeDurationMilliseconds
        )
        editorCoordinateMode = try container.decodeIfPresent(EditorCoordinateMode.self, forKey: .editorCoordinateMode) ?? .legacyTopLeft
        padWidth = try container.decode(Double.self, forKey: .padWidth)
        padHeight = try container.decode(Double.self, forKey: .padHeight)
        displayPadWidth = try container.decodeIfPresent(Double.self, forKey: .displayPadWidth) ?? padWidth
        displayPadHeight = try container.decodeIfPresent(Double.self, forKey: .displayPadHeight) ?? padHeight
        buttons = try container.decode([String: ButtonConfig].self, forKey: .buttons)
        buttonGroups = Self.sanitizedButtonGroups(
            try container.decodeIfPresent([ButtonGroup].self, forKey: .buttonGroups) ?? [],
            validButtonIDs: Set(buttons.keys)
        )
        subProfiles = try container.decodeIfPresent([Profile].self, forKey: .subProfiles) ?? []
        activeSubProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeSubProfileID)
    }

    static func normalizedCompatibilityModeDurationMilliseconds(_ value: Int) -> Int {
        min(max(1, value), maximumCompatibilityModeDurationMilliseconds)
    }

    var orderedButtonIDs: [GamepadButton] {
        buttons.keys
            .map { GamepadButton($0) }
            .sorted { lhs, rhs in
                let lhsLegacyIndex = Self.legacyButtonOrder[lhs.rawValue]
                let rhsLegacyIndex = Self.legacyButtonOrder[rhs.rawValue]

                switch (lhsLegacyIndex, rhsLegacyIndex) {
                case let (lhsIndex?, rhsIndex?):
                    return lhsIndex < rhsIndex
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    let lhsLabel = buttons[lhs.rawValue]?.resolvedSortLabel ?? lhs.rawValue
                    let rhsLabel = buttons[rhs.rawValue]?.resolvedSortLabel ?? rhs.rawValue
                    let labelOrder = lhsLabel.localizedStandardCompare(rhsLabel)
                    if labelOrder != .orderedSame {
                        return labelOrder == .orderedAscending
                    }

                    return lhs.rawValue < rhs.rawValue
                }
            }
    }

    func normalizedForSaving() -> Profile {
        var normalizedProfile = self
        var normalizedButtons: [String: ButtonConfig] = [:]
        var remappedButtonIDs: [String: String] = [:]

        for button in orderedButtonIDs {
            guard let config = buttons[button.rawValue] else {
                continue
            }

            let key = (button.isGenerated || button.isSubProfileSwitch) ? button.rawValue : GamepadButton.generated().rawValue
            normalizedButtons[key] = config
            remappedButtonIDs[button.rawValue] = key
        }

        normalizedProfile.buttons = normalizedButtons
        normalizedProfile.buttonGroups = Self.sanitizedButtonGroups(
            buttonGroups.map { group in
                ButtonGroup(
                    id: group.id,
                    name: group.name,
                    memberButtonIDs: group.memberButtonIDs.compactMap { remappedButtonIDs[$0] }
                )
            },
            validButtonIDs: Set(normalizedButtons.keys)
        )
        normalizedProfile.subProfiles = subProfiles.map { $0.normalizedForSaving() }
        return normalizedProfile
    }

    func withSanitizedButtonGroups() -> Profile {
        var sanitizedProfile = self
        sanitizedProfile.buttonGroups = Self.sanitizedButtonGroups(buttonGroups, validButtonIDs: Set(buttons.keys))
        sanitizedProfile.subProfiles = subProfiles.map { $0.withSanitizedButtonGroups() }
        return sanitizedProfile
    }

    func asTopLevelContainer(baseLayerName: String = "Base") -> Profile {
        if !subProfiles.isEmpty {
            return normalizedActiveSubProfileSelection()
        }

        var baseLayer = self
        baseLayer.id = UUID()
        baseLayer.name = baseLayerName
        baseLayer.subProfiles = []
        baseLayer.activeSubProfileID = nil

        var container = self
        container.buttons = [:]
        container.buttonGroups = []
        container.subProfiles = [baseLayer]
        container.activeSubProfileID = baseLayer.id
        return container
    }

    func normalizedActiveSubProfileSelection() -> Profile {
        var normalizedProfile = self
        if normalizedProfile.subProfiles.isEmpty {
            normalizedProfile.activeSubProfileID = nil
            return normalizedProfile
        }

        if let activeSubProfileID,
           normalizedProfile.subProfiles.contains(where: { $0.id == activeSubProfileID }) {
            normalizedProfile.activeSubProfileID = activeSubProfileID
        } else {
            normalizedProfile.activeSubProfileID = normalizedProfile.subProfiles[0].id
        }

        return normalizedProfile
    }

    func copyWithNewIDs(nameSuffix: String = " Copy") -> Profile {
        var copiedProfile = self
        copiedProfile.id = UUID()
        copiedProfile.name += nameSuffix
        let copiedSubProfiles = subProfiles.map { $0.copyWithNewIDs(nameSuffix: "") }
        let copiedSubProfileIDsBySourceID = Dictionary(
            uniqueKeysWithValues: zip(subProfiles.map(\.id), copiedSubProfiles.map(\.id))
        )
        copiedProfile.subProfiles = copiedSubProfiles.map { subProfile in
            subProfile.remappingSubProfileSwitches(using: copiedSubProfileIDsBySourceID)
        }

        if let activeSubProfileID,
           let sourceIndex = subProfiles.firstIndex(where: { $0.id == activeSubProfileID }),
           copiedProfile.subProfiles.indices.contains(sourceIndex) {
            copiedProfile.activeSubProfileID = copiedProfile.subProfiles[sourceIndex].id
        } else {
            copiedProfile.activeSubProfileID = copiedProfile.subProfiles.first?.id
        }

        return copiedProfile
    }

    func copyWithFreshButtonIDs(nameSuffix: String = "") -> Profile {
        var copiedProfile = self
        copiedProfile.id = UUID()
        copiedProfile.name += nameSuffix

        var remappedButtons: [String: ButtonConfig] = [:]
        var copiedIDsBySourceID: [String: String] = [:]

        for button in orderedButtonIDs {
            guard let config = buttons[button.rawValue] else {
                continue
            }

            let copiedButton = GamepadButton.generated()
            remappedButtons[copiedButton.rawValue] = config
            copiedIDsBySourceID[button.rawValue] = copiedButton.rawValue
        }

        copiedProfile.buttons = remappedButtons
        copiedProfile.buttonGroups = Self.sanitizedButtonGroups(
            buttonGroups.map { group in
                ButtonGroup(
                    id: UUID(),
                    name: group.name,
                    memberButtonIDs: group.memberButtonIDs.compactMap { copiedIDsBySourceID[$0] }
                )
            },
            validButtonIDs: Set(remappedButtons.keys)
        )
        copiedProfile.subProfiles = []
        copiedProfile.activeSubProfileID = nil
        return copiedProfile
    }

    private func remappingSubProfileSwitches(using copiedIDsBySourceID: [UUID: UUID]) -> Profile {
        guard !copiedIDsBySourceID.isEmpty else {
            return self
        }

        var remappedProfile = self
        var remappedButtons: [String: ButtonConfig] = [:]

        for (key, var config) in buttons {
            let button = GamepadButton(key)
            if let sourceTargetID = button.subProfileSwitchTargetID,
               let copiedTargetID = copiedIDsBySourceID[sourceTargetID] {
                config.action = .subProfileSwitch(copiedTargetID)
                remappedButtons[GamepadButton.subProfileSwitch(targetID: copiedTargetID).rawValue] = config
                continue
            }

            if let sourceTargetID = config.action.targetSubProfileID,
               let copiedTargetID = copiedIDsBySourceID[sourceTargetID] {
                config.action = .subProfileSwitch(copiedTargetID)
            }

            remappedButtons[key] = config
        }

        remappedProfile.buttons = remappedButtons
        return remappedProfile
    }

    private static func sanitizedButtonGroups(_ groups: [ButtonGroup], validButtonIDs: Set<String>) -> [ButtonGroup] {
        groups.compactMap { group in
            var seen = Set<String>()
            let members = group.memberButtonIDs.filter { buttonID in
                guard validButtonIDs.contains(buttonID), !seen.contains(buttonID) else {
                    return false
                }

                seen.insert(buttonID)
                return true
            }

            guard members.count >= 2 else {
                return nil
            }

            let trimmedName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return ButtonGroup(
                id: group.id,
                name: trimmedName.isEmpty ? "Group" : trimmedName,
                memberButtonIDs: members
            )
        }
    }

    static func makeBlank(name: String = "Blank Profile") -> Profile {
        Profile(
            id: UUID(),
            name: name,
            opacity: 0.90,
            backgroundColorHex: Self.defaultBackgroundColorHex,
            backgroundFrostedGlassIntensity: Self.defaultBackgroundFrostedGlassIntensity,
            compatibilityMode: false,
            editorCoordinateMode: .centered,
            padWidth: 420,
            padHeight: 300,
            displayPadWidth: 420,
            displayPadHeight: 300,
            buttons: [:]
        )
    }

    static func makeDefault(name: String = "Default") -> Profile {
        makeStarterTemplate(name: name)
    }

    // Starter template for fresh installs and built-in profile creation.
    static func makeStarterTemplate(name: String = "Default") -> Profile {
        var profile = Profile(
            id: UUID(),
            name: name,
            opacity: 0.90,
            backgroundColorHex: Self.defaultBackgroundColorHex,
            backgroundFrostedGlassIntensity: Self.defaultBackgroundFrostedGlassIntensity,
            compatibilityMode: false,
            editorCoordinateMode: .centered,
            padWidth: 420,
            padHeight: 300,
            displayPadWidth: 462,
            displayPadHeight: 255,
            buttons: [:],
            subProfiles: [
                makeDefaultGamepadLayer(),
                makeDefaultKeyboardLayer(),
            ]
        )
        profile.activeSubProfileID = profile.subProfiles.first { $0.name == "Keyboard" }?.id
        return profile
    }

    static func makeDefaultLayerTemplates() -> [Profile] {
        [
            makeDefaultGamepadLayer(),
            makeDefaultKeyboardLayer(),
        ]
    }

    private static func makeDefaultGamepadLayer() -> Profile {
        let W = 480.4
        let H = 274.0

        func cx(_ abs: Double) -> Double { abs / W }
        func cy(_ abs: Double) -> Double { abs / H }
        func bw(_ abs: Double) -> Double { abs / W }
        func bh(_ abs: Double) -> Double { abs / H }

        var btns: [String: ButtonConfig] = [:]

        func add(
            key: Int,
            x: Double,
            y: Double,
            w: Double = 40,
            h: Double = 40,
            hex: String = "#3D3D3D",
            shape: ButtonShape = .square,
            label: String = ""
        ) {
            btns[GamepadButton.generated().rawValue] = ButtonConfig(
                x: cx(x), y: cy(y),
                width: bw(w), height: bh(h),
                editorWidth: w,
                editorHeight: h,
                colorHex: hex,
                keyCode: key,
                keyModifiers: 0,
                label: label,
                labelFontSize: 11,
                shape: shape,
                enabled: true
            )
        }

        func addJoystick(x: Double, y: Double, up: Int, down: Int, left: Int, right: Int) {
            var joystick = JoystickConfig.defaultBindings
            joystick.operationMode = .clickDrag
            joystick.axisLockMode = .holdDirection
            joystick.up = ButtonKeyBinding(keyCode: up, keyModifiers: 0)
            joystick.down = ButtonKeyBinding(keyCode: down, keyModifiers: 0)
            joystick.left = ButtonKeyBinding(keyCode: left, keyModifiers: 0)
            joystick.right = ButtonKeyBinding(keyCode: right, keyModifiers: 0)
            btns[GamepadButton.generated().rawValue] = ButtonConfig(
                type: .joystick,
                x: cx(x), y: cy(y),
                width: bw(40), height: bh(40),
                editorWidth: 40,
                editorHeight: 40,
                colorHex: "#000000",
                keyCode: 13,
                label: "Joystick",
                labelFontSize: 11,
                shape: .oval,
                enabled: true,
                rightClickFallsBackToPrimary: false,
                joystick: joystick
            )
        }

        add(key: 6, x: 20, y: 20)
        add(key: 9, x: 148, y: 20)
        add(key: 8, x: 105.3, y: 20)
        add(key: 7, x: 62.7, y: 20)
        add(key: 125, x: 375.2, y: 20)
        add(key: 126, x: 332.4, y: 20)
        add(key: 123, x: 417.7, y: 20)
        add(key: 124, x: 460.4, y: 20)
        addJoystick(x: 84, y: 93, up: 13, down: 1, left: 0, right: 2)
        addJoystick(x: 398, y: 93, up: 34, down: 38, left: 40, right: 37)
        add(key: 0, x: 40, y: 144)
        add(key: 1, x: 84, y: 142)
        add(key: 2, x: 128, y: 142)
        add(key: 38, x: 354, y: 144)
        add(key: 40, x: 398, y: 144)
        add(key: 37, x: 442, y: 144)
        add(key: 27, x: 218.7, y: 105, w: 40, h: 20, shape: .roundedRectangle)
        add(key: 24, x: 260.7, y: 105, w: 40, h: 20, shape: .roundedRectangle)
        add(key: 36, x: 240.7, y: 135, w: 40, h: 20, shape: .roundedRectangle)
        add(key: 53, x: 219.7, y: 169, w: 40, h: 20, shape: .roundedRectangle)
        add(key: 49, x: 261.7, y: 169, w: 40, h: 20, shape: .roundedRectangle)
        add(key: 13, x: 84, y: 186)
        add(key: 34, x: 398, y: 188)
        add(key: 12, x: 48.4, y: 256, w: 65.4, h: 24, shape: .roundedRectangle)
        add(key: 14, x: 117, y: 256, w: 65.4, h: 24, shape: .roundedRectangle)
        add(key: 32, x: 365.2, y: 256, w: 62.4, h: 24, shape: .roundedRectangle)
        add(key: 31, x: 430.8, y: 256, w: 62.4, h: 24, shape: .roundedRectangle)

        return Profile(
            id: UUID(),
            name: "Gamepad",
            opacity: 0.90,
            backgroundColorHex: Self.defaultBackgroundColorHex,
            backgroundFrostedGlassIntensity: Self.defaultBackgroundFrostedGlassIntensity,
            compatibilityMode: false,
            editorCoordinateMode: .centered,
            padWidth: W,
            padHeight: H,
            displayPadWidth: 462,
            displayPadHeight: 255,
            buttons: btns
        )
    }

    private static func makeDefaultKeyboardLayer() -> Profile {
        let W = 600.0
        let H = 331.0
        let keyColor = "#212121"

        func cx(_ abs: Double) -> Double { abs / W }
        func cy(_ abs: Double) -> Double { abs / H }
        func bw(_ abs: Double) -> Double { abs / W }
        func bh(_ abs: Double) -> Double { abs / H }

        var btns: [String: ButtonConfig] = [:]

        func add(key: Int, x: Double, y: Double, w: Double = 40, h: Double = 40) {
            btns[GamepadButton.generated().rawValue] = ButtonConfig(
                x: cx(x), y: cy(y),
                width: bw(w), height: bh(h),
                editorWidth: w,
                editorHeight: h,
                colorHex: keyColor,
                keyCode: key,
                label: "",
                labelFontSize: 11,
                shape: .square,
                enabled: true
            )
        }

        func addSystemEvent(
            _ systemEvent: SystemEvent,
            x: Double,
            y: Double,
            iconSize: SystemEventIconSize = .large
        ) {
            btns[GamepadButton.generated().rawValue] = ButtonConfig(
                type: .systemEvent,
                x: cx(x), y: cy(y),
                width: bw(40), height: bh(40),
                editorWidth: 40,
                editorHeight: 40,
                colorHex: keyColor,
                keyCode: 49,
                label: "",
                labelFontSize: 11,
                shape: .square,
                enabled: true,
                rightClickFallsBackToPrimary: false,
                action: .systemEvent(systemEvent),
                systemEventIconSize: iconSize
            )
        }

        add(key: 125, x: 539, y: 10, h: 20)
        add(key: 63, x: 20, y: 20)
        add(key: 59, x: 62, y: 20)
        add(key: 58, x: 104, y: 20)
        add(key: 55, x: 150, y: 20, w: 50)
        add(key: 49, x: 281.2, y: 20, w: 209)
        add(key: 55, x: 411, y: 20, w: 50)
        add(key: 61, x: 457, y: 20)
        add(key: 123, x: 498, y: 20)
        add(key: 124, x: 580, y: 20)
        add(key: 126, x: 539, y: 30, h: 20)
        add(key: 56, x: 44, y: 61, w: 87)
        add(key: 6, x: 108, y: 61)
        add(key: 7, x: 149, y: 61)
        add(key: 8, x: 190, y: 61)
        add(key: 9, x: 231, y: 61)
        add(key: 11, x: 272, y: 61)
        add(key: 45, x: 313, y: 61)
        add(key: 46, x: 354, y: 61)
        add(key: 43, x: 395, y: 61)
        add(key: 47, x: 436, y: 61)
        add(key: 44, x: 477, y: 61)
        add(key: 60, x: 549.5, y: 61, w: 101)
        add(key: 57, x: 34, y: 102, w: 68)
        add(key: 0, x: 89, y: 102)
        add(key: 1, x: 130, y: 102)
        add(key: 2, x: 171, y: 102)
        add(key: 3, x: 212, y: 102)
        add(key: 5, x: 253, y: 102)
        add(key: 4, x: 294, y: 102)
        add(key: 38, x: 335, y: 102)
        add(key: 40, x: 376, y: 102)
        add(key: 37, x: 417, y: 102)
        add(key: 41, x: 458, y: 102)
        add(key: 39, x: 499, y: 102)
        add(key: 36, x: 560, y: 102, w: 80)
        add(key: 48, x: 31.2, y: 143, w: 62)
        add(key: 12, x: 82.5, y: 143)
        add(key: 13, x: 123.5, y: 143)
        add(key: 14, x: 164.5, y: 143)
        add(key: 15, x: 205.5, y: 143)
        add(key: 17, x: 246.5, y: 143)
        add(key: 16, x: 287.5, y: 143)
        add(key: 32, x: 328.5, y: 143)
        add(key: 34, x: 369.5, y: 143)
        add(key: 31, x: 410.5, y: 143)
        add(key: 35, x: 451.5, y: 143)
        add(key: 33, x: 492.5, y: 143)
        add(key: 30, x: 533.5, y: 143)
        add(key: 42, x: 577, y: 143, w: 45)
        add(key: 50, x: 20, y: 184)
        add(key: 18, x: 61, y: 184)
        add(key: 19, x: 102, y: 184)
        add(key: 20, x: 143, y: 184)
        add(key: 21, x: 184, y: 184)
        add(key: 23, x: 225, y: 184)
        add(key: 22, x: 266, y: 184)
        add(key: 26, x: 307, y: 184)
        add(key: 28, x: 348, y: 184)
        add(key: 25, x: 389, y: 184)
        add(key: 29, x: 430, y: 184)
        add(key: 27, x: 471, y: 184)
        add(key: 24, x: 512, y: 184)
        add(key: 51, x: 566.5, y: 184, w: 67)
        add(key: 53, x: 20, y: 224)
        add(key: 122, x: 61, y: 224)
        add(key: 120, x: 102, y: 224)
        add(key: 99, x: 143, y: 224)
        add(key: 118, x: 184, y: 224)
        add(key: 96, x: 225, y: 224)
        add(key: 97, x: 266, y: 224)
        add(key: 98, x: 307, y: 224)
        add(key: 100, x: 348, y: 224)
        add(key: 101, x: 389, y: 224)
        add(key: 109, x: 430, y: 224)
        add(key: 103, x: 471, y: 224)
        add(key: 111, x: 512, y: 224)
        addSystemEvent(.brightnessDown, x: 62, y: 270)
        addSystemEvent(.brightnessUp, x: 111.8889, y: 270)
        addSystemEvent(.missionControl, x: 161.7778, y: 270)
        addSystemEvent(.launchpad, x: 211.6667, y: 270, iconSize: .small)
        addSystemEvent(.previousTrack, x: 261.5556, y: 270)
        addSystemEvent(.playPause, x: 311.4444, y: 270)
        addSystemEvent(.nextTrack, x: 361.3333, y: 270)
        addSystemEvent(.mute, x: 411.2222, y: 270)
        addSystemEvent(.volumeDown, x: 461.1111, y: 270)
        addSystemEvent(.volumeUp, x: 511, y: 270)

        return Profile(
            id: UUID(),
            name: "Keyboard",
            opacity: 0.90,
            backgroundColorHex: Self.defaultBackgroundColorHex,
            backgroundFrostedGlassIntensity: Self.defaultBackgroundFrostedGlassIntensity,
            compatibilityMode: false,
            editorCoordinateMode: .centered,
            padWidth: W,
            padHeight: H,
            displayPadWidth: 600,
            displayPadHeight: 325,
            buttons: btns
        )
    }

    private static let legacyButtonOrder: [String: Int] = Dictionary(
        uniqueKeysWithValues: GamepadButton.legacyButtons.enumerated().map { index, button in
            (button.rawValue, index)
        }
    )
}

// MARK: - Hex color helpers

import AppKit

extension NSColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8)  & 0xFF) / 255
        let b = CGFloat(rgb         & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#888888" }
        return String(
            format: "#%02X%02X%02X",
            Int(c.redComponent * 255),
            Int(c.greenComponent * 255),
            Int(c.blueComponent * 255)
        )
    }
}

extension ButtonConfig {
    static func systemEventSymbolColor(for backgroundColorHex: String) -> NSColor {
        let backgroundColor = NSColor(hex: backgroundColorHex)
        guard let color = backgroundColor.usingColorSpace(.sRGB) else {
            return .white
        }

        let luminance = (0.2126 * color.redComponent) + (0.7152 * color.greenComponent) + (0.0722 * color.blueComponent)
        return luminance >= 0.82 ? .black : .white
    }

    var resolvedSortLabel: String {
        let displayLabel = resolvedDisplayLabel
        return displayLabel.isEmpty ? keyBindingsDisplayName : displayLabel
    }

    var resolvedLabelFont: NSFont {
        var symbolicTraits: NSFontDescriptor.SymbolicTraits = []
        if labelBold { symbolicTraits.insert(.bold) }
        if labelItalic { symbolicTraits.insert(.italic) }

        let clampedSize = CGFloat(min(max(labelFontSize, 6), 36))
        let descriptor = NSFont.systemFont(ofSize: clampedSize).fontDescriptor.withSymbolicTraits(symbolicTraits)
        return NSFont(descriptor: descriptor, size: clampedSize) ?? NSFont.systemFont(
            ofSize: clampedSize,
            weight: labelBold ? .bold : .regular
        )
    }

    var resolvedLabelAttributes: [NSAttributedString.Key: Any] {
        [
            .font: resolvedLabelFont,
            .foregroundColor: NSColor(hex: labelColorHex),
        ]
    }

    var resolvedDisplayLabel: String {
        guard label.isEmpty else {
            return label
        }

        if let systemEvent = action.systemEvent {
            return systemEvent.fallbackSymbol
        }

        if type == .dwellAction {
            return dwellAction.kind.fallbackLabel
        }

        return keyBindingsDisplayName
    }

    var keyBindingsDisplayName: String {
        guard keyBindings.count > 1 else {
            let binding = keyBindings.first ?? ButtonKeyBinding(keyCode: keyCode, keyModifiers: keyModifiers)
            return Self.keyDisplayName(
                code: binding.keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
            )
        }

        return "[" + keyBindings.map { binding in
            Self.keyDisplayName(
                code: binding.keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
            )
        }.joined() + "]"
    }

    static func keyDisplayName(code: Int, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        parts.append(keyName(code))
        return parts.joined()
    }

    static func isModifierKey(code: Int) -> Bool {
        modifierFlag(forKeyCode: code) != nil
    }

    static func modifierFlag(forKeyCode code: Int) -> NSEvent.ModifierFlags? {
        switch code {
        case 54, 55:
            return .command
        case 56, 60:
            return .shift
        case 57:
            return .capsLock
        case 58, 61:
            return .option
        case 59, 62:
            return .control
        case 63:
            return .function
        default:
            return nil
        }
    }

    static func keyName(_ code: Int) -> String {
        let keyNames: [Int: String] = [
            0: "A",
            1: "S",
            2: "D",
            3: "F",
            4: "H",
            5: "G",
            6: "Z",
            7: "X",
            8: "C",
            9: "V",
            11: "B",
            12: "Q",
            13: "W",
            14: "E",
            15: "R",
            16: "Y",
            17: "T",
            18: "1",
            19: "2",
            20: "3",
            21: "4",
            22: "6",
            23: "5",
            24: "=",
            25: "9",
            26: "7",
            27: "-",
            28: "8",
            29: "0",
            30: "]",
            31: "O",
            32: "U",
            33: "[",
            34: "I",
            35: "P",
            36: "􀅇",
            37: "L",
            38: "J",
            39: "'",
            40: "K",
            41: ";",
            42: "\\",
            43: ",",
            44: "/",
            45: "N",
            46: "M",
            47: ".",
            48: "􀅆",
            49: "􁁺",
            50: "`",
            51: "􀆛",
            53: "esc",
            54: "⌘",
            55: "⌘",
            56: "􀆝",
            57: "􀆡",
            58: "􀆕",
            59: "􀆍",
            60: "􀆝",
            61: "􀆕",
            62: "􀆍",
            63: "Fn",
            64: "F17",
            65: "Num .",
            67: "Num *",
            69: "Num +",
            71: "Num Clear",
            75: "Num /",
            76: "Enter",
            78: "Num -",
            79: "F18",
            80: "F19",
            81: "Num =",
            82: "Num 0",
            83: "Num 1",
            84: "Num 2",
            85: "Num 3",
            86: "Num 4",
            87: "Num 5",
            88: "Num 6",
            89: "Num 7",
            90: "F20",
            91: "Num 8",
            92: "Num 9",
            96: "F5",
            97: "F6",
            98: "F7",
            99: "F3",
            100: "F8",
            101: "F9",
            103: "F11",
            105: "F13",
            106: "F16",
            107: "F14",
            109: "F10",
            111: "F12",
            113: "F15",
            114: "Help",
            115: "Home",
            116: "􀄿",
            117: "􀆗",
            118: "F4",
            119: "End",
            120: "F2",
            121: "􀅀",
            122: "F1",
            123: "􀄦",
            124: "􀄧",
            125: "􀄥",
            126: "􀄤",
        ]

        return keyNames[code] ?? "key(\(code))"
    }
}

extension SystemEventIconSize {
    static var allCases: [SystemEventIconSize] {
        [.extraSmall, .small, .medium, .large, .extraLarge]
    }

    var displayName: String {
        switch self {
        case .extraSmall:
            return "Extra Small"
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        case .large:
            return "Large"
        case .extraLarge:
            return "Extra Large"
        }
    }

    var symbolScale: CGFloat {
        switch self {
        case .extraSmall:
            return 0.36
        case .small:
            return 0.44
        case .medium:
            return 0.50
        case .large:
            return 0.58
        case .extraLarge:
            return 0.70
        }
    }

    var tag: Int {
        SystemEventIconSize.allCases.firstIndex(of: self) ?? 3
    }

    init?(tag: Int) {
        guard SystemEventIconSize.allCases.indices.contains(tag) else {
            return nil
        }

        self = SystemEventIconSize.allCases[tag]
    }
}

extension SystemEvent {
    static var allCases: [SystemEvent] {
        [
            .brightnessDown,
            .brightnessUp,
            .volumeDown,
            .volumeUp,
            .mute,
            .playPause,
            .nextTrack,
            .previousTrack,
            .launchpad,
            .missionControl,
        ]
    }

    var displayName: String {
        switch self {
        case .brightnessDown:
            return "Brightness Down"
        case .brightnessUp:
            return "Brightness Up"
        case .volumeDown:
            return "Volume Down"
        case .volumeUp:
            return "Volume Up"
        case .mute:
            return "Mute"
        case .playPause:
            return "Play/Pause"
        case .nextTrack:
            return "Next"
        case .previousTrack:
            return "Previous"
        case .launchpad:
            return Self.prefersAppsDisplayName ? "Apps" : "Launchpad"
        case .missionControl:
            return "Mission Control"
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .brightnessDown:
            return "􀆫"
        case .brightnessUp:
            return "􀆭"
        case .volumeDown:
            return "􀊥"
        case .volumeUp:
            return "􀊧"
        case .mute:
            return "􀊣"
        case .playPause:
            return "􀊈"
        case .nextTrack:
            return "􀊐"
        case .previousTrack:
            return "􀊎"
        case .launchpad:
            return "􀚇"
        case .missionControl:
            return "􀐅"
        }
    }

    var symbolName: String {
        switch self {
        case .brightnessDown:
            return "sun.min.fill"
        case .brightnessUp:
            return "sun.max.fill"
        case .volumeDown:
            return "speaker.wave.1.fill"
        case .volumeUp:
            return "speaker.wave.3.fill"
        case .mute:
            return "speaker.slash.fill"
        case .playPause:
            return "playpause.fill"
        case .nextTrack:
            return "forward.end.fill"
        case .previousTrack:
            return "backward.end.fill"
        case .launchpad:
            return "square.grid.3x3.fill"
        case .missionControl:
            return "rectangle.3.group.fill"
        }
    }

    var tag: Int {
        SystemEvent.allCases.firstIndex(of: self) ?? 0
    }

    init?(tag: Int) {
        guard SystemEvent.allCases.indices.contains(tag) else {
            return nil
        }

        self = SystemEvent.allCases[tag]
    }

    private static var prefersAppsDisplayName: Bool {
        FileManager.default.fileExists(atPath: "/System/Applications/Apps.app")
    }
}
