import Foundation

public extension KeyAction {
    /// A simultaneous macro chord applies the complete modifier set before any primary key.
    var macroChord: KeyAction {
        func flag(_ code: UInt16) -> UInt64 {
            switch code {
            case 54, 55: return 1 << 20
            case 56, 60: return 1 << 17
            case 58, 61: return 1 << 19
            case 59, 62: return 1 << 18
            default: return 0
            }
        }
        let flags = bindings.reduce(UInt64(0)) { $0 | $1.modifiers | flag($1.keyCode) }
        let ordered = bindings.sorted { flag($0.keyCode) != 0 && flag($1.keyCode) == 0 }
        return KeyAction(bindings: ordered.map { KeyBinding(keyCode: $0.keyCode, modifiers: flags) })
    }
}

public enum MacroStep: Codable, Equatable, Sendable {
    case tap(KeyAction, milliseconds: Int)
    case hold(KeyAction, milliseconds: Int, during: [TimedMacroTap])
    case wait(milliseconds: Int)
    case text(String, intervalMilliseconds: Int)

    var isKey: Bool {
        switch self { case .tap, .hold: return true; default: return false }
    }
    var duration: TimeInterval {
        switch self {
        case let .tap(_, ms), let .hold(_, ms, _): return Double(max(33, ms)) / 1000
        case let .wait(ms): return Double(ms) / 1000
        case let .text(value, ms): return Double(max(0, value.count - 1)) * Double(ms) / 1000
        }
    }
}

public struct TimedMacroTap: Codable, Equatable, Sendable {
    public var offsetMilliseconds: Int
    public var action: KeyAction
    public var durationMilliseconds: Int
    public init(offsetMilliseconds: Int, action: KeyAction, durationMilliseconds: Int = 33) {
        self.offsetMilliseconds = offsetMilliseconds
        self.action = action
        self.durationMilliseconds = durationMilliseconds
    }
}

public enum MacroError: Error, Equatable, LocalizedError {
    case invalidPlan, inputConflict, targetChanged, deliveryFailed, timingOverrun
    public var errorDescription: String? {
        switch self {
        case .invalidPlan: return L10n.text("Проверьте шаги, сочетания и интервалы макроса.")
        case .inputConflict: return L10n.text("Макрос остановлен: конфликт с удерживаемыми клавишами.")
        case .targetChanged: return L10n.text("Макрос остановлен: сменилось приложение или недоступен ввод.")
        case .deliveryFailed: return L10n.text("Не удалось отправить ввод макроса.")
        case .timingOverrun: return L10n.text("Макрос остановлен: вложенное нажатие не помещается в удержание.")
        }
    }
}

public struct MacroDefinition: Codable, Equatable, Sendable {
    public var steps: [MacroStep]
    public var releaseGapMilliseconds: Int
    public init(steps: [MacroStep], releaseGapMilliseconds: Int = 33) {
        self.steps = steps
        self.releaseGapMilliseconds = releaseGapMilliseconds
    }
    private enum CodingKeys: String, CodingKey { case steps, releaseGapMilliseconds }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps = try c.decode([MacroStep].self, forKey: .steps)
        releaseGapMilliseconds = try c.decodeIfPresent(Int.self, forKey: .releaseGapMilliseconds) ?? 33
    }
    public static func milliseconds(_ value: String, allowZero: Bool = false, maximum: Int = 3_600_000) -> Int? {
        guard let seconds = Double(value.replacingOccurrences(of: ",", with: ".")),
              seconds.isFinite, seconds >= 0, seconds <= Double(maximum) / 1000 else { return nil }
        let ms = Int((seconds * 1000).rounded())
        return ((allowZero ? 0 : 1)...maximum).contains(ms) ? ms : nil
    }
    public func validated(compatibilityMilliseconds: Int = 33) throws -> MacroDefinition {
        guard !steps.isEmpty, steps.count <= 128, (1...1000).contains(releaseGapMilliseconds),
              compatibilityMilliseconds == 33 else { throw MacroError.invalidPlan }
        var count = steps.count
        var textCount = 0
        for step in steps {
            switch step {
            case let .tap(action, ms):
                try validate(action)
                guard (1...1000).contains(ms) else { throw MacroError.invalidPlan }
            case let .hold(action, ms, during):
                try validate(action)
                guard (10...3_600_000).contains(ms) else { throw MacroError.invalidPlan }
                count += during.count
                guard count <= 128 else { throw MacroError.invalidPlan }
                var ends: [UInt16: Int] = [:]
                let parentKeys = Set(action.bindings.map(\.keyCode))
                for item in during.sorted(by: { $0.offsetMilliseconds < $1.offsetMilliseconds }) {
                    try validate(item.action)
                    guard (0...max(ms, 33)).contains(item.offsetMilliseconds),
                          (1...3_600_000).contains(item.durationMilliseconds) else { throw MacroError.invalidPlan }
                    let end = item.offsetMilliseconds + max(33, item.durationMilliseconds)
                    guard end <= max(ms, 33) else { throw MacroError.invalidPlan }
                    for key in item.action.bindings.map(\.keyCode) {
                        guard !parentKeys.contains(key),
                              ends[key].map({ $0 + releaseGapMilliseconds <= item.offsetMilliseconds }) ?? true else { throw MacroError.invalidPlan }
                        ends[key] = end
                    }
                }
            case let .wait(ms):
                guard (1...3_600_000).contains(ms) else { throw MacroError.invalidPlan }
            case let .text(value, interval):
                textCount += value.count
                guard !value.isEmpty, textCount <= 4096, (1...1000).contains(interval),
                      value.unicodeScalars.allSatisfy({
                          $0.properties.generalCategory != .control && $0.value != 0x2028 && $0.value != 0x2029
                      }),
                      value.allSatisfy({ String($0).utf16.count <= 20 }) else { throw MacroError.invalidPlan }
            }
        }
        guard plannedDuration <= 3600 else { throw MacroError.invalidPlan }
        return self
    }
    private func validate(_ action: KeyAction) throws {
        let keys = action.bindings.map(\.keyCode)
        let supported: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
        guard (1...16).contains(keys.count), action.combinationMode == .simultaneous,
              Set(keys).count == keys.count,
              action.bindings.allSatisfy({ $0.keyCode <= 126 && ($0.modifiers & ~supported) == 0 }) else { throw MacroError.invalidPlan }
    }
    func gap(after index: Int) -> TimeInterval {
        guard index + 1 < steps.count, steps[index].isKey, steps[index + 1].isKey else { return 0 }
        return Double(releaseGapMilliseconds) / 1000
    }
    public var plannedDuration: TimeInterval {
        steps.indices.reduce(0) { $0 + steps[$1].duration + gap(after: $1) }
    }
}

/// All completions return on the runner's executor (the main thread in the app).
/// cancel invalidates queued work before releasing only this run's ownership.
public protocol MacroSink: AnyObject {
    func beginMacro(run: UUID)
    func macroPress(_ action: KeyAction, owner: UUID, run: UUID, latestStart: TimeInterval?, completion: @escaping (MacroError?) -> Void)
    func macroRelease(owner: UUID, run: UUID, completion: @escaping () -> Void)
    func macroText(_ character: String, run: UUID, completion: @escaping (MacroError?) -> Void)
    func cancelMacro(run: UUID)
}

public final class MacroRunner {
    public private(set) var isRunning = false
    public private(set) var lastError: MacroError?
    public var progress: Double {
        guard isRunning else { return 0 }
        let elapsed = min(budget, max(0, scheduler.now - startedAt))
        return max(0.001, 1 - (completed + elapsed) / max(plan.plannedDuration, 0.001))
    }
    private let sink: MacroSink
    private let scheduler: ActionScheduler
    private var run = UUID()
    private var tokens: [Cancellable] = []
    private var finish: ((Bool) -> Void)?
    private var plan = MacroDefinition(steps: [])
    private var completed: TimeInterval = 0
    private var budget: TimeInterval = 0
    private var startedAt: TimeInterval = 0
    private var children = 0
    private var parentDeadlineReached = false
    public init(sink: MacroSink, scheduler: ActionScheduler) { self.sink = sink; self.scheduler = scheduler }
    @discardableResult public func start(_ definition: MacroDefinition, completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard !isRunning else { return false }
        guard let valid = try? definition.validated() else { lastError = .invalidPlan; return false }
        plan = valid; run = UUID(); finish = completion; isRunning = true; lastError = nil
        completed = 0; budget = 0; startedAt = scheduler.now
        sink.beginMacro(run: run)
        step(0, run)
        return true
    }
    public func cancel() { stop(false) }
    private func active(_ id: UUID) -> Bool { isRunning && run == id }
    private func fail(_ error: MacroError) { lastError = error; stop(false) }
    private func startBudget(_ duration: TimeInterval) {
        completed += budget; budget = duration; startedAt = scheduler.now
    }
    private func step(_ index: Int, _ id: UUID) {
        guard active(id) else { return }
        guard index < plan.steps.count else { stop(true); return }
        let value = plan.steps[index]
        switch value {
        case let .wait(ms):
            startBudget(value.duration)
            schedule(Double(ms) / 1000, id) { [weak self] in self?.next(index, id) }
        case let .text(text, interval):
            let chars = Array(text).map(String.init)
            startBudget(0)
            textCharacter(chars, 0, interval, index, id)
        case let .tap(action, _):
            keyBlock(action, [], index, id)
        case let .hold(action, _, during):
            keyBlock(action, during, index, id)
        }
    }
    private func keyBlock(_ action: KeyAction, _ during: [TimedMacroTap], _ index: Int, _ id: UUID) {
        let owner = UUID()
        sink.macroPress(action, owner: owner, run: id, latestStart: nil) { [weak self] error in
            guard let self, self.active(id) else { return }
            if let error { self.fail(error); return }
            let duration = self.plan.steps[index].duration
            self.startBudget(duration)
            let deadline = self.scheduler.now + duration
            self.children = during.count; self.parentDeadlineReached = false
            let finishParent: () -> Void = { [weak self] in
                guard let self, self.active(id), self.parentDeadlineReached, self.children == 0 else { return }
                self.sink.macroRelease(owner: owner, run: id) { [weak self] in self?.next(index, id) }
            }
            for child in during.sorted(by: { $0.offsetMilliseconds < $1.offsetMilliseconds }) {
                self.schedule(Double(child.offsetMilliseconds) / 1000, id) { [weak self] in
                    guard let self else { return }
                    let length = Double(max(33, child.durationMilliseconds)) / 1000
                    guard self.scheduler.now + length <= deadline + 0.000001 else { self.fail(.timingOverrun); return }
                    let childOwner = UUID()
                    self.sink.macroPress(child.action, owner: childOwner, run: id, latestStart: deadline - length) { [weak self] error in
                        guard let self, self.active(id) else { return }
                        if let error { self.fail(error); return }
                        guard self.scheduler.now + length <= deadline + 0.000001 else { self.fail(.timingOverrun); return }
                        self.schedule(length, id) { [weak self] in
                            guard let self else { return }
                            self.sink.macroRelease(owner: childOwner, run: id) { [weak self] in
                                guard let self, self.active(id) else { return }
                                self.children -= 1; finishParent()
                            }
                        }
                    }
                }
            }
            self.schedule(duration, id) { [weak self] in
                self?.parentDeadlineReached = true; finishParent()
            }
        }
    }
    private func textCharacter(_ chars: [String], _ position: Int, _ interval: Int, _ index: Int, _ id: UUID) {
        guard active(id) else { return }
        sink.macroText(chars[position], run: id) { [weak self] error in
            guard let self, self.active(id) else { return }
            if let error { self.fail(error); return }
            guard position + 1 < chars.count else { self.next(index, id); return }
            let delay = Double(interval) / 1000
            self.startBudget(delay)
            self.schedule(delay, id) { [weak self] in self?.textCharacter(chars, position + 1, interval, index, id) }
        }
    }
    private func next(_ index: Int, _ id: UUID) {
        guard active(id) else { return }
        let gap = plan.gap(after: index)
        if gap > 0 {
            startBudget(gap)
            schedule(gap, id) { [weak self] in self?.step(index + 1, id) }
        } else { step(index + 1, id) }
    }
    private func schedule(_ delay: TimeInterval, _ id: UUID, _ body: @escaping () -> Void) {
        tokens.append(scheduler.schedule(after: delay) { [weak self] in
            guard let self, self.active(id) else { return }; body()
        })
    }
    private func stop(_ success: Bool) {
        guard isRunning else { return }
        isRunning = false
        tokens.forEach { $0.cancel() }; tokens.removeAll()
        sink.cancelMacro(run: run)
        let callback = finish; finish = nil; callback?(success)
    }
}
