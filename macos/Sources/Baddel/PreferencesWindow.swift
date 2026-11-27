import AppKit
import BaddelCore
import BaddelMacKit

/// A button that records a new shortcut. Key events are observed only while
/// recording, and only when they are delivered to Baddel's own window.
final class ShortcutRecorderButton: NSButton {
    var shortcut: Shortcut = .default { didSet { updateTitle() } }
    var onChange: ((Shortcut) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private var monitor: Any?

    private var isRecording: Bool { monitor != nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func updateTitle() {
        title = isRecording ? "Press a shortcut… (Esc cancels)" : shortcut.displayString
    }

    @objc private func toggleRecording() {
        isRecording ? stop() : start()
    }

    private func start() {
        onRecordingChanged?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {  // Escape
                self.stop()
            } else if let recorded = Shortcut(event: event) {
                self.shortcut = recorded
                self.stop()
                self.onChange?(recorded)
            } else {
                NSSound.beep()
            }
            return nil
        }
        updateTitle()
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        updateTitle()
        onRecordingChanged?(false)
    }
}

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let settings = Settings.shared
    private let recorder = ShortcutRecorderButton(frame: .zero)
    private let shortcutStatus = NSTextField(labelWithString: "")
    private let arabicPopup = NSPopUpButton()
    private let englishPopup = NSPopUpButton()
    private let intervalField = NSTextField(labelWithString: "")
    private let intervalStepper = NSStepper()
    private let switchCheckbox = NSButton(checkboxWithTitle: "Switch the keyboard layout after a correction", target: nil, action: nil)
    private let pasteCheckbox = NSButton(checkboxWithTitle: "Paste fallback for apps that refuse direct edits (experimental)", target: nil, action: nil)

    /// Re-registers the hot key; returns whether the system accepted it.
    var applyShortcut: ((Shortcut) -> Bool)?
    var suspendHotKey: ((Bool) -> Void)?
    var onSettingsChanged: (() -> Void)?

    /// Valid user-supplied layouts, set by the app delegate before the window is created.
    static var customLayouts: [KeyboardLayout] = []

    private static func choices(_ builtIn: [(title: String, id: String?)], script: Script) -> [(title: String, id: String?)] {
        builtIn + customLayouts.filter { $0.script == script }
            .sorted { $0.id < $1.id }
            .map { (title: "\($0.name) (custom)", id: Optional($0.id)) }
    }

    private static var englishChoices: [(title: String, id: String?)] {
        choices([
            ("Automatic (from enabled input sources)", nil),
            ("US English / ABC", "us-english"),
            ("British English", "uk-english-mac"),
        ], script: .latin)
    }

    private static var arabicChoices: [(title: String, id: String?)] {
        choices([
            ("Automatic (from enabled input sources)", nil),
            ("Arabic (macOS)", "arabic-mac"),
            ("Arabic – PC", "arabic-pc"),
        ], script: .arabic)
    }

    private let loginCheckbox = NSButton(checkboxWithTitle: "Open Baddel at login", target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let channelPopup = NSPopUpButton()
    private let autoCheckCheckbox = NSButton(
        checkboxWithTitle: "Check for updates once a day (never downloads or installs)", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Baddel Settings"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self

        recorder.shortcut = settings.shortcut
        recorder.onChange = { [weak self] shortcut in self?.shortcutRecorded(shortcut) }
        recorder.onRecordingChanged = { [weak self] recording in self?.suspendHotKey?(recording) }
        shortcutStatus.textColor = .secondaryLabelColor
        shortcutStatus.stringValue = "Press once: selection or last word. Press twice quickly: the whole field."

        for choice in Self.arabicChoices { arabicPopup.addItem(withTitle: choice.title) }
        arabicPopup.selectItem(at: Self.arabicChoices.firstIndex { $0.id == settings.arabicLayoutID } ?? 0)
        arabicPopup.target = self
        arabicPopup.action = #selector(changed)
        for choice in Self.englishChoices { englishPopup.addItem(withTitle: choice.title) }
        englishPopup.selectItem(at: Self.englishChoices.firstIndex { $0.id == settings.englishLayoutID } ?? 0)
        englishPopup.target = self
        englishPopup.action = #selector(changed)

        intervalStepper.minValue = 150
        intervalStepper.maxValue = 600
        intervalStepper.increment = 25
        intervalStepper.integerValue = settings.doublePressMs
        intervalStepper.target = self
        intervalStepper.action = #selector(changed)
        let interval = NSStackView(views: [intervalField, intervalStepper])
        interval.spacing = 6

        switchCheckbox.state = settings.switchesLayout ? .on : .off
        pasteCheckbox.state = settings.pasteFallbackEnabled ? .on : .off
        for channel in UpdateChannel.allCases {
            channelPopup.addItem(withTitle: channel == .stable ? "Stable releases only" : "Stable releases and previews")
        }
        channelPopup.selectItem(at: UpdateChannel.allCases.firstIndex(of: settings.updateChannel) ?? 0)
        channelPopup.target = self
        channelPopup.action = #selector(changed)
        autoCheckCheckbox.state = settings.checksForUpdatesAutomatically ? .on : .off
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginItemChanged)
        loginStatus.textColor = .secondaryLabelColor
        loginStatus.font = .systemFont(ofSize: 11)
        loginStatus.preferredMaxLayoutWidth = 330
        refreshLoginItem()
        for checkbox in [switchCheckbox, pasteCheckbox, autoCheckCheckbox] {
            checkbox.target = self
            checkbox.action = #selector(changed)
        }
        let pasteNote = NSTextField(wrappingLabelWithString:
            "The fallback pastes over a verified selection and then restores your clipboard. It is only used when an app ignores direct edits.")
        pasteNote.textColor = .secondaryLabelColor
        pasteNote.font = .systemFont(ofSize: 11)
        pasteNote.preferredMaxLayoutWidth = 330

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Shortcut:"), recorder],
            [NSGridCell.emptyContentView, shortcutStatus],
            [NSTextField(labelWithString: "Arabic layout:"), arabicPopup],
            [NSTextField(labelWithString: "English layout:"), englishPopup],
            [NSTextField(labelWithString: "Double-press window:"), interval],
            [NSGridCell.emptyContentView, switchCheckbox],
            [NSGridCell.emptyContentView, pasteCheckbox],
            [NSGridCell.emptyContentView, pasteNote],
            [NSTextField(labelWithString: "Startup:"), loginCheckbox],
            [NSGridCell.emptyContentView, loginStatus],
            [NSTextField(labelWithString: "Updates:"), channelPopup],
            [NSGridCell.emptyContentView, autoCheckCheckbox],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
        updateIntervalLabel()
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Shows what macOS reports, so the checkbox never claims more than is true.
    private func refreshLoginItem() {
        let state = LoginItem.state
        loginCheckbox.state = state == .enabled || state == .requiresApproval ? .on : .off
        loginCheckbox.isEnabled = LoginItem.isInstalledCopy || state != .disabled
        switch state {
        case .enabled:
            loginStatus.stringValue = "Baddel opens when you log in. Turn this off here, or in System Settings → General → Login Items."
        case .requiresApproval:
            loginStatus.stringValue = "macOS is waiting for you to allow Baddel in System Settings → General → Login Items."
        case .disabled, .notFound:
            loginStatus.stringValue = LoginItem.isInstalledCopy
                ? "Off. Baddel starts only when you open it."
                : "Available when Baddel is installed in the Applications folder."
        }
    }

    @objc private func loginItemChanged() {
        switch LoginItem.set(loginCheckbox.state == .on) {
        case .success(.requiresApproval):
            LoginItem.openSystemSettings()
        case .success:
            break
        case .failure:
            NSSound.beep()
        }
        refreshLoginItem()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // The user may have changed it in System Settings meanwhile.
        refreshLoginItem()
    }

    func windowWillClose(_ notification: Notification) {
        recorder.stop()
    }

    private func updateIntervalLabel() {
        intervalField.stringValue = "\(intervalStepper.integerValue) ms"
    }

    private func shortcutRecorded(_ shortcut: Shortcut) {
        if applyShortcut?(shortcut) == true {
            settings.shortcut = shortcut
            shortcutStatus.textColor = .secondaryLabelColor
            shortcutStatus.stringValue = "Shortcut set to \(shortcut.displayString)."
        } else {
            // Keep the working shortcut if the system refuses the new one.
            recorder.shortcut = settings.shortcut
            _ = applyShortcut?(settings.shortcut)
            shortcutStatus.textColor = .systemRed
            shortcutStatus.stringValue = "\(shortcut.displayString) is not available. Another app may be using it."
        }
    }

    @objc private func changed() {
        settings.arabicLayoutID = Self.arabicChoices[max(arabicPopup.indexOfSelectedItem, 0)].id
        settings.englishLayoutID = Self.englishChoices[max(englishPopup.indexOfSelectedItem, 0)].id
        settings.doublePressMs = intervalStepper.integerValue
        settings.switchesLayout = switchCheckbox.state == .on
        settings.pasteFallbackEnabled = pasteCheckbox.state == .on
        settings.updateChannel = UpdateChannel.allCases[max(channelPopup.indexOfSelectedItem, 0)]
        settings.checksForUpdatesAutomatically = autoCheckCheckbox.state == .on
        updateIntervalLabel()
        onSettingsChanged?()
    }
}
