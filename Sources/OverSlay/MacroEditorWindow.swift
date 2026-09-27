import AppKit
import OverSlayCore

final class MacroEditorWindow: NSPanel, NSWindowDelegate {
    private let onChooseKey: (@escaping (KeyAction, String) -> Void) -> Void
    private let onSave: (String, MacroDefinition) -> Bool
    private let onCancel: () -> Void
    private let language: KeyboardLanguage
    private var steps: [MacroStep] = []
    private let nameField = MacroMouseTextField(string: L10n.text("Новая кнопка"))
    private let textField = MacroMouseTextField(string: "")
    private let waitField = MacroMouseTextField(string: "1")
    private let textIntervalField = MacroMouseTextField(string: "0.033")
    private let durationField = MacroMouseTextField(string: "0.033")
    private let offsetField = MacroMouseTextField(string: "1")
    private let kindPopup = NSPopUpButton()
    private let rows = NSStackView()
    private let gapField = MacroMouseTextField(string: "0.033")
    private var selected: Int?
    private var selectedChild: Int?
    private var rowAddresses: [(Int, Int?)] = []
    private let status = NSTextField(labelWithString: L10n.text("Добавьте действие мышью."))
    private var didFinish = false
    private weak var activeTextField: MacroMouseTextField?
    private var uppercase = false
    private let alphabet = Array("abcdefghijklmnopqrstuvwxyzабвгдеёжзийклмнопрстуфхцчшщъыьэюя0123456789 .,!?-_:;/@~#$%&*()+=[]{}<>?")
    private var keyButtons: [NSButton] = []

    init(language: KeyboardLanguage, label: String = L10n.text("Новая кнопка"), macro: MacroDefinition? = nil,
         onChooseKey: @escaping (@escaping (KeyAction, String) -> Void) -> Void,
         onSave: @escaping (String, MacroDefinition) -> Bool,
         onCancel: @escaping () -> Void = {}) {
        self.language = language
        self.onChooseKey = onChooseKey
        self.onSave = onSave
        self.onCancel = onCancel
        self.steps = macro?.steps ?? []
        super.init(contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        title = L10n.text("Кастомная кнопка")
        isReleasedWhenClosed = false
        delegate = self
        build()
        nameField.stringValue = label
        activeTextField = nameField
        nameField.onSelect = { [weak self] in self?.activeTextField = self?.nameField }
        textField.onSelect = { [weak self] in self?.activeTextField = self?.textField }
        for field in [waitField, textIntervalField, durationField, offsetField, gapField] {
            field.onSelect = { [weak self, weak field] in self?.activeTextField = field }
        }
        gapField.stringValue = String(Double(macro?.releaseGapMilliseconds ?? 33) / 1000)
        minSize = NSSize(width: 680, height: 480)
        rebuildRows()
    }

    func start() { center(); makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func windowWillClose(_ notification: Notification) {
        guard !didFinish else { return }
        didFinish = true
        onCancel()
    }

    private func build() {
        guard let contentView else { return }
        let outerScroll = NSScrollView()
        outerScroll.hasVerticalScroller = true
        outerScroll.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(outerScroll)
        NSLayoutConstraint.activate([
            outerScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            outerScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            outerScroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            outerScroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        outerScroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: outerScroll.contentView.leadingAnchor, constant: 18),
            stack.widthAnchor.constraint(equalTo: outerScroll.contentView.widthAnchor, constant: -36),
            stack.topAnchor.constraint(equalTo: outerScroll.contentView.topAnchor, constant: 16)
        ])
        stack.addArrangedSubview(row(L10n.text("Имя кнопки"), nameField))
        kindPopup.addItems(withTitles: [L10n.text("Нажать клавишу"), L10n.text("Удерживать клавишу"), L10n.text("Нажать во время удержания")])
        kindPopup.target = self
        kindPopup.action = #selector(kindChanged)
        kindPopup.widthAnchor.constraint(equalToConstant: 250).isActive = true
        durationField.widthAnchor.constraint(equalToConstant: 62).isActive = true
        offsetField.widthAnchor.constraint(equalToConstant: 62).isActive = true
        stack.addArrangedSubview(kindPopup)
        let timing = NSStackView(views: [NSTextField(labelWithString: L10n.text("длительность, с")), durationField,
                                         stepperView(tag: 0), NSTextField(labelWithString: L10n.text("смещение, с")),
                                         offsetField, stepperView(tag: 1)])
        timing.orientation = .horizontal; timing.spacing = 5; stack.addArrangedSubview(timing)
        textField.placeholderString = L10n.text("Текст для ввода")
        waitField.widthAnchor.constraint(equalToConstant: 62).isActive = true
        textIntervalField.widthAnchor.constraint(equalToConstant: 62).isActive = true
        textField.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let controls = NSStackView()
        controls.orientation = .horizontal; controls.spacing = 8
        let addKey = NSButton(title: L10n.text("Выбрать клавишу…"), target: self, action: #selector(addKey))
        let addWait = NSButton(title: L10n.text("Добавить паузу"), target: self, action: #selector(addWait))
        let addText = NSButton(title: L10n.text("Добавить текст"), target: self, action: #selector(addText))
        controls.addArrangedSubview(addKey)
        stack.addArrangedSubview(controls)
        stack.addArrangedSubview(NSStackView(views: [textField, addText, NSTextField(labelWithString: L10n.text("интервал с")), textIntervalField, stepperView(tag: 3)]))
        stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: L10n.text("пауза, с")), waitField, stepperView(tag: 2), addWait]))
        let keyboard = NSStackView()
        keyboard.orientation = .vertical; keyboard.spacing = 3
        for start in stride(from: 0, to: alphabet.count, by: 20) {
            let keyRow = NSStackView(); keyRow.orientation = .horizontal; keyRow.spacing = 3
            for index in start..<min(start + 20, alphabet.count) {
                let character = String(alphabet[index])
                let key = NSButton(title: uppercase ? character.uppercased() : character, target: self, action: #selector(typeCharacter(_:)))
                key.tag = index; key.widthAnchor.constraint(equalToConstant: 27).isActive = true
                keyButtons.append(key)
                keyRow.addArrangedSubview(key)
            }
            keyboard.addArrangedSubview(keyRow)
        }
        let textTools = NSStackView(views: [
            NSButton(title: L10n.text("⇧ Регистр"), target: self, action: #selector(toggleCase)),
            NSButton(title: L10n.text("Пробел"), target: self, action: #selector(insertSpace)),
            NSButton(title: "⌫", target: self, action: #selector(backspace)),
            NSButton(title: L10n.text("Очистить поле"), target: self, action: #selector(clearTextField))
        ])
        textTools.orientation = .horizontal; textTools.spacing = 6
        stack.addArrangedSubview(keyboard); stack.addArrangedSubview(textTools)
        stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: L10n.text("Между нажатиями, с")), gapField]))
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 5
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.documentView = rows
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 180).isActive = true
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        rows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor).isActive = true
        rows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor).isActive = true
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        status.textColor = .secondaryLabelColor; stack.addArrangedSubview(status)
        let remove = NSButton(title: L10n.text("Удалить выбранный"), target: self, action: #selector(removeLast))
        let cancel = NSButton(title: L10n.text("Отмена"), target: self, action: #selector(cancel))
        let save = NSButton(title: L10n.text("Сохранить кнопку"), target: self, action: #selector(save))
        stack.addArrangedSubview(NSStackView(views: [
            NSButton(title: L10n.text("Применить параметры"), target: self, action: #selector(applySelected)),
            NSButton(title: L10n.text("Изменить клавиши…"), target: self, action: #selector(changeKeys)),
            NSButton(title: "↑", target: self, action: #selector(moveStepUp)),
            NSButton(title: "↓", target: self, action: #selector(moveStepDown)), remove
        ]))
        let footer = NSStackView(views: [NSView(), cancel, save])
        footer.orientation = .horizontal; footer.spacing = 8; stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func row(_ label: String, _ field: NSTextField) -> NSStackView {
        let title = NSTextField(labelWithString: label); title.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let stack = NSStackView(views: [title, field]); stack.orientation = .horizontal; stack.spacing = 8
        field.widthAnchor.constraint(equalToConstant: 330).isActive = true
        return stack
    }

    @objc private func kindChanged() {
        durationField.stringValue = kindPopup.indexOfSelectedItem == 1 ? "3" : "0.033"
    }

    private func stepperView(tag: Int) -> NSStackView {
        let down = NSButton(title: "−", target: self, action: #selector(adjustValue(_:)))
        let up = NSButton(title: "+", target: self, action: #selector(adjustValue(_:)))
        down.tag = tag * 2; up.tag = tag * 2 + 1
        down.widthAnchor.constraint(equalToConstant: 25).isActive = true
        up.widthAnchor.constraint(equalToConstant: 25).isActive = true
        return NSStackView(views: [down, up])
    }

    @objc private func adjustValue(_ sender: NSButton) {
        let field: NSTextField
        let kind = sender.tag / 2
        switch kind {
        case 0: field = durationField
        case 1: field = offsetField
        case 2: field = waitField
        default: field = textIntervalField
        }
        let current = Double(field.stringValue.replacingOccurrences(of: ",", with: ".")) ?? 0
        let increment = kind == 3 ? 0.01 : 0.1
        let minimum = kind == 1 ? 0.0 : 0.001
        let maximum = kind == 3 ? 1.0 : 3600.0
        let direction = sender.tag % 2 == 0 ? -1.0 : 1.0
        field.stringValue = String(format: "%.3f", min(maximum, max(minimum, current + increment * direction)))
    }

    @objc private func addKey() {
        guard let duration = MacroDefinition.milliseconds(durationField.stringValue),
              let offset = MacroDefinition.milliseconds(offsetField.stringValue, allowZero: true) else {
            status.stringValue = L10n.text("Укажите корректное время от 0,001 до 3600 секунд."); return
        }
        let kind = kindPopup.indexOfSelectedItem
        let parent = selected
        onChooseKey { [weak self] action, _ in
            guard let self, !self.didFinish else { return }
            guard action.combinationMode == .simultaneous else {
                self.status.stringValue = L10n.text("Последовательность задаётся отдельными шагами; выберите одновременное сочетание."); return
            }
            switch kind {
            case 1: self.steps.append(.hold(action, milliseconds: duration, during: []))
            case 2:
                guard let index = parent, self.steps.indices.contains(index),
                      case let .hold(outer, ms, items) = self.steps[index] else {
                    self.status.stringValue = L10n.text("Выберите строку удержания для вложенного нажатия."); return
                }
                self.steps[index] = .hold(outer, milliseconds: ms, during: items + [TimedMacroTap(offsetMilliseconds: offset, action: action, durationMilliseconds: duration)])
            default:
                guard duration <= 1000 else { self.status.stringValue = L10n.text("Для нажатия дольше секунды выберите удержание."); return }
                self.steps.append(.tap(action, milliseconds: duration))
            }
            self.rebuildRows(); self.makeKeyAndOrderFront(nil)
        }
    }
    @objc private func typeCharacter(_ sender: NSButton) {
        guard let activeTextField, alphabet.indices.contains(sender.tag), activeTextField.stringValue.count < 4096 else { return }
        let value = String(alphabet[sender.tag])
        activeTextField.stringValue += uppercase ? value.uppercased() : value
    }
    @objc private func toggleCase() { uppercase.toggle(); buildKeyboardLabels() }
    private func buildKeyboardLabels() {
        for (index, key) in keyButtons.enumerated() {
            key.title = uppercase ? String(alphabet[index]).uppercased() : String(alphabet[index])
        }
    }
    @objc private func insertSpace() { if let activeTextField, activeTextField.stringValue.count < 4096 { activeTextField.stringValue += " " } }
    @objc private func backspace() { if let activeTextField, !activeTextField.stringValue.isEmpty { activeTextField.stringValue.removeLast() } }
    @objc private func clearTextField() { activeTextField?.stringValue = "" }

    @objc private func addWait() {
        guard let ms = MacroDefinition.milliseconds(waitField.stringValue) else { status.stringValue = L10n.text("Пауза: от 0,001 до 3600 секунд."); return }
        steps.append(.wait(milliseconds: ms)); appendRow(L10n.text("Пауза · ") + String(ms) + L10n.text(" мс"))
    }

    @objc private func addText() {
        let value = textField.stringValue
        guard !value.isEmpty else { status.stringValue = L10n.text("Введите текст перед добавлением."); return }
        guard let interval = MacroDefinition.milliseconds(textIntervalField.stringValue, maximum: 1000) else { status.stringValue = L10n.text("Интервал текста: от 0,001 до 1 секунды."); return }
        steps.append(.text(value, intervalMilliseconds: interval))
        appendRow(L10n.text("Текст · ") + String(value.count) + L10n.text(" символов"))
        textField.stringValue = ""
    }

    private func appendRow(_ value: String) { rebuildRows() }
    private func keys(_ action: KeyAction) -> String {
        action.bindings.map { binding in
            let flags = NSEvent.ModifierFlags(rawValue: UInt(binding.modifiers))
            let prefix = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
                + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            return prefix + language.label(for: binding.keyCode)
        }.joined(separator: " + ")
    }
    private func summary(_ step: MacroStep) -> String {
        switch step {
        case let .tap(action, ms): return L10n.format("Tap %@ · %@ ms", keys(action), String(ms))
        case let .hold(action, ms, _): return L10n.format("Hold %@ · %@ ms", keys(action), String(ms))
        case .wait(let ms): return L10n.format("Wait · %@ ms", String(ms))
        case .text(let value, let ms): return L10n.format("Text: %@ · interval %@ ms", value, String(ms))
        }
    }
    private func rebuildRows() {
        for view in rows.arrangedSubviews { rows.removeArrangedSubview(view); view.removeFromSuperview() }
        rowAddresses.removeAll()
        func add(_ title: String, _ parent: Int, _ child: Int?) {
            let button = NSButton(title: title, target: self, action: #selector(selectRow(_:)))
            button.tag = rowAddresses.count
            button.setButtonType(.pushOnPushOff)
            button.state = selected == parent && selectedChild == child ? .on : .off
            button.alignment = .left
            button.lineBreakMode = .byTruncatingTail
            button.toolTip = title
            rowAddresses.append((parent, child)); rows.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        for (index, step) in steps.enumerated() {
            add("\(index + 1). " + summary(step), index, nil)
            if case let .hold(_, _, children) = step {
                for (childIndex, child) in children.enumerated() {
                    add("    " + L10n.format("After %@ ms: %@ · %@ ms", String(child.offsetMilliseconds), keys(child.action), String(child.durationMilliseconds)), index, childIndex)
                }
            }
        }
        status.stringValue = L10n.format("Steps: %@/128. Select a step to edit.", String(rowAddresses.count))
    }
    @objc private func selectRow(_ sender: NSButton) {
        guard rowAddresses.indices.contains(sender.tag) else { return }
        let address = rowAddresses[sender.tag]; selected = address.0; selectedChild = address.1
        switch steps[address.0] {
        case let .tap(_, ms): durationField.stringValue = String(Double(ms) / 1000); kindPopup.selectItem(at: 0)
        case let .hold(_, ms, children):
            durationField.stringValue = String(Double(ms) / 1000); kindPopup.selectItem(at: 1)
            if let child = address.1 {
                durationField.stringValue = String(Double(children[child].durationMilliseconds) / 1000)
                offsetField.stringValue = String(Double(children[child].offsetMilliseconds) / 1000)
                kindPopup.selectItem(at: 2)
            }
        case let .wait(ms): waitField.stringValue = String(Double(ms) / 1000)
        case let .text(value, ms): textField.stringValue = value; textIntervalField.stringValue = String(Double(ms) / 1000)
        }
        rebuildRows()
    }
    @objc private func applySelected() {
        guard let index = selected, steps.indices.contains(index) else { return }
        switch steps[index] {
        case let .tap(action, _):
            guard let ms = MacroDefinition.milliseconds(durationField.stringValue, maximum: 1000) else { return }
            steps[index] = .tap(action, milliseconds: ms)
        case let .hold(action, old, children):
            guard let ms = MacroDefinition.milliseconds(durationField.stringValue) else { return }
            if let child = selectedChild, children.indices.contains(child) {
                guard let offset = MacroDefinition.milliseconds(offsetField.stringValue, allowZero: true) else { return }
                var changed = children; changed[child].durationMilliseconds = ms; changed[child].offsetMilliseconds = offset
                steps[index] = .hold(action, milliseconds: old, during: changed)
            } else { steps[index] = .hold(action, milliseconds: ms, during: children) }
        case .wait:
            guard let ms = MacroDefinition.milliseconds(waitField.stringValue) else { return }
            steps[index] = .wait(milliseconds: ms)
        case .text:
            guard let ms = MacroDefinition.milliseconds(textIntervalField.stringValue, maximum: 1000) else { return }
            steps[index] = .text(textField.stringValue, intervalMilliseconds: ms)
        }
        rebuildRows()
    }
    @objc private func removeLast() {
        guard let index = selected, steps.indices.contains(index) else { return }
        if let child = selectedChild, case let .hold(action, ms, items) = steps[index], items.indices.contains(child) {
            var updated = items; updated.remove(at: child); steps[index] = .hold(action, milliseconds: ms, during: updated)
        } else { steps.remove(at: index) }
        selected = nil; selectedChild = nil; rebuildRows()
    }
    @objc private func moveStepUp() { move(-1) }
    @objc private func moveStepDown() { move(1) }
    private func move(_ delta: Int) {
        guard let index = selected else { return }
        if let child = selectedChild, case let .hold(action, ms, items) = steps[index], items.indices.contains(child + delta) {
            var updated = items; updated.swapAt(child, child + delta)
            steps[index] = .hold(action, milliseconds: ms, during: updated); selectedChild = child + delta
        } else if selectedChild == nil, steps.indices.contains(index + delta) {
            steps.swapAt(index, index + delta); selected = index + delta
        }
        rebuildRows()
    }

    @objc private func changeKeys() {
        guard let index = selected, steps.indices.contains(index) else { return }
        let child = selectedChild
        onChooseKey { [weak self] action, _ in
            guard let self, !self.didFinish, self.steps.indices.contains(index),
                  action.combinationMode == .simultaneous else { return }
            switch self.steps[index] {
            case let .tap(_, ms): self.steps[index] = .tap(action, milliseconds: ms)
            case let .hold(parent, ms, items):
                if let child, items.indices.contains(child) {
                    var changed = items; changed[child].action = action
                    self.steps[index] = .hold(parent, milliseconds: ms, during: changed)
                } else { self.steps[index] = .hold(action, milliseconds: ms, during: items) }
            default: return
            }
            self.rebuildRows(); self.makeKeyAndOrderFront(nil)
        }
    }
    @objc private func cancel() { close() }
    @objc private func save() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 128 else { status.stringValue = L10n.text("Имя должно содержать от 1 до 128 символов."); return }
        guard let gap = MacroDefinition.milliseconds(gapField.stringValue, maximum: 1000),
              let macro = try? MacroDefinition(steps: steps, releaseGapMilliseconds: gap).validated() else {
            status.stringValue = L10n.text("План пуст или содержит недопустимый шаг, тайминг либо длительность.")
            return
        }
        guard onSave(name, macro) else { status.stringValue = L10n.text("Не удалось сохранить. Исправьте ошибку и повторите."); return }
        didFinish = true; close()
    }
}

private final class MacroMouseTextField: NSTextField {
    var onSelect: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onSelect?(); super.mouseDown(with: event) }
}
