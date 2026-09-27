import AppKit
import OverSlayCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var overlay: OverlayController?
    private var diagnosticsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlay = OverlayController()
        self.overlay = overlay
        overlay.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "OverSlay"
        let menu = NSMenu()
        let diagnostics = NSMenuItem(title: L10n.text("Диагностика и разрешения"), action: #selector(showDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)
        let permissions = NSMenuItem(title: L10n.text("Обновить разрешения"), action: #selector(refreshPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        let reset = NSMenuItem(title: L10n.text("Аварийный сброс"), action: #selector(resetInput), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        let addButton = NSMenuItem(title: L10n.text("Добавить кнопку…"), action: #selector(addButton), keyEquivalent: "")
        addButton.target = self
        menu.addItem(addButton)
        let addMacro = NSMenuItem(title: L10n.text("Добавить кастомную кнопку…"), action: #selector(addMacroButton), keyEquivalent: "")
        addMacro.target = self
        menu.addItem(addMacro)
        let profiles = NSMenuItem(title: L10n.text("Профили…"), action: #selector(showProfiles), keyEquivalent: "")
        profiles.target = self
        menu.addItem(profiles)
        let editorSettings = NSMenuItem(title: L10n.text("Настройки редактора…"), action: #selector(showEditorSettings), keyEquivalent: "")
        editorSettings.target = self
        menu.addItem(editorSettings)
        let toggleLanguage = NSMenuItem(title: L10n.text("Переключить язык кнопок"), action: #selector(toggleLanguage), keyEquivalent: "")
        toggleLanguage.target = self
        menu.addItem(toggleLanguage)
        let exportProfile = NSMenuItem(title: L10n.text("Экспортировать профиль…"), action: #selector(exportProfile), keyEquivalent: "")
        exportProfile.target = self
        menu.addItem(exportProfile)
        let importProfile = NSMenuItem(title: L10n.text("Импортировать профиль…"), action: #selector(importProfile), keyEquivalent: "")
        importProfile.target = self
        menu.addItem(importProfile)
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("Выйти"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showDiagnostics() {
        guard let overlay else { return }
        overlay.clearInput()
        if diagnosticsWindow == nil {
            let panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            panel.title = L10n.text("OverSlay — диагностика")
            panel.isReleasedWhenClosed = false
            let text = NSTextView(frame: .zero)
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.string = overlay.diagnosticsText()
            panel.contentView = text
            panel.center()
            diagnosticsWindow = panel
        }
        if let text = diagnosticsWindow?.contentView as? NSTextView { text.string = overlay.diagnosticsText() }
        diagnosticsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func resetInput() { overlay?.emergencyReset() }
    @objc private func refreshPermissions() { overlay?.clearInput(); overlay?.refreshPermissions() }

    @objc private func addButton() { overlay?.beginAddButton() }
    @objc private func addMacroButton() { overlay?.beginAddMacroButton() }
    @objc private func showProfiles() { overlay?.openProfileManager() }
    @objc private func showEditorSettings() { overlay?.openEditorSettings() }
    @objc private func toggleLanguage() { overlay?.toggleButtonLanguage() }

    @objc private func exportProfile() {
        guard let overlay else { return }
        overlay.clearInput()
        let panel = NSSavePanel()
        panel.title = L10n.text("Экспортировать профиль OverSlay")
        panel.nameFieldStringValue = "overSlay-profile.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        overlay.exportProfile(to: url)
    }

    @objc private func importProfile() {
        guard let overlay else { return }
        overlay.clearInput()
        let panel = NSOpenPanel()
        panel.title = L10n.text("Импортировать профиль OverSlay")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        overlay.importProfile(from: url)
    }

    func applicationWillTerminate(_ notification: Notification) { overlay?.stop() }
}
