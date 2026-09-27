import AppKit
import OverSlayCore

final class MouseKeyPickerWindow: NSWindow, NSWindowDelegate {
    private let onPick: (KeyAction, String) -> Void
    private let onDrag: (KeyAction, String, NSPoint) -> Void
    private let maximumBindings: Int
    private var bindings: [(binding: KeyBinding, label: String)] = []
    private var modifiers: NSEvent.ModifierFlags = []
    private var mode: CombinationMode = .simultaneous
    private let selectedLabel = NSTextField(labelWithString: L10n.text("Ничего не выбрано"))
    private let modePopup = NSPopUpButton()
    private var modifierButtons: [(flag: NSEvent.ModifierFlags, button: NSButton)] = []

    private var language: KeyboardLanguage
    private var keyButtons: [UInt16: [NSButton]] = [:]

    init(title: String = L10n.text("Добавить кнопку"), language: KeyboardLanguage, maximumBindings: Int = 16, onPick: @escaping (KeyAction, String) -> Void, onDrag: @escaping (KeyAction, String, NSPoint) -> Void = { _, _, _ in }, onCancel: @escaping () -> Void) {
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

    func windowWillClose(_ notification: Notification) { onCancel() }

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
                    guard let self, let button else { return }
                    self.dragKey(button, at: point)
                }
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
        onDrag(KeyAction(binding), label, point)
        close()
    }

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

private final class PickerKeyButton: NSButton, NSDraggingSource {
    var onTap: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    private var downPoint: NSPoint?
    private var didDrag = false

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        target = nil
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow; didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint, !didDrag else { return }
        let current = event.locationInWindow
        let distance = hypot(current.x - downPoint.x, current.y - downPoint.y)
        guard distance >= 5 else { return }
        didDrag = true
        let item = NSPasteboardItem()
        item.setString(title, forType: .string)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: NSImage(size: NSSize(width: 70, height: 30)))
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag { onTap?() }
        downPoint = nil; didDrag = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor draggingContext: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { onDrag?(screenPoint) }
}
