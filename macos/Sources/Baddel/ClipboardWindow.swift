import AppKit
import BaddelMacKit

final class ClipboardWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let history: ClipboardHistory
    private let search = NSSearchField()
    private let table = NSTableView()
    private let preview = NSImageView()
    private let recordButton = NSButton(checkboxWithTitle: "Keep clipboard history on this Mac", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let pinButton = NSButton(title: "Keep File Copy…", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete…", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear Recent…", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private var results: [ClipboardEntry] = []

    init(history: ClipboardHistory) {
        self.history = history
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 405),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Clipboard History"
        window.minSize = NSSize(width: 600, height: 370)
        window.isReleasedWhenClosed = false
        super.init(window: window)

        search.placeholderString = "Search copied text and file names"
        search.delegate = self
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clipboard")))
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.rowHeight = 30
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(copySelected)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table

        preview.imageScaling = .scaleProportionallyDown
        preview.imageAlignment = .alignCenter
        preview.setAccessibilityLabel("Image preview")
        preview.heightAnchor.constraint(equalToConstant: 105).isActive = true
        preview.isHidden = true

        let handlers: [(NSButton, Selector)] = [
            (recordButton, #selector(recordingChanged)),
            (copyButton, #selector(copySelected)),
            (pinButton, #selector(pinSelected)),
            (deleteButton, #selector(deleteSelected)),
            (clearButton, #selector(clearRecent)),
        ]
        for (button, action) in handlers {
            button.target = self
            button.action = action
        }
        recordButton.state = Self.recordsHistory ? .on : .off
        copyButton.keyEquivalent = "\r"
        status.textColor = .secondaryLabelColor

        let buttons = NSStackView(views: [copyButton, pinButton, deleteButton, clearButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [recordButton, search, scroll, preview, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window.center()
        history.onChange = { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { return nil }

    static var recordsHistory: Bool {
        get { UserDefaults.standard.bool(forKey: "recordsClipboardHistory") }
        set { UserDefaults.standard.set(newValue, forKey: "recordsClipboardHistory") }
    }

    func present() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(search)
    }

    private var selected: ClipboardEntry? {
        let row = table.selectedRow
        return results.indices.contains(row) ? results[row] : nil
    }

    private func reload() {
        let oldSelection = selected?.id
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        results = history.entries.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
        table.reloadData()
        if let index = results.firstIndex(where: { $0.id == oldSelection }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !results.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        let count = results.count
        if history.entries.isEmpty {
            status.stringValue = Self.recordsHistory ? "Copy something to start the history." : "Turn on clipboard history to start saving new copies."
        } else {
            status.stringValue = count == 1 ? "1 item" : "\(count) items"
        }
        refreshButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = results[row]
        let title = String(entry.title.prefix(160))
        let text = NSTextField(labelWithString: entry.isPinned ? "Pinned · \(title)" : title)
        text.lineBreakMode = .byTruncatingTail
        return text
    }

    func tableViewSelectionDidChange(_ notification: Notification) { refreshButtons() }

    func controlTextDidChange(_ notification: Notification) { reload() }

    private func refreshButtons() {
        let entry = selected
        copyButton.isEnabled = entry != nil
        deleteButton.isEnabled = entry != nil
        clearButton.isEnabled = history.entries.contains { !$0.isPinned }
        if let entry, case .files(_, nil) = entry.content {
            pinButton.isEnabled = true
        } else {
            pinButton.isEnabled = false
        }
        preview.image = entry.flatMap { history.image(for: $0) }
        preview.isHidden = preview.image == nil
    }

    @objc private func recordingChanged() {
        Self.recordsHistory = recordButton.state == .on
        history.setRecording(Self.recordsHistory)
        reload()
    }

    @objc private func copySelected() {
        guard let item = selected else { return }
        do {
            try history.restore(item)
            window?.orderOut(nil)
        } catch { show(error) }
    }

    @objc private func pinSelected() {
        guard let item = selected,
              confirm("Keep a copy of these files?", "Baddel will save a separate copy on this Mac.", button: "Keep Copy") else { return }
        do { try history.pin(item) }
        catch { show(error) }
    }

    @objc private func deleteSelected() {
        guard let item = selected,
              confirm("Delete this item?", "Baddel will remove this item from its clipboard history.", button: "Delete") else { return }
        do { try history.remove(item) }
        catch { show(error) }
    }

    @objc private func clearRecent() {
        guard confirm("Clear recent clipboard history?", "This deletes the recent copies stored by Baddel.", button: "Clear Recent") else { return }
        do { try history.clearRecent() }
        catch { show(error) }
    }

    private func confirm(_ title: String, _ description: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = description
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: button)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
