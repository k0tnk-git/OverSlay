import AppKit
import OverSlayCore

enum RadialSettingSlot: Equatable { case rightMouse, scrollUp, scrollDown }

final class RadialPropertiesWindow: NSPanel, NSWindowDelegate {
    private var config: RadialWidgetConfig
    private let analogAvailable: Bool
    private let sideInputAvailable: Bool
    private let onSave: (RadialWidgetConfig) -> Void
    private let onCancel: () -> Void
    private var language: KeyboardLanguage
    private var finished = false
    private var picker: MouseKeyPickerWindow?
    private let mode = NSPopUpButton()
    private let right = NSPopUpButton()
    private let up = NSPopUpButton()
    private let down = NSPopUpButton()
    private let opacity = NSSlider(value: 0.72, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let opacityLabel = NSTextField(labelWithString: "72%")

    init(config: RadialWidgetConfig, analogAvailable: Bool, sideInputAvailable: Bool, language: KeyboardLanguage, onSave: @escaping (RadialWidgetConfig) -> Void, onCancel: @escaping () -> Void) {
        self.config = config
        self.analogAvailable = analogAvailable
        self.sideInputAvailable = sideInputAvailable
        self.language = language
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = L10n.text("Свойства джойстика")
        isReleasedWhenClosed = false
        delegate = self
        build()
    }

    func start() { center(); makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func updateLanguage(_ language: KeyboardLanguage) {
        self.language = language
        picker?.updateLanguage(language)
    }

    func windowWillClose(_ notification: Notification) {
        picker?.close(); picker = nil
        if !finished { finished = true; onCancel() }
    }

    private func build() {
        guard let contentView else { return }
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18), stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)])

        mode.addItems(withTitles: [L10n.text("Клавиатура (WASD)"), L10n.text("Джойстик (Analog)")]); mode.selectItem(at: config.inputMode == .digital ? 0 : 1)
        mode.item(at: 1)?.isEnabled = analogAvailable || config.inputMode == .analog
        if !analogAvailable { mode.toolTip = L10n.text("Виртуальный HID-контроллер недоступен в этой сборке или системе") }
        stack.addArrangedSubview(row(L10n.text("Режим ввода"), mode))

        setup(right, action: config.rightMouseAction, allowsSprint: true, slot: .rightMouse)
        setup(up, action: config.scrollUpAction, allowsSprint: false, slot: .scrollUp)
        setup(down, action: config.scrollDownAction, allowsSprint: false, slot: .scrollDown)
        for popup in [right, up, down] {
            popup.isEnabled = sideInputAvailable
            if !sideInputAvailable { popup.toolTip = L10n.text("Глобальный event tap недоступен; выдайте приложению Accessibility-разрешение") }
        }
        stack.addArrangedSubview(row(L10n.text("ПКМ во время движения"), right))
        stack.addArrangedSubview(row(L10n.text("Колесо вверх"), up))
        stack.addArrangedSubview(row(L10n.text("Колесо вниз"), down))

        opacity.doubleValue = config.opacity; opacity.widthAnchor.constraint(equalToConstant: 220).isActive = true
        opacity.target = self; opacity.action = #selector(opacityChanged)
        stack.addArrangedSubview(row(L10n.text("Прозрачность"), opacity, value: opacityLabel))

        let buttons = NSStackView(); buttons.orientation = .horizontal; buttons.spacing = 8
        let cancel = NSButton(title: L10n.text("Отмена"), target: self, action: #selector(cancelClicked))
        let save = NSButton(title: L10n.text("Сохранить"), target: self, action: #selector(saveClicked)); save.keyEquivalent = "\r"
        buttons.addArrangedSubview(NSView()); buttons.addArrangedSubview(cancel); buttons.addArrangedSubview(save); stack.addArrangedSubview(buttons)
        updateOpacityLabel()
    }

    private func row(_ title: String, _ control: NSView, value: NSTextField? = nil) -> NSStackView {
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 8
        let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 180).isActive = true
        row.addArrangedSubview(label); row.addArrangedSubview(control); if let value { row.addArrangedSubview(value) }; return row
    }

    private func setup(_ popup: NSPopUpButton, action: Any, allowsSprint: Bool, slot: RadialSettingSlot) {
        popup.addItems(withTitles: allowsSprint ? [L10n.text("Передавать игре"), L10n.text("Спринт (Shift)"), L10n.text("Своя клавиша…"), L10n.text("Отключить")] : [L10n.text("Передавать игре"), L10n.text("Своя клавиша…"), L10n.text("Отключить")])
        popup.selectItem(at: index(action, allowsSprint: allowsSprint)); popup.tag = slotTag(slot); popup.target = self; popup.action = #selector(actionChanged(_:))
        popup.widthAnchor.constraint(equalToConstant: 220).isActive = true
    }

    private func index(_ action: Any, allowsSprint: Bool) -> Int {
        if allowsSprint, let action = action as? SideInputAction {
            switch action { case .passthrough: return 0; case .sprint: return 1; case .custom: return 2; case .none: return 3 }
        }
        if let action = action as? ScrollInputAction { switch action { case .passthrough: return 0; case .custom: return 1; case .none: return 2 } }
        return 0
    }

    private func slotTag(_ slot: RadialSettingSlot) -> Int { switch slot { case .rightMouse: return 0; case .scrollUp: return 1; case .scrollDown: return 2 } }
    private func slot(for tag: Int) -> RadialSettingSlot { tag == 0 ? .rightMouse : (tag == 1 ? .scrollUp : .scrollDown) }

    @objc private func actionChanged(_ sender: NSPopUpButton) {
        let slot = slot(for: sender.tag)
        let isCustom = sender.indexOfSelectedItem == (slot == .rightMouse ? 2 : 1)
        guard isCustom else { return }
        let previous = sender.indexOfSelectedItem
        let picker = MouseKeyPickerWindow(title: L10n.text("Выбери клавишу"), language: language, maximumBindings: 1, onPick: { [weak self] action, _ in
            guard let self else { return }; self.picker = nil
            let binding = action.bindings[0]
            switch slot {
            case .rightMouse: self.config.rightMouseAction = .custom(binding)
            case .scrollUp: self.config.scrollUpAction = .custom(binding)
            case .scrollDown: self.config.scrollDownAction = .custom(binding)
            }
            sender.selectItem(at: previous)
        }, onCancel: { [weak self] in self?.picker = nil })
        self.picker = picker; picker.start()
    }

    @objc private func opacityChanged() { updateOpacityLabel() }
    private func updateOpacityLabel() { opacityLabel.stringValue = "\(Int((opacity.doubleValue * 100).rounded()))%" }
    @objc private func cancelClicked() { close() }
    @objc private func saveClicked() {
        config.inputMode = mode.indexOfSelectedItem == 1 ? .analog : .digital
        config.opacity = opacity.doubleValue
        if right.indexOfSelectedItem != 2 { config.rightMouseAction = right.indexOfSelectedItem == 1 ? .sprint : (right.indexOfSelectedItem == 3 ? .none : .passthrough) }
        if up.indexOfSelectedItem != 1 { config.scrollUpAction = up.indexOfSelectedItem == 2 ? .none : .passthrough }
        if down.indexOfSelectedItem != 1 { config.scrollDownAction = down.indexOfSelectedItem == 2 ? .none : .passthrough }
        finished = true; onSave(config); close()
    }
}
