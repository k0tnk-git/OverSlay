import AppKit
import OverSlayCore

final class RadialPanel: NSPanel {
    private let radialView: RadialView
    var onEditBegan: (NSRect, ResizeHandle?) -> Void {
        get { radialView.onEditBegan }
        set { radialView.onEditBegan = newValue }
    }
    var onEditCancelled: () -> Void {
        get { radialView.onEditCancelled }
        set { radialView.onEditCancelled = newValue }
    }

    init(
        frame: NSRect,
        opacity: Double = 0.72,
        inputMode: RadialInputMode = .digital,
        onBegin: @escaping () -> Bool,
        onMove: @escaping (RadialVector) -> Void,
        onEnd: @escaping () -> Void,
        onGeometryChanged: @escaping (NSRect, Bool, ResizeHandle?) -> Void = { _, _, _ in },
        onGeometryCommitted: @escaping (NSRect, Bool, ResizeHandle?) -> Void = { _, _, _ in },
        onProperties: @escaping () -> Void = {}
    ) {
        radialView = RadialView(opacity: opacity, inputMode: inputMode, onBegin: onBegin, onMove: onMove, onEnd: onEnd, onGeometryChanged: onGeometryChanged, onGeometryCommitted: onGeometryCommitted, onProperties: onProperties)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = OverlayWindowLevel.base
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = radialView
    }

    func setSnapFeedback(_ edges: OverlayResizeEdges) { radialView.snappedEdges = edges; radialView.needsDisplay = true }
    override func orderOut(_ sender: Any?) {
        radialView.cancelTracking()
        EditorPulseClock.unregister(radialView)
        super.orderOut(sender)
    }
    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        if radialView.isEditing { EditorPulseClock.register(radialView) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func setDirection(_ direction: RadialDirection?) { radialView.direction = direction; radialView.needsDisplay = true }
    func cancelTracking() { radialView.cancelTracking() }
    func finishMouseTracking() { radialView.finishMouseTracking() }
    var isTracking: Bool { radialView.isTracking }
    func setAnalogAvailable(_ available: Bool) { radialView.analogAvailable = available; radialView.needsDisplay = true }
    func setEditing(_ editing: Bool) { radialView.setEditing(editing) }
    func applyEditorFrame(_ frame: NSRect) { setFrame(frame, display: true) }
    func update(config: RadialWidgetConfig) {
        radialView.opacity = CGFloat(config.opacity)
        radialView.inputMode = config.inputMode
        setFrame(NSRect(x: config.geometry.x, y: config.geometry.y, width: config.geometry.width, height: config.geometry.height), display: true)
        radialView.needsDisplay = true
    }
}

private final class RadialView: NSView {
    private let onBegin: () -> Bool
    private let onMove: (RadialVector) -> Void
    private let onEnd: () -> Void
    private let onGeometryChanged: (NSRect, Bool, ResizeHandle?) -> Void
    private let onGeometryCommitted: (NSRect, Bool, ResizeHandle?) -> Void
    private let onProperties: () -> Void
    private var tracking = false
    var onEditBegan: (NSRect, ResizeHandle?) -> Void = { _, _ in }
    var onEditCancelled: () -> Void = {}
    private var hoveredHandle: ResizeHandle?
    var snappedEdges = OverlayResizeEdges()
    private var dragStart: NSPoint?
    private var frameStart: NSRect?
    private var resizingHandle: ResizeHandle?
    private var targetOffset = RadialVector(x: 0, y: 0)
    private var visualOffset = RadialVector(x: 0, y: 0)
    private var hoverCursorPushed = false
    private var dragCursorPushed = false
    private var hoverTrackingArea: NSTrackingArea?
    var isEditing = false
    var opacity: CGFloat
    var direction: RadialDirection?
    var inputMode: RadialInputMode
    var analogAvailable = false
    var isTracking: Bool { tracking }

    init(opacity: Double, inputMode: RadialInputMode, onBegin: @escaping () -> Bool, onMove: @escaping (RadialVector) -> Void, onEnd: @escaping () -> Void, onGeometryChanged: @escaping (NSRect, Bool, ResizeHandle?) -> Void, onGeometryCommitted: @escaping (NSRect, Bool, ResizeHandle?) -> Void, onProperties: @escaping () -> Void) {
        self.opacity = CGFloat(min(max(opacity, 0.1), 1))
        self.inputMode = inputMode
        self.onBegin = onBegin
        self.onMove = onMove
        self.onEnd = onEnd
        self.onGeometryChanged = onGeometryChanged
        self.onGeometryCommitted = onGeometryCommitted
        self.onProperties = onProperties
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { EditorPulseClock.unregister(self) }

    func cancelTracking() {
        let wasEditing = dragStart != nil
        let wasTracking = tracking
        tracking = false; dragStart = nil; frameStart = nil; resizingHandle = nil; direction = nil
        popDragCursorIfNeeded(); popHoverCursorIfNeeded(); targetOffset = .init(x: 0, y: 0); visualOffset = targetOffset; needsDisplay = true
        if wasEditing { onEditCancelled() }
        hoveredHandle = nil
        if isEditing { EditorPulseClock.register(self) }
        if wasTracking { onEnd() }
        if wasTracking { updateHoverCursor() }
    }

    /// Completes an ordinary mouse-up from the event monitor or this view.
    /// Unlike cancellation, this commits an editor drag and ends gameplay input.
    func finishMouseTracking() {
        if isEditing {
            guard dragStart != nil else { return }
            let frame = window?.frame
            let handle = resizingHandle
            dragStart = nil; frameStart = nil; resizingHandle = nil
            EditorPulseClock.register(self)
            if let frame { onGeometryCommitted(frame, handle != nil, handle) }
            return
        }
        guard tracking else { return }
        tracking = false
        popDragCursorIfNeeded()
        targetOffset = .init(x: 0, y: 0); visualOffset = targetOffset; direction = nil; needsDisplay = true
        onEnd()
        resetCursorRects()
        updateHoverCursor()
    }

    func setEditing(_ editing: Bool) {
        if !editing { cancelTracking() }
        isEditing = editing
        if editing { EditorPulseClock.register(self) } else { EditorPulseClock.unregister(self) }
        popHoverCursorIfNeeded()
        needsDisplay = true
        resetCursorRects()
        updateHoverCursor()
    }

    func setOffset(_ offset: RadialVector) {
        targetOffset = clamped(offset); visualOffset = targetOffset; needsDisplay = true
    }

    private func clamped(_ offset: RadialVector) -> RadialVector {
        let magnitude = hypot(offset.x, offset.y)
        guard magnitude > 1 else { return offset }
        return .init(x: offset.x / magnitude, y: offset.y / magnitude)
    }

    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.44
        let outer = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        NSColor.darkGray.withAlphaComponent(opacity).setFill()
        outer.fill()
        NSColor.white.withAlphaComponent(0.7).setStroke()
        outer.lineWidth = 1.5
        outer.stroke()

        let knobRadius: CGFloat = min(bounds.width, bounds.height) * (tracking ? 0.24 * 0.76 : 0.24) * 0.44
        let travel = max(radius - knobRadius - radius * 0.04, 0)
        let knobCenter = NSPoint(x: center.x + CGFloat(visualOffset.x) * travel, y: center.y + CGFloat(visualOffset.y) * travel)
        let knob = NSBezierPath(ovalIn: NSRect(x: knobCenter.x - knobRadius, y: knobCenter.y - knobRadius, width: knobRadius * 2, height: knobRadius * 2))
        (tracking ? NSColor.systemBlue : NSColor.white).withAlphaComponent(tracking ? 0.9 : 0.62).setFill()
        knob.fill()
        let symbol = inputMode == .digital ? "keyboard" : "gamecontroller"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: inputMode == .digital ? L10n.text("Клавиатурный режим") : L10n.text("Режим джойстика")) {
            let side = min(14, max(9, bounds.width * 0.07))
            image.draw(in: NSRect(x: center.x - side / 2, y: center.y - radius * 0.72 - side / 2, width: side, height: side), from: .zero, operation: .sourceOver, fraction: inputMode == .analog && !analogAvailable ? 0.16 : 0.3)
        }
        if isEditing {
            EditorChrome.draw(in: bounds, selected: false, phase: dragStart == nil ? EditorPulseClock.phase : 0, hovered: hoveredHandle, snapped: snappedEdges)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEditing else { return }
        addCursorRect(bounds, cursor: .openHand)
        for (handle, rect) in ResizeHandle.zones(in: bounds) { addCursorRect(rect, cursor: handle.cursor) }
    }

    override func mouseMoved(with event: NSEvent) {
        guard isEditing, dragStart == nil else { return }
        hoveredHandle = ResizeHandle.hit(convert(event.locationInWindow, from: nil), in: bounds)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        if isEditing {
            dragStart = NSEvent.mouseLocation; frameStart = window?.frame; resizingHandle = ResizeHandle.hit(event.locationInWindow, in: bounds)
            EditorPulseClock.unregister(self)
            if let frameStart { onEditBegan(frameStart, resizingHandle) }
            return
        }
        guard onBegin() else { return }
        tracking = true
        popHoverCursorIfNeeded(); NSCursor.closedHand.push(); dragCursorPushed = true
        emit(offset(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        if isEditing, let dragStart, let frameStart {
            let delta = NSPoint(x: NSEvent.mouseLocation.x - dragStart.x, y: NSEvent.mouseLocation.y - dragStart.y)
            let original = OverlayRect(frameStart)
            let frame = (resizingHandle?.resized(original, dx: delta.x, dy: delta.y, square: true)
                         ?? original.translated(x: delta.x, y: delta.y)).nsRect
            onGeometryChanged(frame, resizingHandle != nil, resizingHandle)
            return
        }
        guard tracking else { return }
        emit(offset(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        finishMouseTracking()
        if !isEditing { updateHoverCursor(at: event.locationInWindow) }
    }

    override func rightMouseDown(with event: NSEvent) {
        if tracking { return }
        guard isEditing else { return }
        let menu = NSMenu(); let item = menu.addItem(withTitle: L10n.text("Свойства джойстика…"), action: #selector(MenuTarget.properties), keyEquivalent: "")
        let target = MenuTarget(action: onProperties); item.target = target; menu.popUp(positioning: nil, at: event.locationInWindow, in: self)
    }

    override func rightMouseUp(with event: NSEvent) { }

    override func mouseEntered(with event: NSEvent) {
        guard !tracking, !isEditing, !hoverCursorPushed else { return }
        NSCursor.openHand.push(); hoverCursorPushed = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredHandle = nil; needsDisplay = true
        popHoverCursorIfNeeded()
    }

    private func popHoverCursorIfNeeded() { if hoverCursorPushed { NSCursor.pop(); hoverCursorPushed = false } }
    private func popDragCursorIfNeeded() { if dragCursorPushed { NSCursor.pop(); dragCursorPushed = false } }

    private func updateHoverCursor(at point: NSPoint? = nil) {
        popHoverCursorIfNeeded()
        guard !tracking, !isEditing, let window, window.isVisible else { return }
        let location = point ?? convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        guard bounds.contains(location) else { return }
        NSCursor.openHand.push()
        hoverCursorPushed = true
    }

    private final class MenuTarget: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func properties() { action() }
    }

    private func emit(_ offset: RadialVector) {
        let bounded = clamped(offset)
        targetOffset = bounded
        visualOffset = bounded
        needsDisplay = true
        onMove(bounded)
    }

    private func offset(for event: NSEvent) -> RadialVector {
        let point = event.locationInWindow
        let radius = Double(min(bounds.width, bounds.height)) * 0.44
        let restingKnob = Double(min(bounds.width, bounds.height)) * 0.44 * 0.24 * 0.76
        let travel = max(radius - restingKnob - radius * 0.04, 1)
        return clamped(RadialVector(x: Double(point.x - bounds.midX) / travel, y: Double(point.y - bounds.midY) / travel))
    }
}
