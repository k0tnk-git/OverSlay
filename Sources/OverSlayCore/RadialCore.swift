import Foundation

public struct RadialVector: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum RadialDirection: String, Equatable, Sendable {
    case up
    case upRight
    case right
    case downRight
    case down
    case downLeft
    case left
    case upLeft
}

public struct RadialConfig: Codable, Equatable, Sendable {
    public var directions: Int
    public var deadZone: Double
    public var releaseDelayMilliseconds: Int
    public var up: KeyAction
    public var down: KeyAction
    public var left: KeyAction
    public var right: KeyAction

    public init(
        directions: Int = 8,
        deadZone: Double = 0.2,
        releaseDelayMilliseconds: Int = 50,
        up: KeyAction,
        down: KeyAction,
        left: KeyAction,
        right: KeyAction
    ) {
        self.directions = directions == 4 ? 4 : 8
        self.deadZone = min(max(deadZone, 0), 1)
        self.releaseDelayMilliseconds = min(max(releaseDelayMilliseconds, 0), 1000)
        self.up = up
        self.down = down
        self.left = left
        self.right = right
    }
}

public final class RadialControlEngine {
    private let sink: InputSink
    private let scheduler: ActionScheduler
    private let config: RadialConfig
    private var heldBindings: Set<KeyBinding> = []
    private var pending: [KeyBinding: Cancellable] = [:]
    private var releaseIDs: [KeyBinding: UUID] = [:]

    public private(set) var direction: RadialDirection?

    public init(config: RadialConfig, sink: InputSink, scheduler: ActionScheduler) {
        self.config = config
        self.sink = sink
        self.scheduler = scheduler
    }

    public func update(offset: RadialVector) {
        let nextDirection = direction(for: offset)
        let nextBindings = bindings(for: nextDirection)
        for binding in nextBindings {
            pending.removeValue(forKey: binding)?.cancel()
            releaseIDs.removeValue(forKey: binding)
            if !heldBindings.contains(binding) {
                heldBindings.insert(binding)
                sink.press(binding)
            }
        }
        for binding in Array(heldBindings) where !nextBindings.contains(binding) {
            scheduleRelease(binding)
        }
        direction = nextDirection
    }

    public func releaseAll() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        releaseIDs.removeAll()
        for binding in heldBindings { sink.release(binding) }
        heldBindings.removeAll()
        direction = nil
    }

    private func direction(for offset: RadialVector) -> RadialDirection? {
        let magnitude = hypot(offset.x, offset.y)
        guard magnitude >= config.deadZone else { return nil }
        if config.directions == 4 {
            if abs(offset.x) > abs(offset.y) { return offset.x > 0 ? .right : .left }
            return offset.y > 0 ? .up : .down
        }

        let angle = atan2(offset.y, offset.x)
        let sector = Int((angle / (.pi / 4)).rounded())
        switch (sector + 8) % 8 {
        case 0: return .right
        case 1: return .upRight
        case 2: return .up
        case 3: return .upLeft
        case 4: return .left
        case 5: return .downLeft
        case 6: return .down
        default: return .downRight
        }
    }

    private func bindings(for direction: RadialDirection?) -> Set<KeyBinding> {
        guard let direction else { return [] }
        switch direction {
        case .up: return Set(config.up.bindings)
        case .right: return Set(config.right.bindings)
        case .down: return Set(config.down.bindings)
        case .left: return Set(config.left.bindings)
        case .upRight: return Set(config.up.bindings).union(config.right.bindings)
        case .downRight: return Set(config.down.bindings).union(config.right.bindings)
        case .downLeft: return Set(config.down.bindings).union(config.left.bindings)
        case .upLeft: return Set(config.up.bindings).union(config.left.bindings)
        }
    }

    private func scheduleRelease(_ binding: KeyBinding) {
        guard pending[binding] == nil else { return }
        let delay = TimeInterval(config.releaseDelayMilliseconds) / 1000
        if delay == 0 {
            heldBindings.remove(binding)
            sink.release(binding)
            return
        }
        let releaseID = UUID()
        releaseIDs[binding] = releaseID
        let token = scheduler.schedule(after: delay) { [weak self] in
            guard let self, self.heldBindings.contains(binding), self.releaseIDs[binding] == releaseID else { return }
            self.releaseIDs.removeValue(forKey: binding)
            self.pending.removeValue(forKey: binding)
            self.heldBindings.remove(binding)
            self.sink.release(binding)
        }
        pending[binding] = token
    }
}
