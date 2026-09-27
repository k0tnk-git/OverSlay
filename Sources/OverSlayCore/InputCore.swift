import Foundation

public struct KeyBinding: Codable, Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64 = 0) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum CombinationMode: String, Codable, Sendable {
    case simultaneous
    case sequential
}

public struct KeyAction: Codable, Hashable, Sendable {
    public let bindings: [KeyBinding]
    public let combinationMode: CombinationMode

    public init(bindings: [KeyBinding], combinationMode: CombinationMode = .simultaneous) {
        self.bindings = bindings
        self.combinationMode = combinationMode
    }

    public init(_ binding: KeyBinding, combinationMode: CombinationMode = .simultaneous) {
        self.init(bindings: [binding], combinationMode: combinationMode)
    }

    private enum CodingKeys: String, CodingKey {
        case bindings
        case combinationMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bindings = try container.decode([KeyBinding].self, forKey: .bindings)
        combinationMode = try container.decodeIfPresent(CombinationMode.self, forKey: .combinationMode) ?? .simultaneous
    }
}

public enum TriggerMode: String, Codable, Sendable {
    case hold
    case toggle
    case timedToggle

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "tap", "hold":
            self = .hold
        case "toggle":
            self = .toggle
        case "timedToggle":
            self = .timedToggle
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown trigger mode: \(rawValue)"
            )
        }
    }
}

public struct WidgetGeometry: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct WidgetConfig: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var geometry: WidgetGeometry
    public var label: String
    public var action: KeyAction
    public var macro: MacroDefinition?
    public var mode: TriggerMode
    public var opacity: Double
    public var timedDurationSeconds: Double
    public var appearance: ButtonAppearance

    private enum CodingKeys: String, CodingKey {
        case id, geometry, label, action, macro, mode, opacity, timedDurationSeconds, appearance
    }

    public init(
        id: UUID = UUID(), geometry: WidgetGeometry, label: String,
        action: KeyAction, mode: TriggerMode = .hold, opacity: Double = 0.72,
        timedDurationSeconds: Double = 5, macro: MacroDefinition? = nil, appearance: ButtonAppearance = .default
    ) {
        self.id = id
        self.geometry = geometry
        self.label = label
        self.action = action
        self.macro = macro
        self.mode = mode
        self.opacity = min(max(opacity, 0.1), 1.0)
        self.timedDurationSeconds = min(max(timedDurationSeconds.isFinite ? timedDurationSeconds : 5, 0.1), 3600)
        self.appearance = appearance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            geometry: try container.decode(WidgetGeometry.self, forKey: .geometry),
            label: try container.decode(String.self, forKey: .label),
            action: try container.decodeIfPresent(KeyAction.self, forKey: .action) ?? KeyAction(bindings: []),
            // Profiles without an explicit mode use the ordinary hold semantics.
            mode: try container.decodeIfPresent(TriggerMode.self, forKey: .mode) ?? .hold,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.72,
            timedDurationSeconds: try container.decodeIfPresent(Double.self, forKey: .timedDurationSeconds) ?? 5,
            macro: try container.decodeIfPresent(MacroDefinition.self, forKey: .macro),
            appearance: try container.decodeIfPresent(ButtonAppearance.self, forKey: .appearance) ?? .default
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(geometry, forKey: .geometry)
        try c.encode(label, forKey: .label)
        if let macro {
            guard action.bindings.isEmpty else { throw MacroError.invalidPlan }
            try c.encode(macro, forKey: .macro)
        } else { try c.encode(action, forKey: .action) }
        try c.encode(mode, forKey: .mode)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(timedDurationSeconds, forKey: .timedDurationSeconds)
        try c.encode(appearance, forKey: .appearance)
    }
}

public enum ButtonPattern: String, Codable, Sendable { case solid, gradient, stripes, checkered }

public struct ButtonAppearance: Codable, Equatable, Sendable {
    public var pattern: ButtonPattern
    public var firstColor: String
    public var secondColor: String
    public static let `default` = ButtonAppearance(pattern: .solid, firstColor: "#555555", secondColor: "#718096")
    public init(pattern: ButtonPattern = .solid, firstColor: String = "#555555", secondColor: String = "#718096") {
        self.pattern = pattern; self.firstColor = firstColor; self.secondColor = secondColor
    }
    public func validated() throws -> ButtonAppearance {
        guard Self.validHex(firstColor), Self.validHex(secondColor) else { throw ButtonAppearanceError.invalidColor }
        return self
    }
    private static func validHex(_ value: String) -> Bool {
        guard value.count == 7, value.first == "#" else { return false }
        return value.dropFirst().utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }
}

public enum ButtonAppearanceError: Error { case invalidColor }

public struct RadialWidgetConfig: Codable, Equatable, Sendable {
    public var geometry: WidgetGeometry
    public var opacity: Double
    public var rightMouseAction: SideInputAction
    public var scrollUpAction: ScrollInputAction
    public var scrollDownAction: ScrollInputAction

    private enum CodingKeys: String, CodingKey { case geometry, opacity, rightMouseAction, scrollUpAction, scrollDownAction }

    public init(geometry: WidgetGeometry = .init(x: 18, y: 22, width: 190, height: 190), opacity: Double = 0.72, rightMouseAction: SideInputAction = .passthrough, scrollUpAction: ScrollInputAction = .passthrough, scrollDownAction: ScrollInputAction = .passthrough) {
        self.geometry = geometry
        self.opacity = min(max(opacity.isFinite ? opacity : 0.72, 0.1), 1)
        self.rightMouseAction = rightMouseAction
        self.scrollUpAction = scrollUpAction
        self.scrollDownAction = scrollDownAction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            geometry: try container.decodeIfPresent(WidgetGeometry.self, forKey: .geometry) ?? .init(x: 18, y: 22, width: 190, height: 190),
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.72,
            rightMouseAction: try container.decodeIfPresent(SideInputAction.self, forKey: .rightMouseAction) ?? .sprint,
            scrollUpAction: try container.decodeIfPresent(ScrollInputAction.self, forKey: .scrollUpAction) ?? .passthrough,
            scrollDownAction: try container.decodeIfPresent(ScrollInputAction.self, forKey: .scrollDownAction) ?? .passthrough
        )
    }
}

public enum SideInputAction: Codable, Equatable, Sendable {
    case passthrough, sprint, custom(KeyBinding), none
    private enum Keys: String, CodingKey { case kind, binding }
    private enum Kind: String, Codable { case passthrough, sprint, custom, none }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .passthrough: self = .passthrough
        case .sprint: self = .sprint
        case .none: self = .none
        case .custom: self = .custom(try c.decode(KeyBinding.self, forKey: .binding))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .passthrough: try c.encode(Kind.passthrough, forKey: .kind)
        case .sprint: try c.encode(Kind.sprint, forKey: .kind)
        case .none: try c.encode(Kind.none, forKey: .kind)
        case .custom(let binding): try c.encode(Kind.custom, forKey: .kind); try c.encode(binding, forKey: .binding)
        }
    }
}

public enum ScrollInputAction: Codable, Equatable, Sendable {
    case passthrough, custom(KeyBinding), none
    private enum Keys: String, CodingKey { case kind, binding }
    private enum Kind: String, Codable { case passthrough, custom, none }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .passthrough: self = .passthrough
        case .none: self = .none
        case .custom: self = .custom(try c.decode(KeyBinding.self, forKey: .binding))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .passthrough: try c.encode(Kind.passthrough, forKey: .kind)
        case .none: try c.encode(Kind.none, forKey: .kind)
        case .custom(let binding): try c.encode(Kind.custom, forKey: .kind); try c.encode(binding, forKey: .binding)
        }
    }
}

public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public static let currentSchemaVersion = 5

    public let id: UUID
    public var schemaVersion: Int
    public var bundleIdentifier: String?
    public var name: String
    public var widgets: [WidgetConfig]
    public var radial: RadialWidgetConfig

    private enum CodingKeys: String, CodingKey { case id, schemaVersion, bundleIdentifier, name, widgets, radial }

    public init(
        id: UUID = UUID(), schemaVersion: Int = Profile.currentSchemaVersion,
        bundleIdentifier: String? = nil, name: String = L10n.text("Новый профиль"), widgets: [WidgetConfig], radial: RadialWidgetConfig = .init()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.widgets = widgets
        self.radial = radial
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            bundleIdentifier: try container.decodeIfPresent(String.self, forKey: .bundleIdentifier),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? L10n.text("Новый профиль"),
            widgets: try container.decode([WidgetConfig].self, forKey: .widgets),
            radial: try container.decodeIfPresent(RadialWidgetConfig.self, forKey: .radial) ?? .init(rightMouseAction: .sprint)
        )
    }

    public func validated() throws -> Profile {
        guard schemaVersion == Self.currentSchemaVersion else { throw ProfileError.unsupportedSchema(schemaVersion) }
        guard !widgets.isEmpty else { throw ProfileError.emptyWidgets }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else { throw ProfileError.invalidName }
        if let bundleIdentifier,
           bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bundleIdentifier.count > 255 {
            throw ProfileError.invalidBundleIdentifier
        }
        var ids: Set<UUID> = []
        for widget in widgets {
            guard ids.insert(widget.id).inserted else { throw ProfileError.duplicateWidget(widget.id) }
            let g = widget.geometry
            guard g.x.isFinite, g.y.isFinite, g.width >= 32, g.width <= 1000, g.height >= 32, g.height <= 1000 else {
                throw ProfileError.invalidGeometry(widget.id)
            }
            if let macro = widget.macro {
                guard widget.action.bindings.isEmpty, !widget.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, widget.label.count <= 128 else { throw MacroError.invalidPlan }
                _ = try macro.validated()
            }
            else {
                guard !widget.action.bindings.isEmpty else { throw ProfileError.emptyAction(widget.id) }
                guard widget.action.bindings.count <= 16 else { throw ProfileError.tooManyBindings(widget.id) }
            }
            guard widget.opacity.isFinite, (0.1...1).contains(widget.opacity) else { throw ProfileError.invalidOpacity(widget.id) }
            _ = try widget.appearance.validated()
            guard widget.timedDurationSeconds.isFinite, (0.1...3600).contains(widget.timedDurationSeconds) else { throw ProfileError.invalidTimedDuration(widget.id) }
        }
        let rg = radial.geometry
        guard rg.x.isFinite, rg.y.isFinite, rg.width >= 64, rg.width <= 1000, rg.height >= 64, rg.height <= 1000, abs(rg.width - rg.height) < 0.5 else { throw ProfileError.invalidRadialGeometry }
        guard radial.opacity.isFinite, (0.1...1).contains(radial.opacity) else { throw ProfileError.invalidRadialOpacity }
        return self
    }
}

public enum ProfileError: Error, Equatable {
    case unsupportedSchema(Int)
    case emptyWidgets
    case invalidGeometry(UUID)
    case emptyAction(UUID)
    case tooManyBindings(UUID)
    case duplicateWidget(UUID)
    case invalidOpacity(UUID)
    case invalidTimedDuration(UUID)
    case invalidRadialGeometry
    case invalidRadialOpacity
    case invalidName
    case invalidBundleIdentifier
}

public protocol InputSink: AnyObject {
    func press(_ binding: KeyBinding)
    func release(_ binding: KeyBinding)
    func releaseAll()
}

public protocol Cancellable: AnyObject {
    func cancel()
}

public protocol ActionScheduler: AnyObject {
    var now: TimeInterval { get }
    @discardableResult func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> Cancellable
}

public extension ActionScheduler {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

public final class ModeManager {
    public typealias OwnerID = UUID

    private struct OwnerState {
        var action: KeyAction
        var mode: TriggerMode
        var active: Bool
        var generation: UInt64
        var pending: PendingRelease?
        var timedToken: Cancellable?
        var pressedAt: TimeInterval
        var sequenceIndex: Int = 0
        var sequenceBinding: KeyBinding?
        var sequenceToken: Cancellable?
    }

    private struct PendingRelease {
        let generation: UInt64
        let token: Cancellable
    }

    private let sink: InputSink
    private let scheduler: ActionScheduler
    private let compatibilityMilliseconds: Int
    private var owners: [OwnerID: OwnerState] = [:]
    private var heldCounts: [KeyBinding: Int] = [:]
    private var nextGeneration: UInt64 = 0

    public init(sink: InputSink, scheduler: ActionScheduler, compatibilityMilliseconds: Int = 33) {
        self.sink = sink
        self.scheduler = scheduler
        self.compatibilityMilliseconds = min(max(compatibilityMilliseconds, 1), 1000)
    }

    public var activeOwnerCount: Int { owners.values.filter(\.active).count }

    public func isActive(owner: OwnerID) -> Bool {
        owners[owner]?.active == true
    }

    public func handlePress(owner: OwnerID, action: KeyAction, mode: TriggerMode) {
        if var state = owners[owner] {
            if let pending = state.pending {
                pending.token.cancel()
                state.pending = nil
                nextGeneration &+= 1
                state.generation = nextGeneration
                state.active = true
                state.pressedAt = scheduler.now
                owners[owner] = state
                return
            }
            if mode == .toggle, state.active {
                handleRelease(owner: owner, emergency: false)
            }
            if mode == .timedToggle, state.active {
                handleRelease(owner: owner, emergency: false)
            }
            return
        }

        nextGeneration &+= 1
        let state = OwnerState(action: action, mode: mode, active: true, generation: nextGeneration, pending: nil, timedToken: nil, pressedAt: scheduler.now)
        owners[owner] = state
        if action.combinationMode == .sequential {
            scheduleSequentialStep(owner: owner, generation: nextGeneration, index: 0)
        } else {
            for binding in action.bindings { acquire(binding) }
        }
    }

    public func handlePress(owner: OwnerID, action: KeyAction, mode: TriggerMode, timedDurationSeconds: Double) {
        handlePress(owner: owner, action: action, mode: mode)
        guard mode == .timedToggle, let state = owners[owner], state.active else { return }
        let duration = min(max(timedDurationSeconds.isFinite ? timedDurationSeconds : 5, 0.1), 3600)
        scheduleTimedRelease(owner: owner, generation: state.generation, after: duration)
    }

    public func handleRelease(owner: OwnerID) {
        handleRelease(owner: owner, emergency: false)
    }

    public func reset() {
        // Invalidate and cancel future work before releasing current input.
        nextGeneration &+= 1
        for state in owners.values {
            state.pending?.token.cancel()
            state.sequenceToken?.cancel()
            state.timedToken?.cancel()
        }
        owners.removeAll()
        heldCounts.removeAll()
        sink.releaseAll()
    }

    private func handleRelease(owner: OwnerID, emergency: Bool) {
        guard var state = owners[owner], state.active else { return }
        state.active = false
        state.timedToken?.cancel()
        state.timedToken = nil
        nextGeneration &+= 1
        state.generation = nextGeneration

        if state.action.combinationMode == .sequential {
            state.sequenceToken?.cancel()
            state.sequenceToken = nil
            let binding = state.sequenceBinding
            state.sequenceBinding = nil
            owners[owner] = state
            if let binding { release(binding) }
            owners.removeValue(forKey: owner)
            return
        }

        owners[owner] = state

        let delay = emergency ? 0 : max(0, TimeInterval(compatibilityMilliseconds) / 1000.0 - (scheduler.now - state.pressedAt))
        if delay <= 0 {
            finishRelease(owner: owner, generation: state.generation)
            return
        }

        let generation = state.generation
        let token = scheduler.schedule(after: delay) { [weak self] in
            self?.finishRelease(owner: owner, generation: generation)
        }
        guard var latest = owners[owner], latest.generation == generation else {
            token.cancel()
            return
        }
        latest.pending = PendingRelease(generation: generation, token: token)
        owners[owner] = latest
    }

    private func scheduleTimedRelease(owner: OwnerID, generation: UInt64, after delay: TimeInterval) {
        let token = scheduler.schedule(after: max(delay, 0)) { [weak self] in
            guard let self, let state = self.owners[owner], state.generation == generation, state.active else { return }
            self.handleRelease(owner: owner, emergency: false)
        }
        guard var state = owners[owner], state.generation == generation else { token.cancel(); return }
        state.timedToken?.cancel()
        state.timedToken = token
        owners[owner] = state
    }

    private func finishRelease(owner: OwnerID, generation: UInt64) {
        guard let state = owners[owner], state.generation == generation, !state.active else { return }
        for binding in state.action.bindings { release(binding) }
        owners.removeValue(forKey: owner)
    }

    private func scheduleSequentialStep(owner: OwnerID, generation: UInt64, index: Int) {
        guard var state = owners[owner], state.generation == generation, state.active else { return }
        guard index < state.action.bindings.count else {
            state.sequenceIndex = index
            state.sequenceBinding = nil
            state.sequenceToken = nil
            owners[owner] = state
            return
        }

        let binding = state.action.bindings[index]
        acquire(binding)
        state.sequenceIndex = index
        state.sequenceBinding = binding
        let delay = TimeInterval(compatibilityMilliseconds) / 1000.0
        let token = scheduler.schedule(after: delay) { [weak self] in
            self?.finishSequentialStep(owner: owner, generation: generation, index: index)
        }
        state.sequenceToken = token
        owners[owner] = state
    }

    private func finishSequentialStep(owner: OwnerID, generation: UInt64, index: Int) {
        guard var state = owners[owner], state.generation == generation, state.active,
              state.sequenceIndex == index, let binding = state.sequenceBinding else { return }
        state.sequenceBinding = nil
        state.sequenceToken = nil
        owners[owner] = state
        release(binding)
        scheduleSequentialStep(owner: owner, generation: generation, index: index + 1)
    }

    private func acquire(_ binding: KeyBinding) {
        let count = heldCounts[binding, default: 0]
        heldCounts[binding] = count + 1
        if count == 0 { sink.press(binding) }
    }

    private func release(_ binding: KeyBinding) {
        guard let count = heldCounts[binding], count > 0 else { return }
        if count == 1 {
            heldCounts.removeValue(forKey: binding)
            sink.release(binding)
        } else {
            heldCounts[binding] = count - 1
        }
    }
}

public enum EmergencyResult: Equatable {
    case regular
    case ignored
    case emergency
}

public final class EmergencyResetController {
    private let lock = NSLock()
    private let maximumGap: TimeInterval
    private var editCount = 0
    private var escapeCount = 0
    private var lastEdit: TimeInterval?
    private var lastEscape: TimeInterval?
    private let resetAction: () -> Void

    public init(maximumGap: TimeInterval = 2, resetAction: @escaping () -> Void) {
        self.maximumGap = maximumGap
        self.resetAction = resetAction
    }

    public func recordEditClick(at time: TimeInterval) -> EmergencyResult {
        lock.lock()
        if let lastEdit, time - lastEdit > maximumGap { editCount = 0 }
        editCount += 1
        lastEdit = time
        if editCount >= 5 {
            editCount = 0
            lastEdit = nil
            lock.unlock()
            resetAction()
            return .emergency
        }
        lock.unlock()
        return .regular
    }

    public func recordEscapeKeyDown(at time: TimeInterval, isAutoRepeat: Bool) -> EmergencyResult {
        lock.lock()
        guard !isAutoRepeat else {
            lock.unlock()
            return .ignored
        }
        if let lastEscape, time - lastEscape > maximumGap { escapeCount = 0 }
        escapeCount += 1
        lastEscape = time
        if escapeCount >= 5 {
            escapeCount = 0
            lastEscape = nil
            lock.unlock()
            resetAction()
            return .emergency
        }
        lock.unlock()
        return .regular
    }

    public func resetCounters() {
        lock.lock()
        defer { lock.unlock() }
        editCount = 0
        escapeCount = 0
        lastEdit = nil
        lastEscape = nil
    }
}

public final class InMemoryInputSink: InputSink {
    public enum Event: Equatable { case press(KeyBinding); case release(KeyBinding); case releaseAll }
    public private(set) var events: [Event] = []
    public init() {}
    public func press(_ binding: KeyBinding) { events.append(.press(binding)) }
    public func release(_ binding: KeyBinding) { events.append(.release(binding)) }
    public func releaseAll() { events.append(.releaseAll) }
}

public final class TestScheduler: ActionScheduler {
    private struct Item { let id: UUID; let deadline: TimeInterval; let action: () -> Void; var cancelled: Bool }
    private var items: [Item] = []
    public private(set) var now: TimeInterval = 0
    public init() {}
    @discardableResult public func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> Cancellable {
        let id = UUID()
        items.append(Item(id: id, deadline: now + max(delay, 0), action: action, cancelled: false))
        return Token { [weak self] in self?.cancel(id: id) }
    }
    public func advance(by duration: TimeInterval) {
        let target = now + max(duration, 0)
        while let index = items.indices.filter({ !items[$0].cancelled && items[$0].deadline <= target })
            .min(by: { items[$0].deadline < items[$1].deadline }) {
            let item = items.remove(at: index)
            now = item.deadline
            if !item.cancelled { item.action() }
        }
        now = target
        items.removeAll(where: { $0.cancelled })
    }
    private func cancel(id: UUID) { if let index = items.firstIndex(where: { $0.id == id }) { items[index].cancelled = true } }
    private final class Token: Cancellable {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        func cancel() { action() }
    }
}
