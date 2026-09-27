import CoreGraphics
import Foundation

final class EscapeEventTap {
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var handler: ((Bool) -> Bool)?

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    func start(handler: @escaping (Bool) -> Bool) {
        lock.lock(); defer { lock.unlock() }
        guard tap == nil else { return }
        self.handler = handler
        let context = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let instance = Unmanaged<EscapeEventTap>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    instance.lock.lock()
                    if let tap = instance.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    instance.lock.unlock()
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown,
                      event.getIntegerValueField(.eventSourceUserData) != CGKeyInjector.eventMarker,
                      event.getIntegerValueField(.keyboardEventKeycode) == 53 else {
                    return Unmanaged.passUnretained(event)
                }
                let autoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                instance.lock.lock()
                let handler = instance.handler
                instance.lock.unlock()
                return handler?(autoRepeat) == true ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: context
        )
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source else { return }
        thread = Thread { [weak self, source] in
            let loop = CFRunLoopGetCurrent()!
            guard self?.attach(source, to: loop) == true else { return }
            CFRunLoopRun()
        }
        thread?.name = "io.github.k0tnk-git.OverSlay.escape-event-tap"
        thread?.start()
    }

    private func attach(_ source: CFRunLoopSource, to loop: CFRunLoop) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard tap != nil, self.source === source else { return false }
        runLoop = loop
        CFRunLoopAddSource(loop, source, .commonModes)
        return true
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(runLoop) }
            CFRunLoopWakeUp(runLoop)
        }
        source = nil
        self.tap = nil
        runLoop = nil
        thread = nil
        handler = nil
    }

    deinit { stop() }
}
