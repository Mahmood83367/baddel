import AppKit
import BaddelMacKit

/// Explains why Accessibility access is needed and lets the user grant it in
/// System Settings. Baddel never changes the setting itself.
final class PermissionWindowController: NSWindowController {
    private let status = NSTextField(labelWithString: "")
    private var poll: Timer?
    var onGranted: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Baddel needs Accessibility access"
        window.isReleasedWhenClosed = false
        self.init(window: window)

        let heading = NSTextField(labelWithString: "Allow Baddel to fix text in other apps")
        heading.font = .systemFont(ofSize: 16, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: """
            Baddel uses the macOS Accessibility API to read the selected text or the word before the caret \
            in the field you are typing in, and to replace it with the corrected text when you press the \
            shortcut.

            • Everything happens on this Mac. Nothing is sent anywhere.
            • Baddel does not record keystrokes. It only acts when you press its shortcut.
            • Password fields are always skipped.

            To continue, enable Baddel in System Settings → Privacy & Security → Accessibility.
            """)
        body.preferredMaxLayoutWidth = 430

        let prompt = NSButton(title: "Request Access…", target: self, action: #selector(requestAccess))
        prompt.keyEquivalent = "\r"
        let open = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openSettings))
        let buttons = NSStackView(views: [prompt, open])
        buttons.spacing = 10

        let stack = NSStackView(views: [heading, body, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
    }

    func present() {
        refresh()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        if AccessibilityPermission.isGranted {
            status.stringValue = "✓ Accessibility access is granted. You can close this window."
            status.textColor = .systemGreen
            if poll != nil {
                poll?.invalidate()
                poll = nil
                onGranted?()
            }
        } else {
            status.stringValue = "Accessibility access is not granted yet."
            status.textColor = .secondaryLabelColor
        }
    }

    /// Shows the system's own permission dialog. The user decides.
    @objc private func requestAccess() {
        AccessibilityPermission.requestSystemPrompt()
    }

    @objc private func openSettings() {
        NSWorkspace.shared.open(AccessibilityPermission.settingsURL)
    }
}
