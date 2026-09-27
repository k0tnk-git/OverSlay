import AppKit
import OverSlayCore

final class WidgetPanel: NSPanel {
    let widgetID: UUID
    private let widgetView: WidgetView
    var onEditBegan: (NSRect, ResizeHandle?) -> Void {
        get { widgetView.onEditBegan }
        set { widgetView.onEditBegan = newValue }
    }
    var onEditCancelled: () -> Void {
        get { widgetView.onEditCancelled }
        set { widgetView.onEditCancelled = newValue }
    }

    init(
        config: WidgetConfig,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onGeometryChanged: @escaping (NSRect, Bool) -> Void,
        onGeometryCommitted: @escaping (NSRect, Bool) -> Void,
        onDelete: @escaping () -> Void,
        onEditBinding: @escaping () -> Void = {},
        onProperties: @escaping () -> Void = {},
        onToggleMode: @escaping () -> Void = {},
        onToggleCombinationMode: @escaping () -> Void = {},
        onSelectionChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        widgetID = config.id
        widgetView = WidgetView(
            config: config,
            onPress: onPress,
            onRelease: onRelease,
            onGeometryChanged: onGeometryChanged,
            onGeometryCommitted: onGeometryCommitted,
            onDelete: onDelete,
            onEditBinding: onEditBinding,
            onProperties: onProperties,
            onToggleMode: onToggleMode,
            onToggleCombinationMode: onToggleCombinationMode,
            onSelectionChanged: onSelectionChanged
        )
        let frame = NSRect(x: config.geometry.x, y: config.geometry.y, width: config.geometry.width, height: config.geometry.height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = OverlayWindowLevel.base
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = widgetView
    }

    func setSnapFeedback(_ edges: OverlayResizeEdges) { widgetView.snappedEdges = edges; widgetView.needsDisplay = true }
    override func orderOut(_ sender: Any?) {
        widgetView.cancelTracking()
        EditorPulseClock.unregister(widgetView)
        super.orderOut(sender)
    }
    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        if widgetView.isEditing { EditorPulseClock.register(widgetView) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func setActive(_ active: Bool) { widgetView.setActive(active) }
    func setMacroProgress(_ progress: Double, running: Bool) { widgetView.setMacroProgress(progress, running: running) }
    func setLabel(_ label: String) { widgetView.setLabel(label) }

    func showMacroBusy() {
        widgetView.toolTip = L10n.text("Сначала остановите текущий макрос")
        NSAccessibility.post(element: widgetView, notification: .announcementRequested,
                             userInfo: [.announcement: L10n.text("Сначала остановите текущий макрос")])
        let original = widgetView.label
        widgetView.setLabel(L10n.text("Остановите макрос"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.widgetView.setLabel(original) }
    }
    func setTooltip(_ tooltip: String) { widgetView.toolTip = tooltip }
    func setEditing(_ editing: Bool) {
        if !editing { widgetView.cancelTracking() }
        widgetView.isEditing = editing
        if editing { EditorPulseClock.register(widgetView) } else { EditorPulseClock.unregister(widgetView) }
        widgetView.needsDisplay = true; widgetView.resetCursorRects()
    }
    func setSelected(_ selected: Bool) { widgetView.isSelected = selected; widgetView.needsDisplay = true }
    func cancelTracking() { widgetView.cancelTracking() }
    func moveBy(_ delta: NSPoint) {
        setFrame(NSRect(x: frame.origin.x + delta.x, y: frame.origin.y + delta.y, width: frame.width, height: frame.height), display: true)
    }
    func update(config: WidgetConfig) {
        widgetView.update(config: config)
        let frame = NSRect(x: config.geometry.x, y: config.geometry.y, width: config.geometry.width, height: config.geometry.height)
        if frame != self.frame { setFrame(frame, display: true) }
    }
}

private final class WidgetView: NSView {
    fileprivate var label: String
    private var opacity: CGFloat
    private var mode: TriggerMode
    private var combinationMode: CombinationMode
    private var bindingCount: Int
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onGeometryChanged: (NSRect, Bool) -> Void
    private let onGeometryCommitted: (NSRect, Bool) -> Void
    private let onDelete: () -> Void
    private let onEditBinding: () -> Void
    private let onProperties: () -> Void
    private let onToggleMode: () -> Void
    private let onToggleCombinationMode: () -> Void
    private let onSelectionChanged: (Bool) -> Void
    var isActive = false
    var isEditing = false
    var isSelected = false
    var onEditBegan: (NSRect, ResizeHandle?) -> Void = { _, _ in }
    var onEditCancelled: () -> Void = {}
    private var hoveredHandle: ResizeHandle?
    var snappedEdges = OverlayResizeEdges()
    private var dragStart: NSPoint?
    private var frameStart: NSRect?
    private var isResizing = false
    private var resizeHandle: ResizeHandle?
    private var menuTarget: MenuTarget?
    private var inputTracking = false
    private var activeStartedAt: Date?
    private var activeTimer: Timer?
    private var activeProgress: CGFloat = 1
    private var isMacro = false
    private var buttonAppearance: ButtonAppearance

    init(
        config: WidgetConfig,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onGeometryChanged: @escaping (NSRect, Bool) -> Void,
        onGeometryCommitted: @escaping (NSRect, Bool) -> Void,
        onDelete: @escaping () -> Void,
        onEditBinding: @escaping () -> Void,
        onProperties: @escaping () -> Void,
        onToggleMode: @escaping () -> Void,
        onToggleCombinationMode: @escaping () -> Void,
        onSelectionChanged: @escaping (Bool) -> Void
    ) {
        self.label = config.label
        self.isMacro = config.macro != nil
        self.opacity = CGFloat(min(max(config.opacity, 0.1), 1))
        self.mode = config.mode
        self.timedDurationSeconds = config.timedDurationSeconds
        self.combinationMode = config.action.combinationMode
        self.bindingCount = config.action.bindings.count
        self.buttonAppearance = config.appearance
        self.onPress = onPress
        self.onRelease = onRelease
        self.onGeometryChanged = onGeometryChanged
        self.onGeometryCommitted = onGeometryCommitted
        self.onDelete = onDelete
        self.onEditBinding = onEditBinding
        self.onProperties = onProperties
        self.onToggleMode = onToggleMode
        self.onToggleCombinationMode = onToggleCombinationMode
        self.onSelectionChanged = onSelectionChanged
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { activeTimer?.invalidate(); EditorPulseClock.unregister(self) }

    func cancelTracking() {
        let wasEditing = dragStart != nil
        inputTracking = false; dragStart = nil; frameStart = nil; resizeHandle = nil; isResizing = false
        hoveredHandle = nil
        if wasEditing { onEditCancelled() }
        if isEditing { EditorPulseClock.register(self) }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseExited(with event: NSEvent) {
        if isMacro { inputTracking = false }
        hoveredHandle = nil; needsDisplay = true
    }

    func setActive(_ active: Bool) {
        isActive = active
        activeTimer?.invalidate(); activeTimer = nil
        if active && mode == .timedToggle {
            activeStartedAt = Date(); activeProgress = 1
            activeTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
                guard let self, let started = self.activeStartedAt else { return }
                self.activeProgress = max(0, 1 - CGFloat(Date().timeIntervalSince(started) / max(self.timedDurationSeconds, 0.1)))
                self.needsDisplay = true
                if self.activeProgress <= 0 { self.activeTimer?.invalidate(); self.activeTimer = nil }
            }
        } else { activeStartedAt = nil; activeProgress = 1 }
        needsDisplay = true
    }

    func setLabel(_ label: String) {
        self.label = label
        needsDisplay = true
    }

    func setMacroProgress(_ progress: Double, running: Bool) {
        guard isMacro else { return }
        isActive = running
        setAccessibilityLabel(label)
        setAccessibilityValue(running ? L10n.text("Исполняется. Нажмите для остановки.") : L10n.text("Готово"))
        activeProgress = CGFloat(min(max(progress, 0), 1))
        activeTimer?.invalidate()
        activeTimer = nil
        needsDisplay = true
    }

    func update(config: WidgetConfig) {
        label = config.label
        isMacro = config.macro != nil
        opacity = CGFloat(min(max(config.opacity, 0.1), 1))
        mode = config.mode
        timedDurationSeconds = config.timedDurationSeconds
        combinationMode = config.action.combinationMode
        bindingCount = config.action.bindings.count
        buttonAppearance = config.appearance
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        ButtonAppearanceRenderer.draw(buttonAppearance, in: rect, path: path, opacity: opacity)
        if isActive {
            NSColor.systemBlue.withAlphaComponent(opacity * (isMacro ? 0.11 : 0.07)).setFill(); path.fill()
            let activePath = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
            NSColor.systemBlue.withAlphaComponent(0.95).setStroke(); activePath.lineWidth = 2; activePath.stroke()
            let stateOutline = NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 8, yRadius: 8)
            NSColor.white.withAlphaComponent(0.9).setStroke(); stateOutline.lineWidth = 1; stateOutline.stroke()
            if mode == .timedToggle || isMacro {
                NSColor.black.withAlphaComponent(0.55).setFill(); NSBezierPath(roundedRect: NSRect(x: rect.minX + 8, y: rect.maxY - 7, width: rect.width - 16, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
                NSColor.systemBlue.setFill(); NSBezierPath(roundedRect: NSRect(x: rect.minX + 8, y: rect.maxY - 7, width: (rect.width - 16) * activeProgress, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
        if !isEditing {
            NSColor.white.withAlphaComponent(0.72).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(22, max(13, bounds.height * 0.28)), weight: .semibold),
            .foregroundColor: NSColor.white,
            .shadow: { let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.9); shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width: 0, height: -1); return shadow }(),
            .paragraphStyle: paragraph
        ]
        let size = label.size(withAttributes: attributes)
        label.draw(in: NSRect(x: 8, y: bounds.midY - size.height / 2,
                              width: max(0, bounds.width - 16), height: size.height), withAttributes: attributes)
        if !isEditing, let modeLabel = modeHint {
            if bounds.height >= 48 {
                let font = NSFont.systemFont(ofSize: 9, weight: .regular)
                let measured = modeLabel.size(withAttributes: [.font: font])
                let labelWidth = min(measured.width, max(10, bounds.width - 12))
                let pill = NSBezierPath(roundedRect: NSRect(x: bounds.midX - labelWidth / 2 - 5, y: 3, width: labelWidth + 10, height: 16), xRadius: 5, yRadius: 5)
                NSColor.black.withAlphaComponent(0.58).setFill(); pill.fill()
                let modeAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.white,
                    .shadow: { let shadow = NSShadow(); shadow.shadowColor = .black; shadow.shadowBlurRadius = 1; return shadow }(),
                    .paragraphStyle: { let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byTruncatingTail; return style }()
                ]
                modeLabel.draw(in: NSRect(x: bounds.midX - labelWidth / 2, y: 5, width: labelWidth, height: 12), withAttributes: modeAttributes)
            }
        }
        if isEditing { EditorChrome.draw(in: bounds, selected: isSelected, phase: dragStart == nil ? EditorPulseClock.phase : 0, hovered: hoveredHandle, snapped: snappedEdges) }
    }

    private var modeHint: String? {
        if isMacro { return isActive ? (bounds.width < 88 ? "■" : L10n.text("■ Стоп")) : nil }
        switch mode {
        case .hold: return isActive ? (bounds.width < 82 || bounds.height < 48 ? "●" : L10n.text("● Удерживается")) : nil
        case .toggle: return isActive ? (bounds.width < 88 ? "●" : L10n.text("ВКЛ · Toggle")) : "Toggle"
        case .timedToggle:
            let value = timedDurationSeconds.rounded() == timedDurationSeconds ? String(Int(timedDurationSeconds)) : String(format: "%.1f", timedDurationSeconds)
            return isActive ? (bounds.width < 88 ? "●" : L10n.format("ON · %@s", String(value))) : (bounds.width < 88 ? L10n.format("T %@s", String(value)) : L10n.format("Toggle %@s", String(value)))
        }
    }
    private var timedDurationSeconds: Double = 5

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

    override func mouseDown(with event: NSEvent) {
        guard isEditing else { inputTracking = true; if !isMacro { onPress() }; return }
        onSelectionChanged(event.modifierFlags.contains(.shift))
        dragStart = NSEvent.mouseLocation
        frameStart = window?.frame
        resizeHandle = ResizeHandle.hit(event.locationInWindow, in: bounds)
        isResizing = resizeHandle != nil
        EditorPulseClock.unregister(self)
        if let frameStart { onEditBegan(frameStart, resizeHandle) }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isEditing else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: isSelected ? L10n.text("Убрать из выделения") : L10n.text("Добавить в выделение"), action: #selector(MenuTarget.select), keyEquivalent: "")
        menu.addItem(withTitle: isMacro ? L10n.text("Изменить макрос…") : L10n.text("Изменить клавишу…"), action: #selector(MenuTarget.edit), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("Свойства кнопки…"), action: #selector(MenuTarget.properties), keyEquivalent: "")
        if !isMacro {
          if bindingCount > 1 {
            if combinationMode == .simultaneous {
                menu.addItem(withTitle: L10n.text("Использовать последовательную комбинацию"), action: #selector(MenuTarget.toggleCombination), keyEquivalent: "")
            } else {
                menu.addItem(withTitle: L10n.text("Использовать одновременную комбинацию"), action: #selector(MenuTarget.toggleCombination), keyEquivalent: "")
            }
          }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("Удалить кнопку"), action: #selector(MenuTarget.delete), keyEquivalent: "")
        let target = MenuTarget(edit: onEditBinding, properties: onProperties, toggle: onToggleMode, toggleCombination: onToggleCombinationMode, delete: onDelete, select: { [weak self] in self?.onSelectionChanged(true) })
        menu.items.forEach { $0.target = target }
        menuTarget = target
        menu.popUp(positioning: nil, at: event.locationInWindow, in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing, let dragStart, let frameStart else { return }
        let position = NSEvent.mouseLocation
        let delta = NSPoint(x: position.x - dragStart.x, y: position.y - dragStart.y)
        let original = OverlayRect(frameStart)
        let frame = (resizeHandle?.resized(original, dx: delta.x, dy: delta.y)
                     ?? original.translated(x: delta.x, y: delta.y)).nsRect
        onGeometryChanged(frame, isResizing)
    }

    override func mouseUp(with event: NSEvent) {
        if isEditing {
            guard dragStart != nil else { return }
            let frame = window?.frame
            let resizing = isResizing
            dragStart = nil
            frameStart = nil
            isResizing = false
            resizeHandle = nil
            EditorPulseClock.register(self)
            if let frame { onGeometryCommitted(frame, resizing) }
            return
        }
        guard inputTracking else { return }
        inputTracking = false
        if isMacro {
            if bounds.contains(convert(event.locationInWindow, from: nil)) { onRelease() }
            return
        }
        onRelease()
    }

    private final class MenuTarget: NSObject {
        let editAction: () -> Void
        let propertiesAction: () -> Void
        let toggleAction: () -> Void
        let toggleCombinationAction: () -> Void
        let deleteAction: () -> Void
        let selectAction: () -> Void

        init(edit: @escaping () -> Void, properties: @escaping () -> Void, toggle: @escaping () -> Void, toggleCombination: @escaping () -> Void, delete: @escaping () -> Void, select: @escaping () -> Void) {
            editAction = edit
            propertiesAction = properties
            toggleAction = toggle
            toggleCombinationAction = toggleCombination
            deleteAction = delete
            selectAction = select
        }

        @objc func edit() { editAction() }
        @objc func properties() { propertiesAction() }
        @objc func toggle() { toggleAction() }
        @objc func toggleCombination() { toggleCombinationAction() }
        @objc func delete() { deleteAction() }
        @objc func select() { selectAction() }
    }
}
