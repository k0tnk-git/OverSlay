import AppKit
import OverSlayCore

final class MouseKeyPickerWindow: NSWindow, NSWindowDelegate {
    private let onPick: (KeyAction, String) -> Void
    private let onDrag: ((KeyAction, String, NSPoint) -> Void)?
    private let maximumBindings: Int
    private var bindings: [(binding: KeyBinding, label: String)] = []
    private var modifiers: NSEvent.ModifierFlags = []
    private var mode: CombinationMode = .simultaneous
    private let selectedLabel = NSTextField(labelWithString: L10n.text("Ничего не выбрано"))
    private let modePopup = NSPopUpButton()
    private var modifierButtons: [(flag: NSEvent.ModifierFlags, button: NSButton)] = []

    private var language: KeyboardLanguage
    private var keyButtons: [UInt16: [NSButton]] = [:]

    init(title: String = L10n.text("Добавить кнопку"), language: KeyboardLanguage, maximumBindings: Int = 16, onPick: @escaping (KeyAction, String) -> Void, onDrag: ((KeyAction, String, NSPoint) -> Void)? = nil, onCancel: @escaping () -> Void) {
        self.language = language
        self.maximumBindings = min(max(maximumBindings, 1), 16)
        self.onPick = onPick
        self.onDrag = onDrag
        self.onCancel = onCancel
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.title = title
        isReleasedWhenClosed = false
        delegate = self
        buildContent()
    }

    private let onCancel: () -> Void

    func start() {
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        cancelPlacement()
        onCancel()
    }

    func cancelPlacement() {
        keyButtons.values.flatMap { $0 }.forEach { ($0 as? PickerKeyButton)?.cancelPointerInteraction() }
    }

    func updateLanguage(_ language: KeyboardLanguage) {
        self.language = language
        for (keyCode, buttons) in keyButtons {
            for button in buttons {
                button.title = language.label(for: keyCode)
                button.toolTip = language.tooltip
            }
        }
        bindings = bindings.map { ($0.binding, displayName(for: $0.binding)) }
        refreshSelection()
    }

    private func buildContent() {
        guard let contentView else { return }
        let instruction = NSTextField(wrappingLabelWithString: L10n.text("Кликай клавиши мышью или зажми и перетащи клавишу наружу прямо на оверлей. Модификаторы применяются к следующей выбранной клавише. Для W+A выбери обе клавиши по очереди."))
        instruction.alignment = .center

        let modifiersStack = NSStackView()
        modifiersStack.orientation = .horizontal
        modifiersStack.spacing = 6
        for (title, flag) in [("⌘", NSEvent.ModifierFlags.command), ("⌥", .option), ("⌃", .control), ("⇧", .shift)] {
            let button = NSButton(title: title, target: self, action: #selector(modifierClicked(_:)))
            button.setButtonType(.pushOnPushOff)
            button.tag = modifierTag(flag)
            button.toolTip = L10n.format("Modifier %@", title)
            modifierButtons.append((flag: flag, button: button))
            modifiersStack.addArrangedSubview(button)
        }

        let rows: [[UInt16]] = [
            [53, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111],
            [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 51],
            [48, 12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
            [57, 0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 36],
            [56, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44, 56],
            [59, 58, 55, 49, 123, 126, 125, 124, 115, 119, 117],
            [50, 116, 121, 105, 107, 113, 106, 64, 79, 80, 90],
            [82, 83, 84, 85, 86, 87, 88, 89, 91, 92],
            [65, 69, 78, 67, 75, 81, 76, 71, 60, 62, 61, 54]
        ]

        let keyboardStack = NSStackView()
        keyboardStack.orientation = .vertical
        keyboardStack.spacing = 5
        keyboardStack.alignment = .centerX
        for row in rows {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 4
            for keyCode in row {
                let label = language.label(for: keyCode)
                let button = PickerKeyButton(title: label)
                button.tag = Int(keyCode)
                keyButtons[keyCode, default: []].append(button)
                button.toolTip = language.tooltip
                button.onTap = { [weak self, weak button] in if let button { self?.keyClicked(button) } }
                button.onDrag = { [weak self, weak button] point in
                    guard let self, self.isVisible, let button else { return }
                    self.dragKey(button, at: point)
                }
                button.dragEnabled = supportsDrag
                button.setContentHuggingPriority(.required, for: .horizontal)
                button.widthAnchor.constraint(greaterThanOrEqualToConstant: label.count > 3 ? 58 : 38).isActive = true
                button.heightAnchor.constraint(equalToConstant: 30).isActive = true
                rowStack.addArrangedSubview(button)
            }
            keyboardStack.addArrangedSubview(rowStack)
        }

        selectedLabel.alignment = .center
        selectedLabel.lineBreakMode = .byTruncatingMiddle
        selectedLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        modePopup.addItems(withTitles: [L10n.text("Одновременно"), L10n.text("Последовательно")])
        modePopup.target = self
        modePopup.action = #selector(modeChanged(_:))

        let clear = NSButton(title: L10n.text("Очистить"), target: self, action: #selector(clearSelection))
        let cancel = NSButton(title: L10n.text("Отмена"), target: self, action: #selector(cancelPicker))
        let apply = NSButton(title: L10n.text("Добавить"), target: self, action: #selector(applyPicker))
        apply.keyEquivalent = "\r"

        let remove = NSButton(title: L10n.text("Убрать последнюю"), target: self, action: #selector(removeLast))
        let footer = NSStackView(views: [modePopup, remove, clear, cancel, apply])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10

        let stack = NSStackView(views: [instruction, modifiersStack, keyboardStack, selectedLabel, footer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            instruction.widthAnchor.constraint(equalTo: stack.widthAnchor),
            selectedLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    @objc private func modifierClicked(_ sender: NSButton) {
        guard let flag = modifierButtons.first(where: { $0.button === sender })?.flag else { return }
        if modifiers.contains(flag) { modifiers.remove(flag) } else { modifiers.insert(flag) }
        sender.state = modifiers.contains(flag) ? .on : .off
    }

    @objc private func keyClicked(_ sender: NSButton) {
        let binding = KeyBinding(keyCode: UInt16(sender.tag), modifiers: UInt64(modifiers.rawValue))
        guard bindings.count < maximumBindings else { return }
        guard mode == .sequential || !bindings.contains(where: { $0.binding == binding }) else { return }
        bindings.append((binding, displayName(for: binding)))
        modifiers = []
        modifierButtons.forEach { $0.button.state = .off }
        refreshSelection()
    }

    private func dragKey(_ sender: NSButton, at point: NSPoint) {
        let binding = KeyBinding(keyCode: UInt16(sender.tag), modifiers: UInt64(modifiers.rawValue))
        let label = displayName(for: binding)
        onDrag?(KeyAction(binding), label, point)
        close()
    }

    fileprivate var supportsDrag: Bool { onDrag != nil }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        mode = sender.indexOfSelectedItem == 1 ? .sequential : .simultaneous
    }

    @objc private func clearSelection() {
        bindings.removeAll()
        refreshSelection()
    }

    @objc private func removeLast() {
        if !bindings.isEmpty { bindings.removeLast() }
        refreshSelection()
    }

    @objc private func cancelPicker() { close() }

    @objc private func applyPicker() {
        guard !bindings.isEmpty else { return }
        let action = KeyAction(bindings: bindings.map { $0.binding }, combinationMode: mode)
        onPick(action, bindings.map { $0.label }.joined(separator: " + "))
        close()
    }

    private func refreshSelection() {
        selectedLabel.stringValue = bindings.isEmpty ? L10n.format("Nothing selected (up to %@ keys)", String(maximumBindings)) : L10n.format("%@/%@: ", String(bindings.count), String(maximumBindings)) + bindings.map { $0.label }.joined(separator: " + ")
    }

    private func modifierTag(_ flag: NSEvent.ModifierFlags) -> Int { Int(flag.rawValue & 0x7FFF) }

    private func displayName(for binding: KeyBinding) -> String {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(binding.modifiers))
        let prefix = [
            modifiers.contains(.command) ? "⌘" : nil,
            modifiers.contains(.option) ? "⌥" : nil,
            modifiers.contains(.control) ? "⌃" : nil,
            modifiers.contains(.shift) ? "⇧" : nil
        ].compactMap { $0 }.joined()
        return prefix + language.label(for: binding.keyCode)
    }
}

private final class PickerKeyButton: NSButton {
    var onTap: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var dragEnabled = false
    private var downPoint: NSPoint?
    private var didDrag = false
    private var cancelledGesture = false
    private var preview: NSPanel?
    private var escapeMonitor: Any?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        target = nil
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        cleanupPointerInteraction()
        downPoint = event.locationInWindow
        didDrag = false
        cancelledGesture = false
        guard dragEnabled else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self else { return event }
            self.cancelPointerInteraction()
            return nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragEnabled, let downPoint else { return }
        let current = event.locationInWindow
        let distance = hypot(current.x - downPoint.x, current.y - downPoint.y)
        if !didDrag {
            guard distance >= 5 else { return }
            didDrag = true
            showPreview(at: event.locationInWindow)
        }
        movePreview(to: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        guard downPoint != nil, !cancelledGesture else {
            cleanupPointerInteraction()
            return
        }
        var placement: NSPoint?
        if didDrag {
            let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
            if let window, window.isVisible, !window.frame.contains(screenPoint),
               NSScreen.screens.contains(where: { $0.frame.contains(screenPoint) }) {
                placement = screenPoint
            }
        } else {
            onTap?()
        }
        cleanupPointerInteraction()
        if let placement { onDrag?(placement) }
    }

    fileprivate func cancelPointerInteraction() {
        cancelledGesture = true
        cleanupPointerInteraction()
    }

    deinit {
        removeEscapeMonitor()
        preview?.orderOut(nil)
    }

    private func cleanupPointerInteraction() {
        hidePreview()
        removeEscapeMonitor()
        downPoint = nil
        didDrag = false
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    private func showPreview(at point: NSPoint) {
        guard let window else { return }
        let panel = preview ?? makePreviewPanel()
        preview = panel
        let screenPoint = window.convertPoint(toScreen: point)
        panel.setFrameOrigin(NSPoint(x: screenPoint.x + 12, y: screenPoint.y - 18))
        panel.orderFrontRegardless()
    }

    private func movePreview(to point: NSPoint) {
        guard let window, let preview else { return }
        let screenPoint = window.convertPoint(toScreen: point)
        preview.setFrameOrigin(NSPoint(x: screenPoint.x + 12, y: screenPoint.y - 18))
    }

    private func hidePreview() {
        preview?.orderOut(nil)
        preview = nil
    }

    private func makePreviewPanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 104, height: 34),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = OverlayWindowLevel.service
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.contentView?.layer?.cornerRadius = 7
        let label = NSTextField(labelWithString: title)
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.frame = panel.contentView?.bounds ?? .zero
        label.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(label)
        return panel
    }
}
