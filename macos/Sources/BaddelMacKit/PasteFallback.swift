import AppKit
import BaddelCore

/// Last-resort writer for apps that ignore Accessibility text writes: pastes
/// over a selection the caller has already verified, then puts the user's
/// clipboard back. Off unless the user enables it.
public final class PasteFallback {
    public init() {}

    private struct SavedItem {
        let contents: [(NSPasteboard.PasteboardType, Data)]
    }

    /// - Parameters:
    ///   - confirm: called immediately before Cmd+V is posted. If it returns
    ///     `false` (focus moved, text changed), nothing is pasted, the
    ///     clipboard is restored and `.focusChanged` is thrown.
    ///   - wait: called after Cmd+V is posted; should block until the paste
    ///     has landed or a timeout passes.
    public func paste(_ text: String, confirm: () -> Bool, wait: () -> Void) throws {
        let pasteboard = NSPasteboard.general
        let saved: [SavedItem] = (pasteboard.pasteboardItems ?? []).map { item in
            SavedItem(contents: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Ask clipboard managers not to record this transient entry.
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.writeObjects([item])
        let ourChange = pasteboard.changeCount

        defer {
            // Restore only if nothing else has written to the clipboard since.
            if pasteboard.changeCount == ourChange {
                pasteboard.clearContents()
                let items: [NSPasteboardItem] = saved.map { savedItem in
                    let restored = NSPasteboardItem()
                    for (type, data) in savedItem.contents { restored.setData(data, forType: type) }
                    return restored
                }
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
        }

        let source = CGEventSource(stateID: .privateState)
        let keyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { throw Rejection.writeFailed }
        guard confirm() else { throw Rejection.focusChanged }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        wait()
    }
}
