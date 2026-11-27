import ApplicationServices
import BaddelCore
import Foundation

/// A focused text element of another app, edited through Accessibility text
/// ranges (UTF-16 offsets).
public final class AXField: EditableField {
    public let element: AXUIElement
    public let role: String
    public let subrole: String
    /// Optional last-resort writer; `nil` disables the paste fallback.
    public var pasteFallback: PasteFallback?
    /// Which write strategy the last successful `replace` used. A code, not text.
    public private(set) var lastWriteStrategy = "none"

    private static let textRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
    ]

    public init(element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, 1.0)
        role = AX.string(element, kAXRoleAttribute) ?? ""
        subrole = AX.string(element, kAXSubroleAttribute) ?? ""
    }

    public var processID: pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    public func isSameField(as other: EditableField) -> Bool {
        guard let other = other as? AXField else { return false }
        return CFEqual(element, other.element)
    }

    /// Whether this element is the system-wide focused element right now.
    public var hasSystemFocus: Bool {
        let system = AXUIElementCreateSystemWide()
        guard let focused = AX.element(system, kAXFocusedUIElementAttribute) else { return false }
        return CFEqual(focused, element)
    }

    public var isSecure: Bool {
        subrole == kAXSecureTextFieldSubrole || role == "AXSecureTextField"
    }

    public var isEditableText: Bool {
        guard Self.textRoles.contains(role) else { return false }
        guard AX.range(element, kAXSelectedTextRangeAttribute) != nil else { return false }
        return AX.isSettable(element, kAXValueAttribute) || AX.isSettable(element, kAXSelectedTextAttribute)
    }

    public func readText() throws -> String {
        guard !isSecure, let text = AX.string(element, kAXValueAttribute) else { throw Rejection.readFailed }
        return text
    }

    public func readSelection() throws -> UTF16Range {
        guard let range = AX.range(element, kAXSelectedTextRangeAttribute), range.location >= 0, range.length >= 0
        else { throw Rejection.readFailed }
        return UTF16Range(location: range.location, length: range.length)
    }

    public func setSelection(_ range: UTF16Range) {
        guard let value = AX.rangeValue(location: range.location, length: range.length) else { return }
        AX.set(element, kAXSelectedTextRangeAttribute, value)
    }

    /// Replaces `range` with `new`, trying the least invasive strategy first
    /// and checking the result after each attempt:
    ///
    /// 1. select exactly `range` (verified by reading the range and its text
    ///    back) and set `AXSelectedText`;
    /// 2. set the whole `AXValue`;
    /// 3. if enabled, paste over the verified selection while preserving the
    ///    clipboard.
    ///
    /// Nothing is written unless the field still holds exactly `snapshot`, the
    /// text the range was planned against, and the range fits it.
    public func replace(range: UTF16Range, in snapshot: String, with new: String) throws {
        guard !isSecure else { throw Rejection.secureField }
        let before = snapshot
        let expected = try CorrectionEngine.validatedReplacement(
            of: range, in: snapshot, current: try readText(), with: new)
        let units = Array(snapshot.utf16)
        let old = String(decoding: units[range.location..<range.end], as: UTF16.self)
        let originalSelection = try? readSelection()

        /// Re-checked immediately before each mutation.
        func stillCurrent() -> Bool { (try? readText()) == snapshot }

        func settled(timeout: TimeInterval) throws -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while true {
                let now = try readText()
                if now == expected { return true }
                if now != before {
                    // The field changed into something we did not ask for.
                    throw Rejection.verificationFailed
                }
                if Date() >= deadline { return false }
                Thread.sleep(forTimeInterval: 0.015)
            }
        }

        func selectTarget() -> Bool {
            guard AX.isSettable(element, kAXSelectedTextRangeAttribute) else { return false }
            setSelection(range)
            guard (try? readSelection()) == range else { return false }
            // An empty or missing selected-text value is only acceptable when
            // nothing is supposed to be selected.
            return (AX.string(element, kAXSelectedTextAttribute) ?? "") == old
        }

        do {
            if AX.isSettable(element, kAXSelectedTextAttribute), selectTarget(), stillCurrent(),
               AX.set(element, kAXSelectedTextAttribute, new as CFString), try settled(timeout: 0.15) {
                lastWriteStrategy = "selectedText"
                return
            }
            guard stillCurrent() else { throw Rejection.fieldChanged }
            if AX.isSettable(element, kAXValueAttribute),
               AX.set(element, kAXValueAttribute, expected as CFString), try settled(timeout: 0.15) {
                lastWriteStrategy = "value"
                return
            }
            if let pasteFallback, selectTarget() {
                var pasted = false
                try pasteFallback.paste(
                    new,
                    // Checked right before Cmd+V is posted: this element must
                    // still have system-wide keyboard focus and hold the
                    // verified selection of unchanged text.
                    confirm: { self.hasSystemFocus && stillCurrent() && (try? self.readSelection()) == range },
                    wait: { pasted = (try? settled(timeout: 0.6)) ?? false })
                if pasted {
                    lastWriteStrategy = "paste"
                    return
                }
                if try readText() != before { throw Rejection.verificationFailed }
            }
        } catch {
            if let originalSelection, (try? readText()) == before { setSelection(originalSelection) }
            throw error
        }
        if let originalSelection { setSelection(originalSelection) }
        throw Rejection.writeFailed
    }

    // MARK: - Geometry (for placing the Undo panel)

    /// Screen rectangle of a text range, in Accessibility coordinates (origin
    /// at the top-left of the primary display). `nil` if the app does not
    /// report usable bounds.
    public func bounds(for range: UTF16Range) -> CGRect? {
        guard let parameter = AX.rangeValue(location: range.location, length: range.length) else { return nil }
        var value: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value)
        guard status == .success, let rect = AX.rect(value), Self.isUsable(rect) else { return nil }
        return rect
    }

    /// Screen rectangle of the whole field, in Accessibility coordinates.
    public var frame: CGRect? {
        guard let rect = AX.rect(AX.copy(element, "AXFrame")), Self.isUsable(rect) else { return nil }
        return rect
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.height > 0 && rect.width >= 0
            && rect.origin.x.isFinite && rect.origin.y.isFinite
    }
}

/// Finds the element that has keyboard focus.
public final class AXFocusProvider: FocusProviding {
    private let application: AXUIElement?
    public var pasteFallback: PasteFallback?

    /// System-wide focus.
    public init() { application = nil }

    /// Focus within one application (used by the developer check tool).
    public init(processID: pid_t) { application = AXUIElementCreateApplication(processID) }

    public func focusedField() -> EditableField? {
        let root = application ?? AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(root, 1.0)
        guard let element = AX.element(root, kAXFocusedUIElementAttribute) else { return nil }
        let field = AXField(element: element)
        field.pasteFallback = pasteFallback
        return field
    }
}
