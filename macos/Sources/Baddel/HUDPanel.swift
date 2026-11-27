import AppKit

/// A panel that never becomes key or main and never activates Baddel, so the
/// text field being edited keeps keyboard focus while the panel is clicked.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows a short status message, optionally with an Undo button, near the
/// edited text.
final class HUDController {
    private var panel: NSPanel?
    private var hideTimer: Timer?
    private var action: (() -> Void)?
    var onHide: (() -> Void)?

    /// - Parameters:
    ///   - anchor: rectangle of the edited text or field in Accessibility
    ///     coordinates (origin top-left of the primary display), or `nil` when
    ///     the app reports no coordinates.
    ///   - undo: when set, an Undo button is shown and calls this.
    func show(message: String, anchor: CGRect?, duration: TimeInterval, undo: (() -> Void)? = nil) {
        hide(notify: false)
        action = undo

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor

        let stack = NSStackView(views: [label])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 12, bottom: 7, right: 10)
        if undo != nil {
            let button = FirstClickButton(title: "Undo", target: self, action: #selector(undoClicked))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.setAccessibilityLabel("Undo keyboard layout correction")
            stack.addArrangedSubview(button)
        }

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 9
        background.layer?.masksToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        let size = stack.fittingSize
        let panel = NonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = background
        panel.setFrameOrigin(Self.origin(for: size, anchor: anchor))
        panel.orderFrontRegardless()
        self.panel = panel

        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hide(notify: true)
        }
    }

    func hide(notify: Bool = true) {
        hideTimer?.invalidate()
        hideTimer = nil
        guard panel != nil else { return }
        panel?.orderOut(nil)
        panel = nil
        action = nil
        if notify { onHide?() }
    }

    @objc private func undoClicked() {
        let action = self.action
        hide(notify: false)
        action?()
    }

    /// Places the panel just below the anchor (above it if there is no room),
    /// clamped to the screen. Without a usable anchor it falls back to the
    /// lower middle of the screen that contains the pointer.
    static func origin(for size: NSSize, anchor: CGRect?) -> NSPoint {
        let screens = NSScreen.screens
        if let anchor, let primary = screens.first {
            // Accessibility uses a top-left origin; AppKit uses bottom-left.
            let rect = NSRect(
                x: anchor.minX, y: primary.frame.maxY - anchor.maxY, width: anchor.width, height: anchor.height)
            if let screen = screens.first(where: { $0.frame.intersects(rect) }) {
                let visible = screen.visibleFrame
                var point = NSPoint(x: rect.minX, y: rect.minY - size.height - 6)
                if point.y < visible.minY { point.y = rect.maxY + 6 }
                point.x = min(max(point.x, visible.minX + 4), visible.maxX - size.width - 4)
                point.y = min(max(point.y, visible.minY + 4), visible.maxY - size.height - 4)
                return point
            }
        }
        let mouse = NSEvent.mouseLocation
        let screen = screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 96)
    }
}
