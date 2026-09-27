import AppKit
import OverSlayCore

/// Mouse-first property editor for overlay buttons.
final class WidgetPropertiesWindow: NSPanel, NSWindowDelegate {
    private let mode: TriggerMode?
    private let onSave: (TriggerMode?, Double, Double, ButtonAppearance) -> String?
    private let onCancel: () -> Void
    private let modePopup = NSPopUpButton()
    private let patternPopup = NSPopUpButton()
    private let opacitySlider = NSSlider(value: 0.72, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let durationSlider = NSSlider(value: 5, minValue: 0.1, maxValue: 3600, target: nil, action: nil)
    private let opacityValue = NSTextField(labelWithString: "72%")
    private let durationValue = NSTextField(labelWithString: "5.0 s")
    private let preview = ButtonAppearancePreview()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var buttonAppearance: ButtonAppearance
    private var swatches: [AppearanceSwatch] = []
    private var didFinish = false

    init(title: String, mode: TriggerMode?, opacity: Double, durationSeconds: Double,
         appearance: ButtonAppearance = .default,
         onSave: @escaping (TriggerMode?, Double, Double, ButtonAppearance) -> String?,
         onCancel: @escaping () -> Void = {}) {
        self.mode = mode
        self.buttonAppearance = appearance
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(contentRect: NSRect(x: 0, y: 0, width: 430, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.title = title
        isReleasedWhenClosed = false
        delegate = self
        buildContent(opacity: opacity, durationSeconds: durationSeconds)
    }

    func start() { center(); makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }

    func windowWillClose(_ notification: Notification) {
        guard !didFinish else { return }
        didFinish = true
        onCancel()
    }

    private func buildContent(opacity: Double, durationSeconds: Double) {
        guard let contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
        ])

        if mode != nil {
            modePopup.addItems(withTitles: [L10n.text("Обычный режим"), "Toggle", L10n.text("Временный Toggle")])
            modePopup.selectItem(at: modeIndex(mode ?? .hold)); modePopup.target = self; modePopup.action = #selector(modeChanged(_:))
            modePopup.widthAnchor.constraint(equalToConstant: 205).isActive = true
            stack.addArrangedSubview(labeledRow(L10n.text("Режим"), modePopup))
        }
        opacitySlider.doubleValue = min(max(opacity, 0.1), 1)
        opacitySlider.target = self; opacitySlider.action = #selector(opacityChanged(_:)); opacitySlider.widthAnchor.constraint(equalToConstant: 205).isActive = true
        stack.addArrangedSubview(labeledRow(L10n.text("Прозрачность"), opacitySlider, value: opacityValue))
        durationSlider.doubleValue = min(max(durationSeconds, 0.1), 3600)
        durationSlider.target = self; durationSlider.action = #selector(durationChanged(_:)); durationSlider.widthAnchor.constraint(equalToConstant: 205).isActive = true
        if mode != nil { stack.addArrangedSubview(labeledRow(L10n.text("Время"), durationSlider, value: durationValue)) }

        let appearanceHeader = NSStackView(views: [NSTextField(labelWithString: L10n.text("Оформление")), NSView(), preview])
        appearanceHeader.orientation = .horizontal; appearanceHeader.alignment = .centerY; appearanceHeader.spacing = 8
        preview.buttonAppearance = buttonAppearance
        preview.opacity = CGFloat(opacitySlider.doubleValue)
        stack.addArrangedSubview(appearanceHeader)
        patternPopup.addItems(withTitles: [L10n.text("Сплошной"), L10n.text("Градиент"), L10n.text("Полосы"), L10n.text("Шахматный")])
        patternPopup.selectItem(at: patternIndex(buttonAppearance.pattern)); patternPopup.target = self; patternPopup.action = #selector(patternChanged(_:))
        patternPopup.widthAnchor.constraint(equalToConstant: 205).isActive = true
        stack.addArrangedSubview(labeledRow(L10n.text("Заливка"), patternPopup))

        stack.addArrangedSubview(paletteRow(title: L10n.text("Цвет 1"), tagBase: 0, selected: buttonAppearance.firstColor))
        stack.addArrangedSubview(paletteRow(title: L10n.text("Цвет 2"), tagBase: 10, selected: buttonAppearance.secondColor))
        let reset = NSButton(title: L10n.text("Сбросить оформление"), target: self, action: #selector(resetAppearance))
        reset.bezelStyle = .rounded
        stack.addArrangedSubview(reset)

        errorLabel.textColor = .systemRed; errorLabel.font = .systemFont(ofSize: 11); errorLabel.stringValue = " "
        errorLabel.widthAnchor.constraint(equalToConstant: 390).isActive = true
        errorLabel.heightAnchor.constraint(equalToConstant: 38).isActive = true
        stack.addArrangedSubview(errorLabel)
        let buttons = NSStackView()
        buttons.orientation = .horizontal; buttons.spacing = 8; buttons.addArrangedSubview(NSView())
        buttons.addArrangedSubview(NSButton(title: L10n.text("Отмена"), target: self, action: #selector(cancelClicked)))
        let save = NSButton(title: L10n.text("Сохранить"), target: self, action: #selector(saveClicked)); save.keyEquivalent = "\r"
        buttons.addArrangedSubview(save); buttons.widthAnchor.constraint(equalToConstant: 390).isActive = true
        stack.addArrangedSubview(buttons)
        contentView.layoutSubtreeIfNeeded()
        let fittedHeight = stack.fittingSize.height + 28
        setContentSize(NSSize(width: 430, height: max(340, fittedHeight)))
        modeChanged(modePopup); opacityChanged(opacitySlider); durationChanged(durationSlider); updateAppearanceControls()
    }

    private func paletteRow(title: String, tagBase: Int, selected: String) -> NSStackView {
        let row = NSStackView(); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 7
        let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 112).isActive = true; row.addArrangedSubview(label)
        for (index, hex) in ButtonAppearanceRenderer.palette.enumerated() {
            let button = AppearanceSwatch(title: "", target: self, action: #selector(colorClicked(_:)))
            button.tag = tagBase + index; button.swatchColor = ButtonAppearanceRenderer.color(hex); button.selected = hex == selected
            button.widthAnchor.constraint(equalToConstant: 25).isActive = true
            button.heightAnchor.constraint(equalToConstant: 23).isActive = true
            button.setAccessibilityLabel("\(title): \(hex)")
            row.addArrangedSubview(button)
            swatches.append(button)
        }
        return row
    }

    private func labeledRow(_ title: String, _ control: NSView, value: NSTextField? = nil) -> NSStackView {
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 8
        let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 112).isActive = true
        row.addArrangedSubview(label); row.addArrangedSubview(control)
        if let value { value.alignment = .right; value.widthAnchor.constraint(equalToConstant: 52).isActive = true; row.addArrangedSubview(value) }
        return row
    }

    private func modeIndex(_ value: TriggerMode) -> Int { switch value { case .hold: 0; case .toggle: 1; case .timedToggle: 2 } }
    private func patternIndex(_ value: ButtonPattern) -> Int { switch value { case .solid: 0; case .gradient: 1; case .stripes: 2; case .checkered: 3 } }
    private func selectedMode() -> TriggerMode? {
        guard mode != nil else { return nil }
        switch modePopup.indexOfSelectedItem { case 1: return .toggle; case 2: return .timedToggle; default: return .hold }
    }
    private func updateAppearanceControls() {
        preview.buttonAppearance = buttonAppearance
        let needsSecond = buttonAppearance.pattern != .solid
        for swatch in swatches where swatch.tag >= 10 && swatch.tag < 18 { swatch.isEnabled = needsSecond }
    }

    @objc private func modeChanged(_ sender: Any?) { durationSlider.isEnabled = selectedMode() == .timedToggle || mode == nil; durationValue.textColor = durationSlider.isEnabled ? .labelColor : .secondaryLabelColor }
    @objc private func opacityChanged(_ sender: Any?) { opacityValue.stringValue = "\(Int((opacitySlider.doubleValue * 100).rounded()))%"; preview.opacity = CGFloat(opacitySlider.doubleValue) }
    @objc private func durationChanged(_ sender: Any?) { durationValue.stringValue = String(format: "%.1f s", durationSlider.doubleValue) }
    @objc private func patternChanged(_ sender: Any?) { buttonAppearance.pattern = [.solid, .gradient, .stripes, .checkered][max(0, min(3, patternPopup.indexOfSelectedItem))]; updateAppearanceControls() }
    @objc private func colorClicked(_ sender: NSButton) {
        let index = sender.tag >= 10 ? sender.tag - 10 : sender.tag
        guard ButtonAppearanceRenderer.palette.indices.contains(index) else { return }
        if sender.tag >= 10 { buttonAppearance.secondColor = ButtonAppearanceRenderer.palette[index] }
        else { buttonAppearance.firstColor = ButtonAppearanceRenderer.palette[index] }
        refreshPaletteSelection(); updateAppearanceControls()
    }
    private func refreshPaletteSelection() {
        for swatch in swatches {
            let selected = swatch.tag >= 10 ? buttonAppearance.secondColor : buttonAppearance.firstColor
            let index = swatch.tag >= 10 ? swatch.tag - 10 : swatch.tag
            if ButtonAppearanceRenderer.palette.indices.contains(index) { swatch.selected = ButtonAppearanceRenderer.palette[index] == selected }
        }
    }
    @objc private func resetAppearance() { buttonAppearance = .default; patternPopup.selectItem(at: 0); refreshPaletteSelection(); updateAppearanceControls(); errorLabel.stringValue = " " }
    @objc private func cancelClicked() { close() }
    @objc private func saveClicked() {
        if let message = onSave(selectedMode(), opacitySlider.doubleValue, durationSlider.doubleValue, buttonAppearance) {
            errorLabel.stringValue = L10n.format("Could not save: %@", message)
        } else {
            didFinish = true; close()
        }
    }
}
