import AppKit
import OverSlayCore

extension OverlayRect {
    init(_ rect: NSRect) { self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height) }
    var nsRect: NSRect { NSRect(x: x, y: y, width: width, height: height) }
}

enum EditorPulseClock {
    private static let views = NSHashTable<NSView>.weakObjects()
    private static var timer: Timer?
    private static var accessibilityObserver: NSObjectProtocol?
    static func register(_ view: NSView) {
        views.add(view)
        if accessibilityObserver == nil {
            accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
            ) { _ in
                timer?.invalidate(); timer = nil
                views.allObjects.forEach { $0.needsDisplay = true }
                if let first = views.allObjects.first { register(first) }
            }
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            views.allObjects.forEach { $0.needsDisplay = true }
            if views.allObjects.isEmpty { timer?.invalidate(); timer = nil }
        }
    }
    static func unregister(_ view: NSView) {
        views.remove(view)
        if views.allObjects.isEmpty { timer?.invalidate(); timer = nil }
    }
    static var phase: CGFloat {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return 0 }
        return CGFloat(ProcessInfo.processInfo.systemUptime.truncatingRemainder(dividingBy: 2.8) / 2.8 * 2 * .pi)
    }
}

enum EditorChrome {
    static func draw(in bounds: NSRect, selected: Bool, phase: CGFloat = 0, hovered: ResizeHandle? = nil,
                     snapped: OverlayResizeEdges = .init()) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let alpha = 0.78 + 0.16 * (0.5 + 0.5 * sin(phase))
        let blue = NSColor.systemBlue.withAlphaComponent(alpha)
        let halo = NSBezierPath(roundedRect: rect, xRadius: min(11, rect.height / 2), yRadius: min(11, rect.height / 2))
        NSColor.black.withAlphaComponent(0.48).setStroke(); halo.lineWidth = selected ? 3.5 : 3; halo.stroke()
        blue.setStroke(); halo.lineWidth = selected ? 1.5 : 1; halo.stroke()
        let accent = NSBezierPath(); accent.lineWidth = 2; accent.lineCapStyle = .round
        if snapped.left { accent.move(to: NSPoint(x: rect.minX, y: rect.minY + 9)); accent.line(to: NSPoint(x: rect.minX, y: rect.maxY - 9)) }
        if snapped.right { accent.move(to: NSPoint(x: rect.maxX, y: rect.minY + 9)); accent.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 9)) }
        if snapped.bottom { accent.move(to: NSPoint(x: rect.minX + 9, y: rect.minY)); accent.line(to: NSPoint(x: rect.maxX - 9, y: rect.minY)) }
        if snapped.top { accent.move(to: NSPoint(x: rect.minX + 9, y: rect.maxY)); accent.line(to: NSPoint(x: rect.maxX - 9, y: rect.maxY)) }
        NSColor.systemBlue.blended(withFraction: 0.4, of: .white)?.setStroke(); accent.stroke()
        let c: CGFloat = min(7, min(rect.width, rect.height) * 0.18)
        let e: CGFloat = min(8, max(4, min(rect.width, rect.height) * 0.14))
        let corners: [(NSPoint, CGFloat, CGFloat)] = [
            (NSPoint(x: rect.minX, y: rect.minY), 1, 1), (NSPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (NSPoint(x: rect.minX, y: rect.maxY), 1, -1), (NSPoint(x: rect.maxX, y: rect.maxY), -1, -1)
        ]
        let handles: [ResizeHandle] = [.bottomLeft, .bottomRight, .topLeft, .topRight]
        for (index, corner) in corners.enumerated() {
            let (p, sx, sy) = corner
            (hovered == handles[index] ? NSColor.white : blue).setStroke()
            let path = NSBezierPath(); path.lineCapStyle = .round; path.lineJoinStyle = .round; path.lineWidth = 2
            path.move(to: NSPoint(x: p.x + sx * c, y: p.y)); path.line(to: p); path.line(to: NSPoint(x: p.x, y: p.y + sy * c)); path.stroke()
        }
        for point in [NSPoint(x: rect.midX, y: rect.minY), NSPoint(x: rect.midX, y: rect.maxY)] {
            (hovered == (point.y == rect.minY ? .bottom : .top) ? NSColor.white : blue).setStroke()
            let tick = NSBezierPath(); tick.lineCapStyle = .round; tick.lineWidth = 2
            tick.move(to: NSPoint(x: point.x - e / 2, y: point.y)); tick.line(to: NSPoint(x: point.x + e / 2, y: point.y)); tick.stroke()
        }
        for point in [NSPoint(x: rect.minX, y: rect.midY), NSPoint(x: rect.maxX, y: rect.midY)] {
            (hovered == (point.x == rect.minX ? .left : .right) ? NSColor.white : blue).setStroke()
            let tick = NSBezierPath(); tick.lineCapStyle = .round; tick.lineWidth = 2
            tick.move(to: NSPoint(x: point.x, y: point.y - e / 2)); tick.line(to: NSPoint(x: point.x, y: point.y + e / 2)); tick.stroke()
        }
    }
}

typealias ResizeHandle = OverlayResizeHandle

extension OverlayResizeHandle {
    static func zones(in b: NSRect) -> [(ResizeHandle, NSRect)] {
        let band = min(12, max(0, (min(b.width, b.height) - 12) / 2))
        return [
            (.bottomLeft, NSRect(x: b.minX, y: b.minY, width: band, height: band)),
            (.bottomRight, NSRect(x: b.maxX - band, y: b.minY, width: band, height: band)),
            (.topLeft, NSRect(x: b.minX, y: b.maxY - band, width: band, height: band)),
            (.topRight, NSRect(x: b.maxX - band, y: b.maxY - band, width: band, height: band)),
            (.bottom, NSRect(x: b.minX + band, y: b.minY, width: b.width - 2 * band, height: band)),
            (.top, NSRect(x: b.minX + band, y: b.maxY - band, width: b.width - 2 * band, height: band)),
            (.left, NSRect(x: b.minX, y: b.minY + band, width: band, height: b.height - 2 * band)),
            (.right, NSRect(x: b.maxX - band, y: b.minY + band, width: band, height: b.height - 2 * band))
        ]
    }

    var cursor: NSCursor {
        switch self {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        default: return Self.diagonalCursor(for: self)
        }
    }

    private static func diagonalCursor(for handle: Self) -> NSCursor {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let ascending = handle == .bottomLeft || handle == .topRight
            let a = NSPoint(x: 5, y: ascending ? 5 : 19), b = NSPoint(x: 19, y: ascending ? 19 : 5)
            let path = NSBezierPath(); path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.move(to: a); path.line(to: b)
            path.move(to: NSPoint(x: a.x + 6, y: a.y)); path.line(to: a); path.line(to: NSPoint(x: a.x, y: a.y + (ascending ? 6 : -6)))
            path.move(to: NSPoint(x: b.x - 6, y: b.y)); path.line(to: b); path.line(to: NSPoint(x: b.x, y: b.y + (ascending ? -6 : 6)))
            NSColor.black.setStroke(); path.lineWidth = 4; path.stroke()
            NSColor.white.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }

    static func hit(_ p: NSPoint, in b: NSRect) -> ResizeHandle? {
        zones(in: b).first { $0.1.contains(p) }?.0
    }
}
