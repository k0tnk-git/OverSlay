import Foundation
import IOKit.hid
import OverSlayCore

/// User-space HID gamepad publisher. Availability is determined by the OS at runtime;
/// creation can fail when the current signing identity lacks the required entitlement.
final class VirtualJoystickSink: AnalogInputSink {
    private let queue = DispatchQueue(label: "io.github.k0tnk-git.OverSlay.virtual-joystick", qos: .userInteractive)
    private var device: IOHIDUserDevice?

    var isAvailable: Bool { queue.sync { device != nil } }

    @discardableResult
    func start() -> Bool {
        queue.sync {
            if device != nil { return true }
            let descriptor: [UInt8] = [
                0x05, 0x01,       // Generic Desktop
                0x09, 0x05,       // Game Pad
                0xA1, 0x01,       // Application collection
                0x09, 0x30,       // X
                0x09, 0x31,       // Y
                0x16, 0x00, 0x80, // Logical minimum -32768
                0x26, 0xFF, 0x7F, // Logical maximum 32767
                0x75, 0x10,       // 16-bit values
                0x95, 0x02,       // Two axes
                0x81, 0x02,       // Data, variable, absolute
                0xC0
            ]
            let properties: [String: Any] = [
                "ReportDescriptor": Data(descriptor),
                "Product": "OverSlay Virtual Gamepad",
                "Manufacturer": "OverSlay"
            ]
            guard let created = IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault, properties as CFDictionary, 0) else {
                NSLog("OverSlay: virtual HID creation failed; check macOS support, signing and com.apple.developer.hid.virtual.device entitlement")
                return false
            }
            device = created
            send(AnalogStickValue(x: 0, y: 0))
            return true
        }
    }

    func updateAxes(_ value: AnalogStickValue) {
        queue.async { [weak self] in self?.send(value) }
    }

    func releaseAxes() {
        queue.async { [weak self] in self?.send(AnalogStickValue(x: 0, y: 0)) }
    }

    func stop() {
        queue.sync {
            send(AnalogStickValue(x: 0, y: 0))
            device = nil
        }
    }

    private func send(_ value: AnalogStickValue) {
        guard let device else { return }
        let x = Int16((min(max(value.x.isFinite ? value.x : 0, -1), 1) * 32767).rounded()).littleEndian
        // HID Y is positive down; Core uses positive up.
        let y = Int16((min(max(value.y.isFinite ? -value.y : 0, -1), 1) * 32767).rounded()).littleEndian
        var report = [UInt8](repeating: 0, count: 4)
        withUnsafeBytes(of: x) { report[0] = $0[0]; report[1] = $0[1] }
        withUnsafeBytes(of: y) { report[2] = $0[0]; report[3] = $0[1] }
        _ = report.withUnsafeBufferPointer { buffer in
            IOHIDUserDeviceHandleReportWithTimeStamp(device, mach_absolute_time(), buffer.baseAddress!, buffer.count)
        }
    }
}
