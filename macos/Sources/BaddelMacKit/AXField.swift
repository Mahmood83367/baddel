import AppKit
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

    public var isEditableText: Bool { unsupportedReason == nil }

    /// Why this element cannot be corrected, as a code that is safe to log, or
    /// `nil` when it can.
    ///
    /// A text element is accepted when Accessibility can write to it, or, with
    /// the paste option on, when it is a text element whose text and selection
    /// can be read and whose selection can be set: the paste path then selects
    /// the exact range, checks it, and pastes over it.
    public var unsupportedReason: String? {
        guard Self.textRoles.contains(role) else { return "notATextElement" }
        guard AX.range(element, kAXSelectedTextRangeAttribute) != nil else { return "noSelectionRange" }
        if AX.isSettable(element, kAXValueAttribute) || AX.isSettable(element, kAXSelectedTextAttribute) { return nil }
        guard AX.isSettable(element, kAXSelectedTextRangeAttribute), AX.string(element, kAXValueAttribute) != nil else {
            return "notWritable"
        }
        return pasteFallback == nil ? "needsPasteOption" : nil
    }

    public var isTextElement: Bool { Self.textRoles.contains(role) }

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
    public init(processID: pid_t) {
        application = AXUIElementCreateApplication(processID)
        self.processID = processID
    }

    private var processID: pid_t?

    /// What the last `focusedField()` call found, as codes that are safe to log.
    public struct Report: Equatable, Sendable {
        /// Whether Accessibility named any focused element.
        public var foundElement = false
        /// Set when the app had to be asked to expose its accessibility tree.
        public var wake: WebAccessibility.Wake?
        /// Milliseconds spent waiting for the tree after asking.
        public var waitedMs = 0

        public init() {}
    }

    public private(set) var lastReport = Report()

    /// How long to wait for a Chromium-based app to expose its tree.
    public var wakeTimeout: TimeInterval = 1.2

    public func focusedField() -> EditableField? {
        var report = Report()
        defer { lastReport = report }
        var field = currentField()
        report.foundElement = field != nil
        if field?.isTextElement == true {
            WebAccessibility.touch(processID: field!.processID)
            return field
        }
        // No element, or one that is not text: a Chromium-based app that has not
        // been asked for its accessibility tree looks exactly like this.
        guard let target = targetApplication() else { return field }
        let wake = WebAccessibility.wake(processID: target.processID, bundleURL: target.bundleURL)
        report.wake = wake
        guard wake != .notApplicable else { return field }
        let start = Date()
        let timeout = wake == .alreadyAsked ? min(wakeTimeout, 0.3) : wakeTimeout
        while Date().timeIntervalSince(start) < timeout {
            Thread.sleep(forTimeInterval: 0.04)
            if let now = currentField() {
                field = now
                report.foundElement = true
                if now.isTextElement { break }
            }
        }
        report.waitedMs = Int(Date().timeIntervalSince(start) * 1000)
        WebAccessibility.touch(processID: target.processID)
        return field
    }

    private func currentField() -> AXField? {
        let root = application ?? AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(root, 1.0)
        guard let element = AX.element(root, kAXFocusedUIElementAttribute) else { return nil }
        let field = AXField(element: element)
        field.pasteFallback = pasteFallback
        return field
    }

    /// The application whose focus is being asked about.
    private func targetApplication() -> (processID: pid_t, bundleURL: URL?)? {
        if let processID {
            return (processID, NSRunningApplication(processIdentifier: processID)?.bundleURL)
        }
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        return (front.processIdentifier, front.bundleURL)
    }
}
