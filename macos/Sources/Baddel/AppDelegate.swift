import AppKit
import BaddelCore
import BaddelMacKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let hotKeys = HotKeyCenter()
    private var coordinator: CorrectionCoordinator?
    private var statusItem: NSStatusItem?
    private lazy var permissionWindow = PermissionWindowController()
    private lazy var preferencesWindow = PreferencesWindowController()

    private let shortcutItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let accessItem = NSMenuItem(title: "", action: #selector(showPermission), keyEquivalent: "")
    private let undoItem = NSMenuItem(title: "Undo Last Correction", action: #selector(undoLast), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store: LayoutStore
        do {
            store = try BaddelResources.loadLayouts()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Baddel can't find its keyboard layout data."
            alert.informativeText = "Reinstall the app, or set BADDEL_LAYOUTS_DIR to the shared/layouts folder."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let coordinator = CorrectionCoordinator(store: store, settings: settings)
        coordinator.onNeedsPermission = { [weak self] in self?.showPermission() }
        coordinator.onUndoAvailabilityChanged = { [weak self] available in self?.undoItem.isEnabled = available }
        self.coordinator = coordinator

        hotKeys.onPress = { [weak coordinator] isRepeat in coordinator?.hotKeyPressed(isRepeat: isRepeat) }
        hotKeys.onRelease = { [weak coordinator] in coordinator?.hotKeyReleased() }
        hotKeys.register(settings.shortcut)

        buildMenu()
        if !AccessibilityPermission.isGranted { showPermission() }
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Baddel") {
            item.button?.image = image
        } else {
            item.button?.title = "بدّل"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        shortcutItem.isEnabled = false
        accessItem.target = self
        undoItem.target = self
        undoItem.isEnabled = false
        menu.addItem(shortcutItem)
        menu.addItem(accessItem)
        menu.addItem(.separator())
        menu.addItem(undoItem)
        menu.addItem(.separator())
        let preferences = NSMenuItem(title: "Settings…", action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        let about = NSMenuItem(title: "About Baddel", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit Baddel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        menuNeedsUpdate(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        shortcutItem.title = hotKeys.isRegistered
            ? "Fix text: \(settings.shortcut.displayString)  (press twice for the whole field)"
            : "Shortcut \(settings.shortcut.displayString) is unavailable — choose another in Settings"
        accessItem.title = AccessibilityPermission.isGranted
            ? "Accessibility access: granted"
            : "Grant Accessibility Access…"
    }

    @objc private func showPermission() {
        permissionWindow.present()
    }

    @objc private func showPreferences() {
        preferencesWindow.applyShortcut = { [weak self] shortcut in self?.hotKeys.register(shortcut) ?? false }
        preferencesWindow.suspendHotKey = { [weak self] suspended in
            guard let self else { return }
            // While recording, the current shortcut must reach the recorder.
            if suspended { self.hotKeys.unregister() } else if !self.hotKeys.isRegistered {
                self.hotKeys.register(self.settings.shortcut)
            }
        }
        preferencesWindow.onSettingsChanged = { [weak self] in self?.coordinator?.settingsChanged() }
        preferencesWindow.present()
    }

    /// The standard About panel, with the copyright and license notice.
    @objc private func showAbout() {
        let credits = NSAttributedString(
            string: """
                Fixes text typed with the wrong keyboard layout (Arabic / English).

                Released under the MIT License. The full license text is in the LICENSE file \
                distributed with this app. Copies and forks that redistribute Baddel must keep \
                this copyright notice and the license notice.

                \(AppInfo.projectURL)
                """,
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Baddel",
            .applicationVersion: AppInfo.version,
            .version: "",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): AppInfo.copyright,
        ])
    }

    @objc private func undoLast() {
        coordinator?.undoLast()
    }
}

enum AppInfo {
    static let copyright = "Copyright (c) 2026 Mahmood"
    static let projectURL = "https://github.com/Mahmood83367/baddel"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }
}
