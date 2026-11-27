import AppKit

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
    private let intervalField = NSTextField(labelWithString: "")
    private let intervalStepper = NSStepper()
    private let switchCheckbox = NSButton(checkboxWithTitle: "Switch the keyboard layout after a correction", target: nil, action: nil)
    private let pasteCheckbox = NSButton(checkboxWithTitle: "Paste fallback for apps that refuse direct edits (experimental)", target: nil, action: nil)

    /// Re-registers the hot key; returns whether the system accepted it.
    var applyShortcut: ((Shortcut) -> Bool)?
    var suspendHotKey: ((Bool) -> Void)?
    var onSettingsChanged: (() -> Void)?

    private static let arabicChoices: [(title: String, id: String?)] = [
        ("Automatic (from enabled input sources)", nil),
        ("Arabic (macOS)", "arabic-mac"),
        ("Arabic – PC", "arabic-pc"),
    ]

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
        for checkbox in [switchCheckbox, pasteCheckbox] {
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
            [NSTextField(labelWithString: "Double-press window:"), interval],
            [NSGridCell.emptyContentView, switchCheckbox],
            [NSGridCell.emptyContentView, pasteCheckbox],
            [NSGridCell.emptyContentView, pasteNote],
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
        settings.doublePressMs = intervalStepper.integerValue
        settings.switchesLayout = switchCheckbox.state == .on
        settings.pasteFallbackEnabled = pasteCheckbox.state == .on
        updateIntervalLabel()
        onSettingsChanged?()
    }
}
