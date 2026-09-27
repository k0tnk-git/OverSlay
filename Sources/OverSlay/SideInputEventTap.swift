import CoreGraphics
import Foundation
import OverSlayCore

/// Suppresses/configures mouse side inputs while the radial widget is actively dragged.
final class SideInputEventTap {
    private let lock = NSLock()
    private let injector: CGKeyInjector
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var tracking = false
    private var config = RadialWidgetConfig()
    private var heldRightAction: SideInputAction?
    private var swallowRightMouseUp = false
    private var rightDownPassedThrough = false
    private var scrollRemainder = 0.0
    private var scrollDirection = 0

    init(injector: CGKeyInjector) { self.injector = injector }
    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return source != nil && (tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false) }

    func update(config: RadialWidgetConfig) {
        lock.lock(); self.config = config; lock.unlock()
    }

    func setTracking(_ tracking: Bool) {
        lock.lock()
        self.tracking = tracking
        if !tracking { scrollRemainder = 0; scrollDirection = 0 }
        if !tracking, let held = heldRightAction {
            heldRightAction = nil
            swallowRightMouseUp = true
            release(held)
            lock.unlock()
            return
        }
        lock.unlock()
    }

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard tap == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let mask = (CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.scrollWheel.rawValue))
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<SideInputEventTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                owner.lock.lock(); if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }; owner.lock.unlock()
                return Unmanaged.passUnretained(event)
            }
            return owner.route(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: context) else { return }
        tap = created
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            CFMachPortInvalidate(created); tap = nil; return
        }
        self.source = source
        thread = Thread { [weak self, source] in
            let loop = CFRunLoopGetCurrent()!
            guard self?.attach(source, to: loop) == true else { return }
            CFRunLoopRun()
        }
        thread?.name = "io.github.k0tnk-git.OverSlay.side-input-tap"
        thread?.start()
    }

    private func attach(_ source: CFRunLoopSource, to loop: CFRunLoop) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard tap != nil, self.source === source else { return false }
        runLoop = loop
        CFRunLoopAddSource(loop, source, .commonModes)
        return true
    }

    private func route(_ type: CGEventType, _ event: CGEvent) -> Bool {
        lock.lock()
        if type == .rightMouseUp, swallowRightMouseUp {
            swallowRightMouseUp = false
            lock.unlock()
            return true
        }
        if type == .rightMouseUp, rightDownPassedThrough {
            rightDownPassedThrough = false
            lock.unlock()
            return false
        }
        if type == .rightMouseDown, !tracking {
            rightDownPassedThrough = true
            lock.unlock()
            return false
        }
        guard tracking else { lock.unlock(); return false }
        if type == .rightMouseDown {
            swallowRightMouseUp = false
            let action = config.rightMouseAction
            if case .passthrough = action { rightDownPassedThrough = true; lock.unlock(); return false }
            rightDownPassedThrough = false
            heldRightAction = action
            press(action)
            lock.unlock()
            return true
        }
        if type == .rightMouseUp {
            guard let action = heldRightAction else { lock.unlock(); return false }
            heldRightAction = nil
            release(action)
            lock.unlock()
            return true
        }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let fixedDelta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let delta = continuous
            ? Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let effectiveDelta = delta == 0 && continuous ? fixedDelta : delta
        guard effectiveDelta != 0 else { lock.unlock(); return false }
        let action = effectiveDelta > 0 ? config.scrollUpAction : config.scrollDownAction
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        if case .passthrough = action { lock.unlock(); return false }
        if momentum { lock.unlock(); return true }
        switch action {
        case .passthrough: lock.unlock(); return false
        case .none: lock.unlock(); return true
        case .custom(let binding):
            guard continuous else { injector.pulse(binding); lock.unlock(); return true }
            let direction = effectiveDelta > 0 ? 1 : -1
            if scrollDirection != direction { scrollDirection = direction; scrollRemainder = 0 }
            scrollRemainder += abs(effectiveDelta)
            let pulseCount = min(Int(scrollRemainder / 24), 3)
            scrollRemainder -= Double(pulseCount * 24)
            for _ in 0..<pulseCount { injector.pulse(binding) }
            lock.unlock()
            return true
        }
    }

    private func press(_ action: SideInputAction) {
        switch action {
        case .sprint: injector.press(KeyBinding(keyCode: 56))
        case .custom(let binding): injector.press(binding)
        case .passthrough, .none: break
        }
    }
    private func release(_ action: SideInputAction) {
        switch action {
        case .sprint: injector.release(KeyBinding(keyCode: 56))
        case .custom(let binding): injector.release(binding)
        case .passthrough, .none: break
        }
    }

    func stop() {
        lock.lock()
        let held = heldRightAction; heldRightAction = nil
        let tap = self.tap; self.tap = nil
        let source = self.source; self.source = nil
        let loop = runLoop; runLoop = nil; tracking = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source, let loop { CFRunLoopRemoveSource(loop, source, .commonModes); CFRunLoopStop(loop); CFRunLoopWakeUp(loop) }
        thread = nil
        if let held { release(held) }
        lock.unlock()
    }

    deinit { stop() }
}
