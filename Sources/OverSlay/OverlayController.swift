import AppKit
import OverSlayCore

final class OverlayController: NSObject {
    private let injector = CGKeyInjector()
    private let scheduler = DispatchScheduler()
    private let permissions = PermissionsManager()
    private let store = ProfileStore()
    private var manager: ModeManager!
    private lazy var macroRunner = MacroRunner(sink: injector, scheduler: scheduler)
    private var macroProgressTimer: Timer?
    private var runningMacroID: UUID?
    private var emergency: EmergencyResetController!
    private var panels: [UUID: WidgetPanel] = [:]
    private var keyboardPanels: [UUID: WidgetPanel] = [:]
    private var editPanel: WidgetPanel?
    private var visibilityPanel: WidgetPanel?
    private var keyboardTogglePanel: WidgetPanel?
    private var languageTogglePanel: WidgetPanel?
    private var radialPanel: RadialPanel?
    private var radialEngine: RadialControlEngine?
    private let analogSink = VirtualJoystickSink()
    private var configs: [UUID: WidgetConfig] = [:]
    private var keyboardConfigs: [UUID: WidgetConfig] = [:]
    private var selectedIDs: Set<UUID> = []
    private var editMode = false
    private var keyboardMode = false
    private var overlayHidden = false
    private var mouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private let escapeTap = EscapeEventTap()
    private lazy var sideInputTap = SideInputEventTap(injector: injector)
    private let inputSourceController = KeyboardInputSourceController()
    private var recorder: MouseKeyPickerWindow?
    private var macroEditorWindow: MacroEditorWindow?
    private var propertiesWindow: NSWindow?
    private var profile: Profile?
    private var profileCatalog: [Profile] = []
    private var profilePreferences: ProfilePreferences?
    private var profileManagerWindow: ProfileManagerWindow?
    private var editorSettingsWindow: NSWindow?
    private var snapToGrid = true
    private var snapToEdges = true
    private var editGesture: OverlayEditGesture?
    private var editGestureGeneration: UInt64 = 0
    private var editGestureProfileID: UUID?
    private var resizeScreen: NSScreen?
    private var lastExternalBundleIdentifier: String?
    private var activationState = ProfileActivationState()
    private var profileGeneration: UInt64 = 0
    private var buttonLanguage = KeyboardLanguage(
        inputSourceID: nil,
        sourceName: L10n.text("Источник ввода недоступен"),
        canTranslate: false,
        translatedLabels: [:]
    )

    func start() {
        buttonLanguage = inputSourceController.currentLanguage
        inputSourceController.onChange = { [weak self] in self?.inputSourceDidChange() }
        manager = ModeManager(sink: injector, scheduler: scheduler, compatibilityMilliseconds: 33)
        emergency = EmergencyResetController { [weak self] in
            if Thread.isMainThread { self?.emergencyReset() }
            else { DispatchQueue.main.async { self?.emergencyReset() } }
        }
        do {
            profileCatalog = try store.loadAll()
            profilePreferences = try store.loadPreferences()
            snapToGrid = profilePreferences?.snapToGrid ?? true
            snapToEdges = profilePreferences?.snapToEdges ?? true
            guard let preferences = profilePreferences,
                  let defaultProfile = profileCatalog.first(where: { $0.id == preferences.defaultProfileID }) else {
                throw ProfileStoreError.missingDefaultProfile
            }
            let frontmost = NSWorkspace.shared.frontmostApplication
            let ownBundleID = Bundle.main.bundleIdentifier
            if let bundle = frontmost?.bundleIdentifier, bundle != ownBundleID {
                lastExternalBundleIdentifier = bundle
            }
            let initialProfile: Profile
            if preferences.autoSelectByBundleIdentifier {
                if let bundle = lastExternalBundleIdentifier {
                    initialProfile = ProfileSelection.matching(bundle, in: profileCatalog) ?? defaultProfile
                } else {
                    initialProfile = defaultProfile
                }
            } else {
                initialProfile = profileCatalog.first(where: { $0.id == preferences.lastManualProfileID }) ?? defaultProfile
            }
            profile = initialProfile
            configs = Dictionary(uniqueKeysWithValues: initialProfile.widgets.map { ($0.id, $0) })
            createPanels(initialProfile.widgets)
            if initialProfile.id != preferences.selectedProfileID {
                var updated = preferences
                updated.selectedProfileID = initialProfile.id
                try store.savePreferences(updated)
                profilePreferences = updated
            }
        } catch {
            NSLog("OverSlay profile error: %@", String(describing: error))
            DispatchQueue.main.async { [weak self] in self?.showError(error, operation: L10n.text("Не удалось загрузить раскладку. Импортируйте исправный JSON через меню OverSlay.")) }
        }
        createEditPanel()
        createVisibilityPanel()
        createKeyboardTogglePanel()
        createLanguageTogglePanel()
        createRadialPanel()
        refreshButtonLabels()
        permissions.requestIfNeeded()
        installMonitors()
        sideInputTap.update(config: profile?.radial ?? .init())
        sideInputTap.start()
    }

    func stop() {
        removeMonitors()
        sideInputTap.stop()
        recorder?.close()
        recorder = nil
        macroEditorWindow?.close()
        macroEditorWindow = nil
        propertiesWindow?.close()
        propertiesWindow = nil
        emergencyReset()
        panels.values.forEach { $0.orderOut(nil) }
        editPanel?.orderOut(nil)
        editPanel = nil
        visibilityPanel?.orderOut(nil)
        visibilityPanel = nil
        keyboardTogglePanel?.orderOut(nil)
        keyboardTogglePanel = nil
        languageTogglePanel?.orderOut(nil)
        languageTogglePanel = nil
        keyboardPanels.values.forEach { $0.orderOut(nil) }
        keyboardPanels.removeAll()
        keyboardConfigs.removeAll()
        radialPanel?.orderOut(nil)
        radialPanel = nil
        radialEngine?.releaseAll()
        analogSink.releaseAxes()
        radialEngine = nil
        analogSink.stop()
        panels.removeAll()
    }

    func clearInput() {
        macroRunner.cancel()
        runningMacroID = nil
        macroProgressTimer?.invalidate()
        macroProgressTimer = nil
        for id in configs.keys { panels[id]?.setMacroProgress(0, running: false) }
        sideInputTap.setTracking(false)
        radialPanel?.cancelTracking()
        panels.values.forEach { $0.cancelTracking() }
        keyboardPanels.values.forEach { $0.cancelTracking() }
        analogSink.releaseAxes()
        radialEngine?.releaseAll()
        manager?.reset()
        radialPanel?.setDirection(nil)
        panels.values.forEach { $0.setActive(false) }
        keyboardPanels.values.forEach { $0.setActive(false) }
        cancelEditGesture()
    }

    func emergencyReset() {
        clearInput()
        editMode = false
        selectedIDs.removeAll()
        panels.values.forEach { $0.setActive(false) }
        panels.values.forEach { $0.setEditing(false) }
        radialPanel?.setEditing(false)
        panels.values.forEach { $0.setSelected(false) }
        editPanel?.setActive(false)
        keyboardTogglePanel?.setActive(keyboardMode)
    }

    func diagnosticsText() -> String {
        let process = ProcessInfo.processInfo
        return """
        OverSlay diagnostic build
        macOS: \(process.operatingSystemVersionString)
        Accessibility: \(permissions.isTrusted ? "granted" : "required")
        Escape event tap: \(escapeTap.isRunning ? "running" : "unavailable")
        Profile widgets: \(configs.count)
        Active inputs: \(manager?.activeOwnerCount ?? 0)
        Side input event tap: \(sideInputTap.isRunning ? "running" : "unavailable")
        Analog HID: \(analogSink.isAvailable ? "available" : "unavailable")

        Supports Hold, Toggle, Timed Toggle, Compatibility Mode and emergency reset.
        Fullscreen, game compatibility and cursor capture: NOT RUN on the target Mac.
        """
    }

    private func showError(_ error: Error, operation: String) {
        clearInput()
        let alert = NSAlert()
        alert.messageText = operation
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.text("Закрыть"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func exportProfile(to url: URL) {
        guard let profile else { return }
        do {
            try store.export(profile, to: url)
        } catch {
            NSLog("OverSlay profile export error: %@", String(describing: error))
            showError(error, operation: L10n.text("Не удалось экспортировать раскладку"))
        }
    }

    func importProfile(from url: URL) {
        do {
            var imported = try store.load(from: url)
            imported = Profile(bundleIdentifier: nil, name: uniqueProfileName(L10n.text("Импорт")), widgets: imported.widgets, radial: imported.radial)
            try persistProfile(imported)
            refreshProfileCatalog()
            if profile == nil, let preferences = profilePreferences,
               let fallback = profileCatalog.first(where: { $0.id == preferences.defaultProfileID }), applyProfile(fallback) {
                var recovered = preferences
                recovered.selectedProfileID = fallback.id
                recovered.lastManualProfileID = fallback.id
                try store.savePreferences(recovered)
                profilePreferences = recovered
            }
        } catch {
            NSLog("OverSlay profile import error: %@", String(describing: error))
            showError(error, operation: L10n.text("Не удалось добавить импортированный профиль. Текущие данные сохранены."))
        }
    }

    func openProfileManager() {
        guard let profile, let preferences = profilePreferences else { return }
        clearInput()
        if profileManagerWindow == nil { configureProfileManager() }
        profileManagerWindow?.show(
            profiles: profileCatalog, activeID: profile.id, defaultID: preferences.defaultProfileID,
            autoSelect: preferences.autoSelectByBundleIdentifier,
            runningTargets: runningProfileTargets(), issues: store.catalogIssues
        )
    }

    func openEditorSettings() {
        clearInput()
        NSApp.activate(ignoringOtherApps: true)
        if editorSettingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 250), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L10n.text("Настройки редактора")
            window.level = OverlayWindowLevel.base
            window.isReleasedWhenClosed = false
            let languageLabel = NSTextField(labelWithString: L10n.text("Язык приложения"))
            let languagePopup = NSPopUpButton()
            for language in OverSlayLanguage.allCases {
                let title = language == .english ? "English" : "Русский"
                languagePopup.addItem(withTitle: title)
                languagePopup.lastItem?.representedObject = language.rawValue
            }
            languagePopup.target = self
            languagePopup.action = #selector(uiLanguageChanged(_:))
            let languageNote = NSTextField(wrappingLabelWithString: L10n.text("Язык интерфейса изменится при следующем запуске OverSlay."))
            languageNote.textColor = .secondaryLabelColor
            let grid = NSButton(checkboxWithTitle: L10n.text("Выравнивать по сетке"), target: self, action: #selector(editorSnapChanged(_:)))
            grid.tag = 1
            let edges = NSButton(checkboxWithTitle: L10n.text("Прилипать к краям"), target: self, action: #selector(editorSnapChanged(_:)))
            edges.tag = 2
            let edgeNote = NSTextField(labelWithString: L10n.text("К краям экрана и других элементов"))
            edgeNote.textColor = .secondaryLabelColor
            let stack = NSStackView(views: [languageLabel, languagePopup, languageNote, grid, edges, edgeNote])
            stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
            window.contentView = NSView()
            window.contentView?.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),
                stack.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor)
            ])
            editorSettingsWindow = window
        }
        if let stack = editorSettingsWindow?.contentView?.subviews.first as? NSStackView {
            (stack.views[1] as? NSPopUpButton)?.selectItem(withTitle: OverSlayLanguage.preferred == .english ? "English" : "Русский")
            (stack.views[3] as? NSButton)?.state = snapToGrid ? .on : .off
            (stack.views[4] as? NSButton)?.state = snapToEdges ? .on : .off
        }
        editorSettingsWindow?.center()
        editorSettingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func uiLanguageChanged(_ sender: NSPopUpButton) {
        guard let value = sender.selectedItem?.representedObject as? String,
              let language = OverSlayLanguage(rawValue: value) else { return }
        clearInput()
        OverSlayLanguage.savePreference(language)
    }

    @objc private func editorSnapChanged(_ sender: NSButton) {
        guard var preferences = profilePreferences else { return }
        if sender.tag == 1 { preferences.snapToGrid = sender.state == .on }
        else { preferences.snapToEdges = sender.state == .on }
        do {
            try store.savePreferences(preferences)
            profilePreferences = preferences
            snapToGrid = preferences.snapToGrid; snapToEdges = preferences.snapToEdges
        } catch {
            sender.state = (sender.tag == 1 ? snapToGrid : snapToEdges) ? .on : .off
            showError(error, operation: L10n.text("Не удалось сохранить настройки редактора"))
        }
    }

    private func configureProfileManager() {
        let window = ProfileManagerWindow()
        window.onSelect = { [weak self] id in self?.selectProfile(id: id, manual: true) }
        window.onAutoSelect = { [weak self] enabled in self?.setAutoProfileSelection(enabled) }
        window.onCreateDefault = { [weak self] in self?.createProfile(copyCurrent: false) }
        window.onDuplicate = { [weak self] in self?.createProfile(copyCurrent: true) }
        window.onRename = { [weak self] id, name in self?.renameProfile(id: id, name: name) }
        window.onDelete = { [weak self] id in self?.deleteProfile(id: id) }
        window.onBind = { [weak self] id, bundleID in self?.bindProfile(id: id, bundleIdentifier: bundleID) }
        window.onImport = { [weak self] in self?.importProfileFromDialog() }
        window.onReplace = { [weak self] id in self?.replaceProfileFromDialog(id: id) }
        window.onExport = { [weak self] id in self?.exportProfile(id: id) }
        profileManagerWindow = window
    }

    private func runningProfileTargets() -> [RunningProfileTarget] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let bundle = app.bundleIdentifier,
                  bundle != Bundle.main.bundleIdentifier else { return nil }
            return RunningProfileTarget(name: app.localizedName ?? bundle, bundleIdentifier: bundle)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func refreshProfileCatalog() {
        do {
            profileCatalog = try store.loadAll()
            profilePreferences = try store.loadPreferences()
            if let profile, let preferences = profilePreferences {
                profileManagerWindow?.show(profiles: profileCatalog, activeID: profile.id, defaultID: preferences.defaultProfileID,
                                           autoSelect: preferences.autoSelectByBundleIdentifier, runningTargets: runningProfileTargets(), issues: store.catalogIssues, present: false)
            }
        } catch { showError(error, operation: L10n.text("Не удалось обновить список профилей")) }
    }

    private func persistProfile(_ updated: Profile) throws {
        try store.save(updated)
        if let index = profileCatalog.firstIndex(where: { $0.id == updated.id }) {
            profileCatalog[index] = updated
        } else {
            profileCatalog.append(updated)
        }
    }

    private func uniqueProfileName(_ base: String) -> String {
        let names = Set(profileCatalog.map { $0.name.localizedLowercase })
        let shortenedBase = String(base.prefix(70))
        var candidate = shortenedBase
        var suffix = 2
        while names.contains(candidate.localizedLowercase) { candidate = "\(shortenedBase) \(suffix)"; suffix += 1 }
        return candidate
    }

    private func createProfile(copyCurrent: Bool) {
        guard let current = profile else { return }
        let created: Profile
        if copyCurrent {
            created = Profile(bundleIdentifier: nil, name: uniqueProfileName(L10n.format("%@ — copy", current.name)), widgets: current.widgets, radial: current.radial)
        } else {
            created = Profile(name: uniqueProfileName(L10n.text("Новая раскладка")), widgets: ProfileStore.defaultWidgets())
        }
        do {
            try persistProfile(created)
            refreshProfileCatalog()
            selectProfile(id: created.id, manual: true)
        } catch { showError(error, operation: L10n.text("Не удалось создать профиль")) }
    }

    private func selectProfile(id: UUID, manual: Bool) {
        let candidate: Profile
        do { candidate = try store.loadProfile(id: id) }
        catch { clearInput(); showError(error, operation: L10n.text("Не удалось загрузить выбранный профиль")); return }
        if candidate.id != profile?.id, !applyProfile(candidate) {
            refreshProfileCatalog()
            return
        }
        guard var preferences = profilePreferences else { return }
        preferences.selectedProfileID = candidate.id
        if manual {
            preferences.lastManualProfileID = candidate.id
            _ = activationState.activate(bundle: lastExternalBundleIdentifier, isOwnApplication: false, automatic: false, profiles: profileCatalog, defaultID: preferences.defaultProfileID)
            activationState.selectManually()
        }
        do {
            try store.savePreferences(preferences)
            profilePreferences = preferences
            refreshProfileCatalog()
        } catch { showError(error, operation: L10n.text("Профиль выбран, но не удалось сохранить выбор")) }
    }

    @discardableResult
    private func applyProfile(_ candidate: Profile) -> Bool {
        do { _ = try candidate.validated() } catch { showError(error, operation: L10n.text("Профиль повреждён и не был применён")); return false }
        if let current = profile, current.id != candidate.id {
            do { try persistProfile(current) }
            catch { showError(error, operation: L10n.text("Не удалось сохранить текущий профиль; переключение отменено")); return false }
        }
        clearInput()
        profileGeneration &+= 1
        editMode = false
        keyboardMode = false
        selectedIDs.removeAll()
        recorder?.close(); recorder = nil
        macroEditorWindow?.close(); macroEditorWindow = nil
        propertiesWindow?.close(); propertiesWindow = nil
        panels.values.forEach { $0.close() }
        panels.removeAll()
        configs = Dictionary(uniqueKeysWithValues: candidate.widgets.map { ($0.id, $0) })
        profile = candidate
        createPanels(candidate.widgets)
        panels.values.forEach { $0.setEditing(false); $0.setSelected(false); $0.setActive(false) }
        radialPanel?.update(config: candidate.radial)
        radialPanel?.setEditing(false)
        sideInputTap.update(config: candidate.radial)
        keyboardTogglePanel?.setActive(false)
        editPanel?.setActive(false)
        refreshButtonLabels()
        applyOverlayVisibility()
        return true
    }

    private func setAutoProfileSelection(_ enabled: Bool) {
        guard var preferences = profilePreferences else { return }
        activationState.clearOverride()
        preferences.autoSelectByBundleIdentifier = enabled
        do {
            try store.savePreferences(preferences)
            profilePreferences = preferences
            if enabled {
                let destination = lastExternalBundleIdentifier.flatMap { bundle in ProfileSelection.matching(bundle, in: profileCatalog)?.id }
                    ?? preferences.defaultProfileID
                selectProfile(id: destination, manual: false)
            } else {
                selectProfile(id: preferences.lastManualProfileID, manual: false)
            }
        } catch { showError(error, operation: L10n.text("Не удалось сохранить настройку автовыбора")) }
    }

    private func renameProfile(id: UUID, name: String) {
        guard var target = profileCatalog.first(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { showError(ProfileError.invalidName, operation: L10n.text("Введите имя длиной от 1 до 80 символов мышью.")); return }
        target.name = trimmed
        do {
            try persistProfile(target)
            if profile?.id == id { profile = target }
            refreshProfileCatalog()
        } catch { showError(error, operation: L10n.text("Не удалось переименовать профиль")) }
    }

    private func deleteProfile(id: UUID) {
        guard let preferences = profilePreferences, id != preferences.defaultProfileID else { return }
        if profile?.id == id {
            guard let defaultProfile = profileCatalog.first(where: { $0.id == preferences.defaultProfileID }), applyProfile(defaultProfile) else { return }
            var updated = preferences
            updated.selectedProfileID = defaultProfile.id
            updated.lastManualProfileID = defaultProfile.id
            do { try store.savePreferences(updated); profilePreferences = updated }
            catch { showError(error, operation: L10n.text("Не удалось сохранить переход на профиль по умолчанию")); return }
        }
        do {
            try store.delete(id: id)
            if var updated = profilePreferences, updated.lastManualProfileID == id {
                updated.lastManualProfileID = updated.defaultProfileID
                try store.savePreferences(updated)
                profilePreferences = updated
            }
            refreshProfileCatalog()
        } catch { showError(error, operation: L10n.text("Не удалось удалить профиль")) }
    }

    private func bindProfile(id: UUID, bundleIdentifier: String?) {
        guard let index = profileCatalog.firstIndex(where: { $0.id == id }) else { return }
        var target = profileCatalog[index]
        let originalTarget = target
        var conflictingProfile: Profile?
        if let bundleIdentifier,
           let other = profileCatalog.first(where: { $0.id != id && $0.bundleIdentifier == bundleIdentifier }) {
            let alert = NSAlert()
            alert.messageText = L10n.text("Игра уже привязана")
            alert.informativeText = L10n.format("%@ is linked to profile “%@”. Move the link?", bundleIdentifier, other.name)
            alert.addButton(withTitle: L10n.text("Перенести"))
            alert.addButton(withTitle: L10n.text("Отмена"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            conflictingProfile = other
        }
        target.bundleIdentifier = bundleIdentifier
        do {
            try persistProfile(target)
            if var conflictingProfile {
                conflictingProfile.bundleIdentifier = nil
                do { try persistProfile(conflictingProfile) }
                catch {
                    do {
                        try persistProfile(originalTarget)
                        showError(error, operation: L10n.text("Не удалось перенести привязку; прежнюю привязку восстановили"))
                    } catch let rollbackError {
                        showError(rollbackError, operation: L10n.text("Не удалось сохранить перенос и восстановить исходную привязку"))
                    }
                    return
                }
            }
            if profile?.id == id { profile = target }
            refreshProfileCatalog()
        } catch { showError(error, operation: L10n.text("Не удалось сохранить привязку")) }
    }

    private func exportProfile(id: UUID) {
        guard let target = profileCatalog.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.title = L10n.text("Экспортировать профиль OverSlay")
        let safeName = target.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(safeName).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(target, to: url) }
        catch { showError(error, operation: L10n.text("Не удалось экспортировать профиль")) }
    }

    private func importProfileFromDialog() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("Импортировать профиль OverSlay")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importProfile(from: url)
    }

    private func replaceProfileFromDialog(id: UUID) {
        guard let existing = profileCatalog.first(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.format("Choose a layout to replace profile “%@”", existing.name)
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try store.load(from: url)
            let confirmation = NSAlert()
            confirmation.messageText = L10n.format("Replace layout “%@”?", existing.name)
            confirmation.informativeText = L10n.format("File %@ was validated. Buttons and settings will be replaced; the name and app link will be kept.", url.lastPathComponent)
            confirmation.addButton(withTitle: L10n.text("Заменить"))
            confirmation.addButton(withTitle: L10n.text("Отмена"))
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }
            let replacement = Profile(id: existing.id, bundleIdentifier: existing.bundleIdentifier, name: existing.name,
                                      widgets: imported.widgets, radial: imported.radial)
            try persistProfile(replacement)
            if profile?.id == id { _ = applyProfile(replacement) }
            refreshProfileCatalog()
        } catch { showError(error, operation: L10n.text("Не удалось заменить профиль. Исходные данные сохранены.")) }
    }

    private func createPanels(_ widgets: [WidgetConfig]) {
        let generation = profileGeneration
        let ownerProfileID = profile?.id
        for widget in widgets {
            let panel = WidgetPanel(
                config: widget,
                onPress: { [weak self] in
                    guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation), !self.overlayHidden, !self.editMode, let current = self.configs[widget.id] else { return }
                    if current.macro == nil, current.mode == .hold { self.press(current) }
                },
                onRelease: { [weak self] in
                    guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation), !self.overlayHidden, !self.editMode, let current = self.configs[widget.id] else { return }
                    if let macro = current.macro {
                        guard self.macroEditorWindow == nil, self.recorder == nil else { return }
                        if self.macroRunner.isRunning {
                            guard self.runningMacroID == current.id else { self.panels[current.id]?.showMacroBusy(); return }
                            self.macroRunner.cancel(); self.runningMacroID = nil
                            self.panels[current.id]?.setMacroProgress(0, running: false)
                        }
                        else {
                            guard self.permissions.isTrusted || self.permissions.requestIfNeeded() else { return }
                            self.runningMacroID = current.id
                            self.panels[current.id]?.setMacroProgress(1, running: true)
                            guard self.macroRunner.start(macro, completion: { [weak self] success in
                                self?.runningMacroID = nil
                                if let error = self?.macroRunner.lastError { self?.showError(error, operation: L10n.text("Макрос остановлен")) }
                                self?.panels[current.id]?.setMacroProgress(success ? 1 : 0, running: false)
                            }) else { self.runningMacroID = nil; self.panels[current.id]?.setMacroProgress(0, running: false); return }
                            self.macroProgressTimer?.invalidate()
                            self.macroProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] timer in
                                guard let self else { timer.invalidate(); return }
                                self.panels[current.id]?.setMacroProgress(self.macroRunner.progress, running: self.macroRunner.isRunning)
                                if !self.macroRunner.isRunning { timer.invalidate(); self.macroProgressTimer = nil }
                            }
                        }
                    } else if current.mode == .toggle || current.mode == .timedToggle { self.press(current) } else if current.mode == .hold { self.release(current) }
                },
                onGeometryChanged: { [weak self] frame, isResizing in guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation) else { return }; self.geometryChanged(for: widget.id, frame: frame, isResizing: isResizing) },
                onGeometryCommitted: { [weak self] frame, isResizing in guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation) else { return }; self.geometryCommitted(for: widget.id, frame: frame, isResizing: isResizing) },
                onDelete: { [weak self] in guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation) else { return }; self.deleteButton(widget.id) },
                onEditBinding: { [weak self] in
                    guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation) else { return }
                    if let current = self.configs[widget.id], current.macro != nil { self.beginEditMacroButton(widget.id) }
                    else { self.beginEditButton(widget.id) }
                },
                onProperties: { [weak self] in guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation) else { return }; self.showProperties(for: widget.id) },
                onToggleMode: { [weak self] in guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation) else { return }; self.toggleMode(for: widget.id) },
                onToggleCombinationMode: { [weak self] in guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation) else { return }; self.toggleCombinationMode(for: widget.id) },
                onSelectionChanged: { [weak self] toggled in guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation) else { return }; self.selectionChanged(for: widget.id, toggled: toggled) }
            )
            panel.onEditBegan = { [weak self] frame, handle in
                guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation) else { return }
                self.beginEditGesture(id: widget.id.uuidString, frame: frame, handle: handle)
            }
            panel.onEditCancelled = { [weak self] in
                guard let self, self.acceptsPanelCallback(profileID: ownerProfileID, generation: generation) else { return }
                self.cancelEditGesture()
            }
            panels[widget.id] = panel
            if !overlayHidden && !keyboardMode { panel.orderFrontRegardless() }
        }
    }

    private func acceptsPanelCallback(profileID: UUID?, generation: UInt64) -> Bool {
        profileGeneration == generation && profile?.id == profileID
    }

    private func createEditPanel() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let config = WidgetConfig(
            geometry: .init(x: frame.maxX - 76, y: frame.maxY - 76, width: 58, height: 58),
            label: "⚙", action: .init(.init(keyCode: 0)), mode: .hold, opacity: 0.9
        )
        let panel = WidgetPanel(
            config: config,
            onPress: { [weak self] in self?.editButtonPressed() },
            onRelease: {},
            onGeometryChanged: { _, _ in },
            onGeometryCommitted: { _, _ in },
            onDelete: {},
            onEditBinding: {},
            onToggleMode: {},
            onToggleCombinationMode: {},
            onSelectionChanged: { _ in }
        )
        editPanel = panel
        panel.level = OverlayWindowLevel.service
        panel.worksWhenModal = true
        panel.orderFrontRegardless()
    }

    private func createVisibilityPanel() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let config = WidgetConfig(
            geometry: .init(x: frame.maxX - 144, y: frame.maxY - 76, width: 58, height: 58),
            label: "◉", action: .init(.init(keyCode: 0)), mode: .hold, opacity: 0.9
        )
        let panel = WidgetPanel(
            config: config,
            onPress: { [weak self] in self?.toggleOverlayVisibility() },
            onRelease: {}, onGeometryChanged: { _, _ in }, onGeometryCommitted: { _, _ in },
            onDelete: {}, onEditBinding: {}, onToggleMode: {}, onToggleCombinationMode: {}
        )
        visibilityPanel = panel
        panel.level = OverlayWindowLevel.service
        panel.worksWhenModal = true
        panel.setTooltip(L10n.text("Скрыть интерфейс оверлея"))
        panel.orderFrontRegardless()
    }

    private func toggleOverlayVisibility() {
        if !overlayHidden {
            clearInput()
            editMode = false
            selectedIDs.removeAll()
            panels.values.forEach { $0.setEditing(false); $0.setSelected(false) }
            radialPanel?.setEditing(false)
            recorder?.close()
            recorder = nil
            propertiesWindow?.close()
            propertiesWindow = nil
            panels.values.forEach { $0.setActive(false) }
            keyboardPanels.values.forEach { $0.setActive(false) }
            editPanel?.setActive(false)
            overlayHidden = true
        } else {
            overlayHidden = false
        }
        updateVisibilityButton()
        applyOverlayVisibility()
    }

    private func updateVisibilityButton() {
        visibilityPanel?.setLabel(overlayHidden ? "◎" : "◉")
        visibilityPanel?.setTooltip(overlayHidden ? L10n.text("Показать интерфейс оверлея") : L10n.text("Скрыть интерфейс оверлея"))
    }

    private func applyOverlayVisibility() {
        updateVisibilityButton()
        guard !overlayHidden else {
            panels.values.forEach { $0.setEditing(false) }
            radialPanel?.setEditing(false)
            panels.values.forEach { $0.orderOut(nil) }
            radialPanel?.orderOut(nil)
            keyboardPanels.values.forEach { $0.orderOut(nil) }
            keyboardTogglePanel?.orderOut(nil)
            languageTogglePanel?.orderOut(nil)
            editPanel?.orderFrontRegardless()
            visibilityPanel?.orderFrontRegardless()
            return
        }
        panels.values.forEach { $0.setEditing(editMode) }
        radialPanel?.setEditing(editMode)
        if keyboardMode {
            panels.values.forEach { $0.orderOut(nil) }
            radialPanel?.orderOut(nil)
            createFullKeyboardPanelsIfNeeded()
            keyboardPanels.values.forEach { $0.orderFrontRegardless() }
        } else {
            keyboardPanels.values.forEach { $0.orderOut(nil) }
            panels.values.forEach { $0.orderFrontRegardless() }
            radialPanel?.orderFrontRegardless()
        }
        editPanel?.orderFrontRegardless()
        visibilityPanel?.orderFrontRegardless()
        keyboardTogglePanel?.orderFrontRegardless()
        languageTogglePanel?.orderFrontRegardless()
    }

    private func createRadialPanel() {
        let config = RadialConfig(
            directions: 8,
            releaseDelayMilliseconds: 50,
            up: KeyAction(KeyBinding(keyCode: 13)),
            down: KeyAction(KeyBinding(keyCode: 1)),
            left: KeyAction(KeyBinding(keyCode: 0)),
            right: KeyAction(KeyBinding(keyCode: 2))
        )
        radialEngine = RadialControlEngine(config: config, sink: injector, scheduler: scheduler)
        let radial = profile?.radial ?? .init()
        let analogReady = analogSink.start()
        let panel = RadialPanel(
            frame: NSRect(x: radial.geometry.x, y: radial.geometry.y, width: radial.geometry.width, height: radial.geometry.height),
            opacity: radial.opacity,
            inputMode: radial.inputMode,
            onBegin: { [weak self] in
                guard let self, !self.overlayHidden, !self.editMode, self.recorder == nil, self.permissions.isTrusted || self.permissions.requestIfNeeded() else { return false }
                guard self.profile?.radial.inputMode != .analog || analogReady else { return false }
                self.sideInputTap.setTracking(true)
                self.radialEngine?.update(offset: .init(x: 0, y: 0))
                return true
            },
            onMove: { [weak self] offset in
                guard let self, !self.overlayHidden, !self.editMode, self.recorder == nil, self.permissions.isTrusted else { return }
                if self.profile?.radial.inputMode == .analog {
                    let value = AnalogStickMath.applyDeadZone(offset)
                    self.analogSink.updateAxes(value)
                } else {
                    self.radialEngine?.update(offset: offset)
                }
                self.radialPanel?.setDirection(self.radialEngine?.direction)
            },
            onEnd: { [weak self] in
                self?.sideInputTap.setTracking(false)
                self?.radialEngine?.releaseAll()
                self?.analogSink.releaseAxes()
                self?.radialPanel?.setDirection(nil)
            },
            onGeometryChanged: { [weak self] frame, isResizing, handle in self?.radialGeometryChanged(frame, isResizing: isResizing, handle: handle) },
            onGeometryCommitted: { [weak self] frame, isResizing, handle in self?.radialGeometryCommitted(frame, isResizing: isResizing, handle: handle) },
            onProperties: { [weak self] in self?.showRadialProperties() }
        )
        panel.setAnalogAvailable(analogReady)
        panel.onEditBegan = { [weak self] frame, handle in self?.beginEditGesture(id: "radial", frame: frame, handle: handle) }
        panel.onEditCancelled = { [weak self] in self?.cancelEditGesture() }
        radialPanel = panel
        panel.orderFrontRegardless()
    }

    private func createKeyboardTogglePanel() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let config = WidgetConfig(
            geometry: .init(x: frame.maxX - 212, y: frame.maxY - 76, width: 58, height: 58),
            label: "⌨", action: .init(.init(keyCode: 0)), mode: .hold, opacity: 0.9
        )
        let panel = WidgetPanel(
            config: config,
            onPress: { [weak self] in self?.toggleKeyboardMode() },
            onRelease: {},
            onGeometryChanged: { _, _ in },
            onGeometryCommitted: { _, _ in },
            onDelete: {},
            onEditBinding: {},
            onToggleMode: {},
            onToggleCombinationMode: {}
        )
        keyboardTogglePanel = panel
        panel.level = OverlayWindowLevel.service
        panel.worksWhenModal = true
        if !overlayHidden { panel.orderFrontRegardless() }
    }

    private func toggleKeyboardMode() {
        guard !editMode, !overlayHidden else { return }
        clearInput()
        keyboardMode.toggle()
        keyboardTogglePanel?.setActive(keyboardMode)
        applyOverlayVisibility()
    }

    private func createLanguageTogglePanel() {
        guard let screen = NSScreen.main else { return }
        let config = WidgetConfig(
            geometry: .init(x: screen.visibleFrame.maxX - 280, y: screen.visibleFrame.maxY - 76, width: 58, height: 58),
            label: buttonLanguage.shortTitle,
            action: .init(.init(keyCode: 0)),
            mode: .hold,
            opacity: 0.9
        )
        let panel = WidgetPanel(
            config: config,
            onPress: { [weak self] in self?.toggleButtonLanguage() },
            onRelease: {},
            onGeometryChanged: { _, _ in },
            onGeometryCommitted: { _, _ in },
            onDelete: {},
            onEditBinding: {},
            onToggleMode: {},
            onToggleCombinationMode: {}
        )
        languageTogglePanel = panel
        panel.level = OverlayWindowLevel.service
        panel.worksWhenModal = true
        if !overlayHidden { panel.orderFrontRegardless() }
    }

    func toggleButtonLanguage() {
        guard !overlayHidden else { return }
        do {
            buttonLanguage = try inputSourceController.nextLanguage { [weak self] in self?.clearInput() }
            recorder?.updateLanguage(buttonLanguage)
            (propertiesWindow as? RadialPropertiesWindow)?.updateLanguage(buttonLanguage)
            refreshButtonLabels()
        } catch {
            languageTogglePanel?.setTooltip(error.localizedDescription)
            NSLog("OverSlay input source switch failed: %@", String(describing: error))
        }
    }

    private func inputSourceDidChange() {
        buttonLanguage = inputSourceController.currentLanguage
        recorder?.updateLanguage(buttonLanguage)
        (propertiesWindow as? RadialPropertiesWindow)?.updateLanguage(buttonLanguage)
        refreshButtonLabels()
    }

    private func refreshButtonLabels() {
        for (id, config) in configs {
            panels[id]?.setLabel(buttonLanguage.displayLabel(for: config.action, fallback: config.label))
        }
        for (id, config) in keyboardConfigs {
            keyboardPanels[id]?.setLabel(buttonLanguage.displayLabel(for: config.action, fallback: config.label))
        }
        languageTogglePanel?.setLabel(buttonLanguage.shortTitle)
        languageTogglePanel?.setTooltip(buttonLanguage.tooltip)
    }

    private func createFullKeyboardPanelsIfNeeded() {
        guard keyboardPanels.isEmpty, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let keyWidth: Double = 46
        let keyHeight: Double = 42
        let gap: Double = 5
        let rows: [(String, [UInt16])] = [
            ("1234567890", [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]),
            ("QWERTYUIOP", [12, 13, 14, 15, 17, 16, 32, 34, 31, 35]),
            ("ASDFGHJKL", [0, 1, 2, 3, 5, 4, 38, 40, 37]),
            ("ZXCVBNM", [6, 7, 8, 9, 11, 45, 46])
        ]
        let rowY = frame.minY + 24
        for (rowIndex, row) in rows.enumerated() {
            let offset = Double(rowIndex) * 26
            for (index, keyCode) in row.1.enumerated() {
                let label = String(row.0[row.0.index(row.0.startIndex, offsetBy: index)])
                let id = UUID()
                let config = WidgetConfig(
                    id: id,
                    geometry: .init(
                        x: frame.midX - (Double(row.1.count) * (keyWidth + gap) - gap) / 2 + Double(index) * (keyWidth + gap) + offset,
                        y: rowY + Double(rows.count - rowIndex) * (keyHeight + gap),
                        width: keyWidth,
                        height: keyHeight
                    ),
                    label: label,
                    action: .init(.init(keyCode: keyCode)),
                    mode: .hold,
                    opacity: 0.88
                )
                keyboardConfigs[id] = config
                let panel = WidgetPanel(
                    config: config,
                    onPress: { [weak self] in self?.pressKeyboardKey(config) },
                    onRelease: { [weak self] in self?.releaseKeyboardKey(config) },
                    onGeometryChanged: { _, _ in },
                    onGeometryCommitted: { _, _ in },
                    onDelete: {},
                    onEditBinding: {},
                    onToggleMode: {},
                    onToggleCombinationMode: {},
                    onSelectionChanged: { _ in }
                )
                keyboardPanels[id] = panel
            }
        }
        let punctuation: [(String, UInt16)] = [
            ("-", 27), ("=", 24), ("[", 33), ("]", 30), ("\\", 42), (";", 41), ("'", 39), (",", 43), (".", 47), ("/", 44)
        ]
        let punctuationY = rowY + Double(rows.count + 1) * (keyHeight + gap)
        let punctuationWidth = Double(punctuation.count) * (keyWidth + gap) - gap
        for (index, item) in punctuation.enumerated() {
            let id = UUID()
            let config = WidgetConfig(
                id: id,
                geometry: .init(x: frame.midX - punctuationWidth / 2 + Double(index) * (keyWidth + gap), y: punctuationY, width: keyWidth, height: keyHeight),
                label: item.0, action: .init(.init(keyCode: item.1)), mode: .hold, opacity: 0.88
            )
            keyboardConfigs[id] = config
            let panel = WidgetPanel(
                config: config,
                onPress: { [weak self] in self?.pressKeyboardKey(config) },
                onRelease: { [weak self] in self?.releaseKeyboardKey(config) },
                    onGeometryChanged: { _, _ in },
                    onGeometryCommitted: { _, _ in },
                    onDelete: {}, onEditBinding: {}, onToggleMode: {}, onToggleCombinationMode: {}, onSelectionChanged: { _ in }
            )
            keyboardPanels[id] = panel
        }
        let special: [(String, UInt16, Double)] = [
            ("Esc", 53, 54), ("Tab", 48, 54), ("Caps", 57, 70), ("Ctrl", 59, 60),
            ("⌥", 58, 60), ("⌘", 55, 60), ("⇧", 56, 80), ("Space", 49, 220),
            ("⌫", 51, 74), ("↩", 36, 74)
        ]
        let specialGap = gap
        let specialWidth = special.reduce(0) { $0 + $1.2 } + Double(special.count - 1) * specialGap
        var specialX = frame.midX - specialWidth / 2
        for item in special {
            let id = UUID()
            let config = WidgetConfig(
                id: id,
                geometry: .init(x: specialX, y: rowY, width: item.2, height: keyHeight),
                label: item.0, action: .init(.init(keyCode: item.1)),
                mode: [55, 56, 58, 59].contains(item.1) ? .toggle : .hold, opacity: 0.88
            )
            keyboardConfigs[id] = config
            let panel = WidgetPanel(
                config: config,
                onPress: { [weak self] in self?.pressKeyboardKey(config) },
                onRelease: { [weak self] in self?.releaseKeyboardKey(config) },
                onGeometryChanged: { _, _ in },
                onGeometryCommitted: { _, _ in },
                onDelete: {}, onEditBinding: {}, onToggleMode: {}, onToggleCombinationMode: {}, onSelectionChanged: { _ in }
            )
            keyboardPanels[id] = panel
            specialX += item.2 + specialGap
        }
        refreshButtonLabels()
    }

    private func press(_ widget: WidgetConfig) {
        guard !overlayHidden else { return }
        guard recorder == nil else { return }
        guard permissions.isTrusted || permissions.requestIfNeeded() else { return }
        if widget.mode == .timedToggle {
            manager.handlePress(owner: widget.id, action: widget.action, mode: widget.mode, timedDurationSeconds: widget.timedDurationSeconds)
        } else {
            manager.handlePress(owner: widget.id, action: widget.action, mode: widget.mode)
        }
        panels[widget.id]?.setActive(manager.isActive(owner: widget.id))
        let visibleDuration = widget.mode == .timedToggle ? widget.timedDurationSeconds : nil
        if let visibleDuration {
            DispatchQueue.main.asyncAfter(deadline: .now() + visibleDuration) { [weak self] in
                guard let self, !self.manager.isActive(owner: widget.id) else { return }
                self.panels[widget.id]?.setActive(false)
            }
        }
    }

    private func editButtonPressed() {
        let result = emergency.recordEditClick(at: ProcessInfo.processInfo.systemUptime)
        guard result != .emergency else { return }
        clearInput()
        if overlayHidden {
            overlayHidden = false
            applyOverlayVisibility()
        }
        if keyboardMode { toggleKeyboardMode() }
        editMode.toggle()
        if !editMode { selectedIDs.removeAll() }
        panels.values.forEach { $0.setEditing(editMode) }
        radialPanel?.setEditing(editMode)
        panels.values.forEach { $0.setSelected(selectedIDs.contains($0.widgetID)) }
        editPanel?.setActive(editMode)
    }

    private func selectionChanged(for id: UUID, toggled: Bool) {
        if toggled {
            if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        } else if !selectedIDs.contains(id) {
            selectedIDs = [id]
        }
        panels.values.forEach { $0.setSelected(selectedIDs.contains($0.widgetID)) }
    }

    private func beginEditGesture(id: String, frame: NSRect, handle: ResizeHandle?) {
        cancelEditGesture()
        guard editMode, !overlayHidden, !keyboardMode else { return }
        var originals = [id: OverlayRect(frame)]
        if handle == nil, id != "radial" {
            for otherID in selectedIDs {
                if let panel = panels[otherID], panel.isVisible { originals[otherID.uuidString] = OverlayRect(panel.frame) }
            }
        }
        editGesture = OverlayEditGesture(activeID: id, originals: originals,
                                         mode: handle?.edges(square: id == "radial"),
                                         options: OverlaySnapOptions(grid: snapToGrid, edges: snapToEdges))
        editGestureGeneration = profileGeneration
        editGestureProfileID = profile?.id
        let center = NSPoint(x: frame.midX, y: frame.midY)
        resizeScreen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    private func snapTargets(on screen: NSScreen, excluding ids: Set<String>) -> [OverlaySnapTarget] {
        var targets = [OverlaySnapTarget(id: "screen", rect: OverlayRect(screen.visibleFrame))]
        for (id, panel) in panels where !ids.contains(id.uuidString) && panel.isVisible && panel.frame.intersects(screen.frame) {
            targets.append(OverlaySnapTarget(id: id.uuidString, rect: OverlayRect(panel.frame)))
        }
        if !ids.contains("radial"), let panel = radialPanel, panel.isVisible, panel.frame.intersects(screen.frame) {
            targets.append(OverlaySnapTarget(id: "radial", rect: OverlayRect(panel.frame)))
        }
        return targets
    }

    private func applyEditFrames(_ frames: [String: OverlayRect]) {
        for (id, rect) in frames {
            if id == "radial" { radialPanel?.applyEditorFrame(rect.nsRect) }
            else if let uuid = UUID(uuidString: id) { panels[uuid]?.setFrame(rect.nsRect, display: true) }
        }
    }

    private func updateEditGesture(id: String, frame: NSRect) {
        guard editMode, var gesture = editGesture, gesture.activeID == id,
              acceptsPanelCallback(profileID: editGestureProfileID, generation: editGestureGeneration) else { return }
        let screen = gesture.mode == nil
            ? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? resizeScreen
            : resizeScreen
        guard let screen else { return }
        if gesture.mode == nil { resizeScreen = screen }
        let frames = gesture.update(raw: OverlayRect(frame), screenID: String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]),
                                    screen: OverlayRect(screen.visibleFrame),
                                    targets: snapTargets(on: screen, excluding: Set(gesture.originals.keys)))
        editGesture = gesture
        applyEditFrames(frames)
        if id == "radial" { radialPanel?.setSnapFeedback(gesture.snappedEdges) }
        else if let uuid = UUID(uuidString: id) { panels[uuid]?.setSnapFeedback(gesture.snappedEdges) }
    }

    private func clearSnapFeedback() {
        panels.values.forEach { $0.setSnapFeedback(.init()) }
        radialPanel?.setSnapFeedback(.init())
    }

    private func cancelEditGesture() {
        guard var gesture = editGesture else { return }
        editGesture = nil; resizeScreen = nil
        clearSnapFeedback()
        if acceptsPanelCallback(profileID: editGestureProfileID, generation: editGestureGeneration) {
            applyEditFrames(gesture.cancel())
        }
    }

    private func commitEditGesture(id: String) {
        guard var gesture = editGesture, gesture.activeID == id,
              acceptsPanelCallback(profileID: editGestureProfileID, generation: editGestureGeneration), var profile else { return }
        editGesture = nil; resizeScreen = nil
        clearSnapFeedback()
        guard gesture.changed else { return }
        let frames = gesture.finish()
        for (key, rect) in frames {
            let geometry = WidgetGeometry(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            if key == "radial" { profile.radial.geometry = geometry }
            else if let uuid = UUID(uuidString: key), let index = profile.widgets.firstIndex(where: { $0.id == uuid }) {
                profile.widgets[index].geometry = geometry
            }
        }
        do {
            try persistProfile(profile)
            self.profile = profile
            for widget in profile.widgets { configs[widget.id] = widget }
        } catch {
            applyEditFrames(gesture.originals)
            showError(error, operation: L10n.text("Не удалось сохранить расположение. Изменение отменено"))
        }
    }

    private func geometryChanged(for id: UUID, frame: NSRect, isResizing: Bool) {
        updateEditGesture(id: id.uuidString, frame: frame)
    }

    private func geometryCommitted(for id: UUID, frame: NSRect, isResizing: Bool) {
        commitEditGesture(id: id.uuidString)
    }

    private func radialGeometryChanged(_ frame: NSRect, isResizing: Bool, handle: ResizeHandle?) {
        updateEditGesture(id: "radial", frame: frame)
    }

    private func radialGeometryCommitted(_ frame: NSRect, isResizing: Bool, handle: ResizeHandle?) {
        commitEditGesture(id: "radial")
    }

    private func release(_ widget: WidgetConfig) {
        guard widget.mode == .hold else { return }
        manager.handleRelease(owner: widget.id)
        panels[widget.id]?.setActive(manager.isActive(owner: widget.id))
    }

    private func pressKeyboardKey(_ widget: WidgetConfig) {
        guard keyboardMode, widget.mode == .hold else { return }
        press(widget)
        keyboardPanels[widget.id]?.setActive(manager.isActive(owner: widget.id))
    }

    private func releaseKeyboardKey(_ widget: WidgetConfig) {
        guard keyboardMode else { return }
        if widget.mode == .toggle || widget.mode == .timedToggle { press(widget) } else { release(widget) }
        keyboardPanels[widget.id]?.setActive(manager.isActive(owner: widget.id))
    }

    private func installMonitors() {
        refreshPermissions()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                self.clearInput()
                if notification.name == NSWorkspace.didActivateApplicationNotification {
                    self.handleApplicationActivation(notification)
                } else if notification.name == NSWorkspace.didTerminateApplicationNotification {
                    self.handleApplicationTermination(notification)
                }
            })
        }
        var permissionWasTrusted = permissions.isTrusted
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let isTrusted = self.permissions.isTrusted
            if permissionWasTrusted && !isTrusted { self.clearInput() }
            permissionWasTrusted = isTrusted
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.releaseAllHoldInputs()
            if event.type == .leftMouseUp {
                self?.radialPanel?.finishMouseTracking()
                self?.radialEngine?.releaseAll()
            }
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.releaseAllHoldInputs()
            if event.type == .leftMouseUp {
                self?.radialPanel?.finishMouseTracking()
                self?.radialEngine?.releaseAll()
            }
            return event
        }
    }

    private func restoreOverlayWindows() {
        applyOverlayVisibility()
    }

    private func handleApplicationActivation(_ notification: Notification) {
        restoreOverlayWindows()
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication ?? NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        guard let preferences = profilePreferences else { return }
        lastExternalBundleIdentifier = app.bundleIdentifier
        if let destination = activationState.activate(bundle: app.bundleIdentifier, isOwnApplication: false,
                automatic: preferences.autoSelectByBundleIdentifier, profiles: profileCatalog,
                defaultID: preferences.defaultProfileID), destination != profile?.id {
            selectProfile(id: destination, manual: false)
        }
    }

    private func handleApplicationTermination(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundle = app.bundleIdentifier, bundle == lastExternalBundleIdentifier else { return }
        lastExternalBundleIdentifier = nil
        activationState.clearOverride()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               frontmost != Bundle.main.bundleIdentifier {
                self.handleExternalBundleActivation(frontmost)
            } else if self.profilePreferences?.autoSelectByBundleIdentifier == true,
                      let defaultID = self.profilePreferences?.defaultProfileID {
                self.selectProfile(id: defaultID, manual: false)
            }
        }
    }

    private func handleExternalBundleActivation(_ bundle: String) {
        lastExternalBundleIdentifier = bundle
        guard let preferences = profilePreferences else { return }
        if let destination = activationState.activate(bundle: bundle, isOwnApplication: false,
                automatic: preferences.autoSelectByBundleIdentifier, profiles: profileCatalog,
                defaultID: preferences.defaultProfileID), destination != profile?.id {
            selectProfile(id: destination, manual: false)
        }
    }

    func refreshPermissions() {
        permissions.requestIfNeeded()
        if !escapeTap.isRunning { escapeTap.stop() }
        escapeTap.start { [weak self] isAutoRepeat in
            guard let self else { return false }
            let result = self.emergency.recordEscapeKeyDown(at: ProcessInfo.processInfo.systemUptime, isAutoRepeat: isAutoRepeat)
            return result == .emergency
        }
    }

    private func removeMonitors() {
        escapeTap.stop()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        globalMouseMonitor = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func releaseAllHoldInputs() {
        for widget in configs.values where widget.mode == .hold { manager.handleRelease(owner: widget.id) }
        for widget in keyboardConfigs.values where widget.mode == .hold { manager.handleRelease(owner: widget.id) }
        for widget in keyboardConfigs.values { keyboardPanels[widget.id]?.setActive(manager.isActive(owner: widget.id)) }
        for widget in configs.values where widget.macro == nil { panels[widget.id]?.setActive(manager.isActive(owner: widget.id)) }
    }

    func beginAddButton() {
        guard recorder == nil else { return }
        clearInput()
        let generation = profileGeneration
        let window = MouseKeyPickerWindow(
            language: buttonLanguage,
            onPick: { [weak self] action, label in
                guard self?.profileGeneration == generation else { return }
                self?.recorder = nil
                self?.addButton(action: action, label: label)
            },
            onDrag: { [weak self] action, label, point in
                guard self?.profileGeneration == generation else { return }
                self?.recorder = nil
                self?.addButton(action: action, label: label, at: point)
            },
            onCancel: { [weak self] in if self?.profileGeneration == generation { self?.recorder = nil } }
        )
        recorder = window
        window.start()
    }

    func beginAddMacroButton() {
        guard macroEditorWindow == nil, profile != nil else { return }
        clearInput()
        let generation = profileGeneration
        let editor = MacroEditorWindow(language: buttonLanguage, onChooseKey: { [weak self] completion in
            guard let self, self.recorder == nil else { return }
            let picker = MouseKeyPickerWindow(title: L10n.text("Выберите клавишу макроса"), language: self.buttonLanguage,
                onPick: { [weak self] action, label in
                    self?.recorder = nil
                    completion(action, label)
                }, onCancel: { [weak self] in self?.recorder = nil })
            self.recorder = picker
            picker.start()
        }, onSave: { [weak self] label, macro in
            guard let self, self.profileGeneration == generation else { return false }
            guard self.addMacroButton(label: label, macro: macro) else { return false }
            self.macroEditorWindow = nil
            return true
        }, onCancel: { [weak self] in
            if self?.profileGeneration == generation { self?.macroEditorWindow = nil }
        })
        macroEditorWindow = editor
        editor.start()
    }

    private func beginEditMacroButton(_ id: UUID) {
        guard editMode, macroEditorWindow == nil, let config = configs[id], let macro = config.macro else { return }
        clearInput()
        let generation = profileGeneration
        let editor = MacroEditorWindow(language: buttonLanguage, label: config.label, macro: macro, onChooseKey: { [weak self] completion in
            guard let self, self.recorder == nil else { return }
            let picker = MouseKeyPickerWindow(title: L10n.text("Выберите клавишу макроса"), language: self.buttonLanguage,
                onPick: { [weak self] action, label in self?.recorder = nil; completion(action, label) },
                onCancel: { [weak self] in self?.recorder = nil })
            self.recorder = picker; picker.start()
        }, onSave: { [weak self] label, updated in
            guard let self, self.profileGeneration == generation else { return false }
            guard self.updateMacroButton(id: id, label: label, macro: updated) else { return false }
            self.macroEditorWindow = nil
            return true
        }, onCancel: { [weak self] in
            if self?.profileGeneration == generation { self?.macroEditorWindow = nil }
        })
        macroEditorWindow = editor; editor.start()
    }

    private func updateMacroButton(id: UUID, label: String, macro: MacroDefinition) -> Bool {
        guard var profile, var config = configs[id], let index = profile.widgets.firstIndex(where: { $0.id == id }) else { return false }
        config.label = label; config.macro = macro; profile.widgets[index] = config
        do {
            try persistProfile(profile); self.profile = profile; configs[id] = config
            panels[id]?.update(config: config); refreshButtonLabels()
            return true
        } catch { showError(error, operation: L10n.text("Не удалось сохранить макрос")); return false }
    }

    private func beginEditButton(_ id: UUID) {
        guard editMode, recorder == nil, let config = configs[id] else { return }
        clearInput()
        let generation = profileGeneration
        let window = MouseKeyPickerWindow(
            title: L10n.format("Edit Button “%@”", config.label),
            language: buttonLanguage,
            onPick: { [weak self] action, label in
                guard self?.profileGeneration == generation else { return }
                self?.recorder = nil
                self?.updateButton(id: id, action: action, label: label)
            },
            onCancel: { [weak self] in if self?.profileGeneration == generation { self?.recorder = nil } }
        )
        recorder = window
        window.start()
    }

    private func updateButton(id: UUID, action: KeyAction, label: String) {
        guard var profile, var config = configs[id], let index = profile.widgets.firstIndex(where: { $0.id == id }) else { return }
        manager.handleRelease(owner: id)
        config.action = action
        config.label = label
        profile.widgets[index] = config
        do {
            try persistProfile(profile)
            self.profile = profile
            configs[id] = config
            panels[id]?.update(config: config)
            refreshButtonLabels()
        } catch {
            NSLog("OverSlay profile edit error: %@", String(describing: error))
        }
    }

    private func toggleMode(for id: UUID) {
        guard editMode, var profile, var config = configs[id], let index = profile.widgets.firstIndex(where: { $0.id == id }) else { return }
        manager.handleRelease(owner: id)
        config.mode = config.mode == .hold ? .toggle : .hold
        profile.widgets[index] = config
        do {
            try persistProfile(profile)
            self.profile = profile
            configs[id] = config
            panels[id]?.update(config: config)
            panels[id]?.setActive(false)
            refreshButtonLabels()
        } catch {
            NSLog("OverSlay profile mode error: %@", String(describing: error))
        }
    }

    private func showProperties(for id: UUID) {
        guard editMode, let config = configs[id] else { return }
        propertiesWindow?.close()
        let generation = profileGeneration
        let window = WidgetPropertiesWindow(title: L10n.format("Button Properties “%@”", config.label), mode: config.macro == nil ? config.mode : nil, opacity: config.opacity, durationSeconds: config.timedDurationSeconds, appearance: config.appearance, onSave: { [weak self] mode, opacity, duration, appearance in
            guard let self, self.profileGeneration == generation else { return L10n.text("Активный профиль изменился. Черновик оставлен в окне.") }
            let error = self.updateButtonProperties(id: id, mode: mode ?? .hold, opacity: opacity, duration: duration, appearance: appearance)
            if error == nil { self.propertiesWindow = nil }
            return error
        }, onCancel: { [weak self] in if self?.profileGeneration == generation { self?.propertiesWindow = nil } })
        propertiesWindow = window
        window.start()
    }

    private func showRadialProperties() {
        guard editMode, let current = profile?.radial else { return }
        propertiesWindow?.close()
        let generation = profileGeneration
        let window = RadialPropertiesWindow(config: current, analogAvailable: analogSink.isAvailable, sideInputAvailable: sideInputTap.isRunning, language: buttonLanguage, onSave: { [weak self] radial in
            guard let self, self.profileGeneration == generation, var profile = self.profile else { return }
            self.clearInput()
            profile.radial = radial
            do { try self.persistProfile(profile); self.profile = profile; self.radialPanel?.update(config: radial); self.sideInputTap.update(config: radial) }
            catch { NSLog("OverSlay radial properties error: %@", String(describing: error)) }
            self.propertiesWindow = nil
        }, onCancel: { [weak self] in if self?.profileGeneration == generation { self?.propertiesWindow = nil } })
        propertiesWindow = window
        window.start()
    }

    private func updateButtonProperties(id: UUID, mode: TriggerMode, opacity: Double, duration: Double, appearance: ButtonAppearance) -> String? {
        guard editMode, var profile, var config = configs[id], let index = profile.widgets.firstIndex(where: { $0.id == id }) else { return L10n.text("Кнопка или профиль больше не доступны.") }
        manager.handleRelease(owner: id)
        config.mode = mode; config.opacity = min(max(opacity, 0.1), 1); config.timedDurationSeconds = min(max(duration, 0.1), 3600); config.appearance = appearance
        profile.widgets[index] = config
        do { try persistProfile(profile); self.profile = profile; configs[id] = config; panels[id]?.update(config: config); panels[id]?.setActive(false); refreshButtonLabels(); return nil }
        catch { NSLog("OverSlay widget properties save error: %@", String(describing: error)); return error.localizedDescription }
    }

    private func toggleCombinationMode(for id: UUID) {
        guard editMode, var profile, var config = configs[id], config.action.bindings.count > 1,
              let index = profile.widgets.firstIndex(where: { $0.id == id }) else { return }
        manager.handleRelease(owner: id)
        let nextMode: CombinationMode = config.action.combinationMode == .simultaneous ? .sequential : .simultaneous
        config.action = KeyAction(bindings: config.action.bindings, combinationMode: nextMode)
        profile.widgets[index] = config
        do {
            try persistProfile(profile)
            self.profile = profile
            configs[id] = config
            panels[id]?.update(config: config)
            panels[id]?.setActive(false)
            refreshButtonLabels()
        } catch {
            NSLog("OverSlay profile combination mode error: %@", String(describing: error))
        }
    }

    private func addButton(action: KeyAction, label: String, at dropPoint: NSPoint? = nil) {
        guard var profile, let screen = dropPoint.flatMap({ point in NSScreen.screens.first { $0.frame.contains(point) } }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let center = dropPoint ?? NSPoint(x: frame.midX, y: frame.midY)
        var snapSession = OverlaySnapSession()
        let rect = snapSession.snap(OverlayRect(x: center.x - 40, y: center.y - 30, width: 80, height: 60),
                                    gridOrigin: (frame.minX, frame.minY), targets: snapTargets(on: screen, excluding: []),
                                    options: OverlaySnapOptions(grid: snapToGrid, edges: snapToEdges))
        let geometry = WidgetGeometry(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        let widget = WidgetConfig(geometry: geometry, label: label, action: action, mode: .hold)
        profile.widgets.append(widget)
        do {
            try persistProfile(profile)
            self.profile = profile
            configs[widget.id] = widget
            createPanels([widget])
            panels[widget.id]?.setEditing(editMode)
            panels[widget.id]?.setSelected(selectedIDs.contains(widget.id))
            refreshButtonLabels()
        } catch {
            NSLog("OverSlay profile add error: %@", String(describing: error))
        }
    }

    private func addMacroButton(label: String, macro: MacroDefinition) -> Bool {
        guard var profile else { return false }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return false }
        let frame = screen.visibleFrame
        var snap = OverlaySnapSession()
        let rect = snap.snap(OverlayRect(x: frame.midX - 55, y: frame.midY - 30, width: 110, height: 60),
                             gridOrigin: (frame.minX, frame.minY), targets: snapTargets(on: screen, excluding: []),
                             options: OverlaySnapOptions(grid: snapToGrid, edges: snapToEdges))
        let config = WidgetConfig(geometry: .init(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
                                  label: label, action: KeyAction(bindings: []), mode: .hold, macro: macro)
        profile.widgets.append(config)
        do {
            try persistProfile(profile); self.profile = profile; configs[config.id] = config
            createPanels([config]); panels[config.id]?.setEditing(editMode); refreshButtonLabels(); return true
        } catch { showError(error, operation: L10n.text("Не удалось добавить кастомную кнопку")); return false }
    }

    private func deleteButton(_ id: UUID) {
        guard editMode, configs.count > 1, var profile else { return }
        manager.handleRelease(owner: id)
        selectedIDs.remove(id)
        profile.widgets.removeAll { $0.id == id }
        do {
            try persistProfile(profile)
            self.profile = profile
            panels[id]?.orderOut(nil)
            panels.removeValue(forKey: id)
            configs.removeValue(forKey: id)
            panels.values.forEach { $0.setSelected(selectedIDs.contains($0.widgetID)) }
        } catch {
            NSLog("OverSlay profile delete error: %@", String(describing: error))
        }
    }
}
