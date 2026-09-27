import AppKit
import OverSlayCore

enum ButtonAppearanceRenderer {
    static let palette: [String] = ["#555555", "#383B40", "#718096", "#7D9B76", "#C6A66B", "#B8796B", "#8875A8", "#D8D6D1"]

    static func color(_ hex: String) -> NSColor {
        let digits = String(hex.dropFirst())
        guard hex.count == 7, hex.first == "#", let value = UInt32(digits, radix: 16) else { return .darkGray }
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    static func draw(_ appearance: ButtonAppearance, in rect: NSRect, path: NSBezierPath, opacity: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let context = NSGraphicsContext.current?.cgContext
        context?.setAlpha(opacity)
        context?.beginTransparencyLayer(auxiliaryInfo: nil)
        switch appearance.pattern {
        case .solid:
            color(appearance.firstColor).setFill(); path.fill()
        case .gradient:
            NSGradient(starting: color(appearance.firstColor), ending: color(appearance.secondColor))?.draw(in: rect, angle: 90)
        case .stripes:
            color(appearance.firstColor).setFill(); path.fill()
            color(appearance.secondColor).setStroke()
            let lines = NSBezierPath(); lines.lineWidth = max(5, rect.width * 0.09)
            var x = rect.minX - rect.height
            while x < rect.maxX { lines.move(to: NSPoint(x: x, y: rect.minY)); lines.line(to: NSPoint(x: x + rect.height, y: rect.maxY)); x += max(12, rect.width * 0.22) }
            lines.stroke()
        case .checkered:
            color(appearance.firstColor).setFill(); path.fill()
            color(appearance.secondColor).setFill()
            let cell = max(8, min(rect.width, rect.height) / 4)
            var row = 0; var y = rect.minY
            while y < rect.maxY {
                var col = 0; var x = rect.minX
                while x < rect.maxX { if (row + col).isMultiple(of: 2) { NSBezierPath(rect: NSRect(x: x, y: y, width: cell, height: cell)).fill() }; x += cell; col += 1 }
                y += cell; row += 1
            }
        }
        context?.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class ButtonAppearancePreview: NSView {
    var buttonAppearance = ButtonAppearance.default { didSet { needsDisplay = true } }
    var opacity: CGFloat = 1 { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 72, height: 42) }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        ButtonAppearanceRenderer.draw(buttonAppearance, in: rect, path: path, opacity: opacity)
        NSColor.separatorColor.setStroke(); path.lineWidth = 1; path.stroke()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.85); shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width: 0, height: -1)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white, .shadow: shadow]
        let label = "Aa"
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}

final class AppearanceSwatch: NSButton {
    var swatchColor: NSColor = .darkGray { didSet { needsDisplay = true } }
    var selected = false { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 25, height: 23) }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        swatchColor.setFill(); path.fill()
        if !isEnabled { NSColor.windowBackgroundColor.withAlphaComponent(0.58).setFill(); path.fill() }
        let border = selected ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.55)
        border.setStroke(); path.lineWidth = selected ? 2 : 1; path.stroke()
        if selected {
            let check = NSBezierPath(); check.lineWidth = 1.8; check.lineCapStyle = .round; check.lineJoinStyle = .round
            check.move(to: NSPoint(x: bounds.midX - 4, y: bounds.midY)); check.line(to: NSPoint(x: bounds.midX - 1, y: bounds.midY - 3)); check.line(to: NSPoint(x: bounds.midX + 5, y: bounds.midY + 4))
            NSColor.white.setStroke(); check.stroke()
        }
    }
}
