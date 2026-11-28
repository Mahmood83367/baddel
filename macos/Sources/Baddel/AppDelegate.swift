import AppKit
import BaddelCore
import BaddelMacKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let hotKeys = HotKeyCenter()
    private let clipboardHotKey = HotKeyCenter(id: 2)
    private let clipboardShortcut = Shortcut(keyCode: 9, carbonModifiers: Shortcut.default.carbonModifiers)
    private var coordinator: CorrectionCoordinator?
    private var statusItem: NSStatusItem?
    private lazy var permissionWindow = PermissionWindowController()
    private lazy var preferencesWindow = PreferencesWindowController()
    private lazy var clipboardHistory: ClipboardHistory = {
        let files = FileManager.default
        let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? files.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return ClipboardHistory(directory: support.appendingPathComponent("Baddel/Clipboard", isDirectory: true))
    }()
    private lazy var clipboardWindow = ClipboardWindowController(history: clipboardHistory)

    private let shortcutItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let accessItem = NSMenuItem(title: "", action: #selector(showPermission), keyEquivalent: "")
    private let undoItem = NSMenuItem(title: "Undo Last Correction", action: #selector(undoLast), keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    private var availableUpdatePage: String?

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
        // The shortcut is shared with terminal apps by letting go of it while
        // one of them is in front. Only the frontmost app's identity is used.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.shareShortcutWithFrontApp() }
        shareShortcutWithFrontApp()
        clipboardHistory.setRecording(ClipboardWindowController.recordsHistory)
        clipboardHotKey.onPress = { [weak self] isRepeat in if !isRepeat { self?.showClipboard() } }
        clipboardHotKey.register(clipboardShortcut)

        PreferencesWindowController.customLayouts = store.layouts.values.filter { $0.id.hasPrefix(LayoutStore.customPrefix) }
        buildMenu()
        if !AccessibilityPermission.isGranted { showPermission() }
        checkAutomaticallyIfDue()
        Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in self?.checkAutomaticallyIfDue() }
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
        let clipboardTitle = clipboardHotKey.isRegistered
            ? "Clipboard History… (\(clipboardShortcut.displayString))" : "Clipboard History…"
        let clipboard = NSMenuItem(title: clipboardTitle, action: #selector(showClipboard), keyEquivalent: "")
        clipboard.target = self
        menu.addItem(clipboard)
        menu.addItem(.separator())
        let preferences = NSMenuItem(title: "Settings…", action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        updateItem.target = self
        menu.addItem(updateItem)
        let about = NSMenuItem(title: "About Baddel", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit Baddel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        menuNeedsUpdate(menu)
    }

    /// Releases the shortcut while a terminal app is frontmost and pass-through
    /// is active, and holds it otherwise.
    private func shareShortcutWithFrontApp() {
        guard !recordingShortcut else { return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let pass = TerminalSharing.isActive(settings: settings) && TerminalSharing.isTerminal(bundleID: front, settings: settings)
        if pass {
            if hotKeys.isRegistered { hotKeys.unregister() }
            passedToTerminal = true
        } else {
            if passedToTerminal || !hotKeys.isRegistered { hotKeys.register(settings.shortcut) }
            passedToTerminal = false
        }
    }

    private var passedToTerminal = false
    private var recordingShortcut = false

    func menuNeedsUpdate(_ menu: NSMenu) {
        shortcutItem.title = hotKeys.isRegistered
            ? "Fix text: \(settings.shortcut.displayString)  (press twice for the whole field)"
            : passedToTerminal
            ? "Fix text: \(settings.shortcut.displayString)  (handled by the terminal in front)"
            : "Shortcut \(settings.shortcut.displayString) is unavailable — choose another in Settings"
        accessItem.title = AccessibilityPermission.isGranted
            ? "Accessibility access: granted"
            : "Grant Accessibility Access…"
    }

    @objc private func showPermission() {
        permissionWindow.present()
    }

    @objc private func showClipboard() {
        clipboardWindow.present()
    }

    @objc private func showPreferences() {
        preferencesWindow.applyShortcut = { [weak self] shortcut in self?.hotKeys.register(shortcut) ?? false }
        preferencesWindow.suspendHotKey = { [weak self] suspended in
            guard let self else { return }
            // While recording, the current shortcut must reach the recorder.
            self.recordingShortcut = suspended
            if suspended { self.hotKeys.unregister() } else if !self.hotKeys.isRegistered {
                self.hotKeys.register(self.settings.shortcut)
            }
        }
        preferencesWindow.onSettingsChanged = { [weak self] in
            self?.coordinator?.settingsChanged()
            self?.shareShortcutWithFrontApp()
        }
        preferencesWindow.present()
    }

    // Updates ---------------------------------------------------------------

    /// Manual check: asks GitHub for the release list and reports the result.
    /// Nothing is downloaded or installed; the release page opens in the browser.
    @objc private func checkForUpdates() {
        if let page = availableUpdatePage, let url = URL(string: page) {
            NSWorkspace.shared.open(url)
            return
        }
        let channel = settings.updateChannel
        UpdateChecker.check(current: AppInfo.version, channel: channel) { [weak self] outcome in
            guard let self else { return }
            let alert = NSAlert()
            switch outcome {
            case .failed:
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = "The release list could not be read. Check your connection and try again."
            case .result(let result):
                self.noteUpdate(result)
                if result.updateAvailable, let latest = result.latest {
                    alert.messageText = "Baddel \(latest) is available"
                    alert.informativeText = "You have \(result.current). Baddel does not install updates itself: "
                        + "open the release page to download it and check its SHA-256."
                    alert.addButton(withTitle: "Open Release Page")
                    alert.addButton(withTitle: "Later")
                } else if let latest = result.latest {
                    alert.messageText = "Baddel is up to date"
                    alert.informativeText = "You have \(result.current). The newest \(channel == .stable ? "stable release" : "release") is \(latest)."
                } else {
                    alert.messageText = "No \(channel == .stable ? "stable release" : "release") yet"
                    alert.informativeText = "You have \(result.current). To hear about previews, choose "
                        + "\"Stable releases and previews\" in Settings."
                }
            }
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn, case .result(let result) = outcome, result.updateAvailable,
               let page = result.releasePage, let url = URL(string: page) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func noteUpdate(_ result: UpdateCheckResult) {
        availableUpdatePage = result.updateAvailable ? result.releasePage : nil
        updateItem.title = result.updateAvailable && result.latest != nil
            ? "Baddel \(result.latest!) is available — open release page"
            : "Check for Updates…"
    }

    /// The opt-in daily check. It only changes the menu item; it shows no window.
    private func checkAutomaticallyIfDue() {
        guard settings.checksForUpdatesAutomatically else { return }
        if let last = settings.lastAutomaticUpdateCheck, Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        settings.lastAutomaticUpdateCheck = Date()
        UpdateChecker.check(current: AppInfo.version, channel: settings.updateChannel) { [weak self] outcome in
            if case .result(let result) = outcome { self?.noteUpdate(result) }
        }
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
