import AppKit
import OverSlayCore
import UniformTypeIdentifiers

struct RunningProfileTarget {
    let name: String
    let bundleIdentifier: String
}

final class ProfileManagerWindow: NSWindow {
    var onSelect: ((UUID) -> Void)?
    var onAutoSelect: ((Bool) -> Void)?
    var onCreateDefault: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onBind: ((UUID, String?) -> Void)?
    var onImport: (() -> Void)?
    var onReplace: ((UUID) -> Void)?
    var onExport: ((UUID) -> Void)?

    private let profilePopup = NSPopUpButton()
    private let runningAppPopup = NSPopUpButton()
    private let autoSelectButton = NSButton(checkboxWithTitle: L10n.text("Автоматически выбирать профиль по игре"), target: nil, action: nil)
    private let nameField = NSTextField(string: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var profiles: [Profile] = []
    private var defaultProfileID: UUID?
    private var activeProfileID: UUID?
    private var isRefreshing = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 700, height: 650), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        title = L10n.text("Профили OverSlay")
        isReleasedWhenClosed = false
        buildContent()
    }

    func show(profiles: [Profile], activeID: UUID, defaultID: UUID, autoSelect: Bool, runningTargets: [RunningProfileTarget], issues: [String], present: Bool = true) {
        self.profiles = profiles
        self.activeProfileID = activeID
        self.defaultProfileID = defaultID
        isRefreshing = true
        profilePopup.removeAllItems()
        for profile in profiles {
            profilePopup.addItem(withTitle: profile.name + (profile.id == activeID ? L10n.text(" · активен") : ""))
            profilePopup.lastItem?.representedObject = profile.id.uuidString
        }
        if let activeIndex = profiles.firstIndex(where: { $0.id == activeID }) { profilePopup.selectItem(at: activeIndex) }
        runningAppPopup.removeAllItems()
        runningAppPopup.addItem(withTitle: L10n.text("Не привязана"))
        runningAppPopup.lastItem?.representedObject = ""
        for target in runningTargets {
            runningAppPopup.addItem(withTitle: "\(target.name) — \(target.bundleIdentifier)")
            runningAppPopup.lastItem?.representedObject = target.bundleIdentifier
        }
        let currentBinding = profiles.first(where: { $0.id == activeID })?.bundleIdentifier
        if let currentBinding, !runningTargets.contains(where: { $0.bundleIdentifier == currentBinding }) {
            runningAppPopup.addItem(withTitle: L10n.format("Not Running — %@", currentBinding))
            runningAppPopup.lastItem?.representedObject = currentBinding
        }
        if let index = runningAppPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == (currentBinding ?? "") }) {
            runningAppPopup.selectItem(at: index)
        }
        autoSelectButton.state = autoSelect ? .on : .off
        nameField.stringValue = profiles.first(where: { $0.id == activeID })?.name ?? ""
        let binding = currentBinding.map { bundle in
            if let target = runningTargets.first(where: { $0.bundleIdentifier == bundle }) {
                return L10n.format("Linked to: %@ (%@)", target.name, bundle)
            }
            return L10n.format("Linked to app (not running): %@", bundle)
        } ?? L10n.text("Нет привязанной игры")
        statusLabel.stringValue = issues.isEmpty ? binding : L10n.format("%@\nCould not read some files:\n%@", binding, issues.joined(separator: "\n"))
        isRefreshing = false
        if present {
            centerIfNeeded()
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func centerIfNeeded() {
        if !isVisible { center() }
    }

    private func buildContent() {
        guard let contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18)
        ])

        root.addArrangedSubview(labeledRow(L10n.text("Активный профиль"), profilePopup))
        profilePopup.target = self
        profilePopup.action = #selector(profileChanged(_:))

        let profileActions = NSStackView(views: [button(L10n.text("Новая стандартная"), #selector(createDefault)), button(L10n.text("Копия текущего"), #selector(duplicate)), button(L10n.text("Удалить"), #selector(deleteProfile))])
        profileActions.orientation = .horizontal
        profileActions.spacing = 8
        root.addArrangedSubview(profileActions)

        autoSelectButton.target = self
        autoSelectButton.action = #selector(autoSelectChanged(_:))
        root.addArrangedSubview(autoSelectButton)
        root.addArrangedSubview(labeledRow(L10n.text("Запущенное приложение"), runningAppPopup))
        runningAppPopup.target = self
        runningAppPopup.action = #selector(runningAppChanged(_:))
        let bindActions = NSStackView(views: [button(L10n.text("Привязать выбранное"), #selector(bindRunningApp)), button(L10n.text("Выбрать .app…"), #selector(chooseApplication)), button(L10n.text("Снять привязку"), #selector(unbindProfile))])
        bindActions.orientation = .horizontal
        bindActions.spacing = 8
        root.addArrangedSubview(bindActions)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.maximumNumberOfLines = 4
        root.addArrangedSubview(statusLabel)
        let separator = NSBox()
        separator.boxType = .separator
        root.addArrangedSubview(separator)

        nameField.isEditable = false
        nameField.isSelectable = true
        nameField.placeholderString = L10n.text("Имя профиля")
        nameField.widthAnchor.constraint(equalToConstant: 210).isActive = true
        let renameRow = NSStackView(views: [nameField, button(L10n.text("Сохранить имя"), #selector(renameProfile)), button("⌫", #selector(backspace)), button(L10n.text("Очистить"), #selector(clearName))])
        renameRow.orientation = .horizontal
        renameRow.spacing = 8
        root.addArrangedSubview(renameRow)

        let alphabet = Array("АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_")
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.spacing = 4
        for start in stride(from: 0, to: alphabet.count, by: 10) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 4
            for index in start..<min(start + 10, alphabet.count) {
                let key = NSButton(title: String(alphabet[index]), target: self, action: #selector(nameKey(_:)))
                key.tag = index
                key.bezelStyle = .rounded
                key.widthAnchor.constraint(equalToConstant: 48).isActive = true
                key.heightAnchor.constraint(equalToConstant: 30).isActive = true
                row.addArrangedSubview(key)
            }
            grid.addArrangedSubview(row)
        }
        root.addArrangedSubview(grid)

        let fileActions = NSStackView(views: [button(L10n.text("Добавить импорт…"), #selector(importProfile)), button(L10n.text("Заменить профиль…"), #selector(replaceProfile)), button(L10n.text("Экспортировать…"), #selector(exportProfile))])
        fileActions.orientation = .horizontal
        fileActions.spacing = 8
        root.addArrangedSubview(fileActions)
    }

    private func labeledRow(_ label: String, _ control: NSView) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.widthAnchor.constraint(equalToConstant: 155).isActive = true
        let row = NSStackView(views: [title, control])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    private var selectedProfileID: UUID? {
        guard let raw = profilePopup.selectedItem?.representedObject as? String else { return nil }
        return UUID(uuidString: raw)
    }

    @objc private func profileChanged(_ sender: NSPopUpButton) {
        guard !isRefreshing, let id = selectedProfileID else { return }
        activeProfileID = id
        nameField.stringValue = profiles.first(where: { $0.id == id })?.name ?? ""
        onSelect?(id)
    }

    @objc private func autoSelectChanged(_ sender: NSButton) { onAutoSelect?(sender.state == .on) }
    @objc private func runningAppChanged(_ sender: NSPopUpButton) {}
    @objc private func createDefault() { onCreateDefault?() }
    @objc private func duplicate() { onDuplicate?() }

    @objc private func deleteProfile() {
        guard let id = selectedProfileID else { return }
        guard id != defaultProfileID else { showError(L10n.text("Профиль «По умолчанию» нельзя удалить.")); return }
        let alert = NSAlert()
        alert.messageText = L10n.text("Удалить профиль?")
        alert.informativeText = L10n.format("Профиль «%@» будет удалён.", profiles.first(where: { $0.id == id })?.name ?? "")
        alert.addButton(withTitle: L10n.text("Удалить"))
        alert.addButton(withTitle: L10n.text("Отмена"))
        if alert.runModal() == .alertFirstButtonReturn { onDelete?(id) }
    }

    @objc private func bindRunningApp() {
        guard let id = activeProfileID, let bundle = runningAppPopup.selectedItem?.representedObject as? String, !bundle.isEmpty else { return }
        onBind?(id, bundle)
    }

    @objc private func chooseApplication() {
        guard let id = activeProfileID else { return }
        let picker = NSOpenPanel()
        picker.title = L10n.text("Выберите игру или приложение")
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        guard let bundle = Bundle(url: url)?.bundleIdentifier, !bundle.isEmpty else {
            showError(L10n.text("В выбранном приложении не найден bundle ID."))
            return
        }
        onBind?(id, bundle)
    }

    @objc private func unbindProfile() { if let id = activeProfileID { onBind?(id, nil) } }
    @objc private func renameProfile() { if let id = activeProfileID { onRename?(id, nameField.stringValue) } }
    @objc private func importProfile() { onImport?() }
    @objc private func replaceProfile() {
        guard let id = activeProfileID else { return }
        onReplace?(id)
    }
    @objc private func exportProfile() { if let id = activeProfileID { onExport?(id) } }
    @objc private func nameKey(_ sender: NSButton) {
        let alphabet = Array("АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_")
        guard alphabet.indices.contains(sender.tag), nameField.stringValue.count < 80 else { return }
        nameField.stringValue.append(alphabet[sender.tag])
    }
    @objc private func backspace() { if !nameField.stringValue.isEmpty { nameField.stringValue.removeLast() } }
    @objc private func clearName() { nameField.stringValue = "" }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: L10n.text("Закрыть"))
        alert.runModal()
    }
}
