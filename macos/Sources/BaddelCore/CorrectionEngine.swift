/// A focused text field, abstracted from the platform accessibility API.
public protocol EditableField: AnyObject {
    func isSameField(as other: EditableField) -> Bool
    /// Password and other protected fields; never read or modified.
    var isSecure: Bool { get }
    /// Whether the element is a text field Baddel knows how to edit.
    var isEditableText: Bool { get }
    func readText() throws -> String
    /// The selection as a UTF-16 range; a zero length is the caret.
    func readSelection() throws -> UTF16Range
    /// Replaces `range` of the field with `new`.
    ///
    /// `snapshot` is the full text the range was planned against. An
    /// implementation must re-read the field and call
    /// `CorrectionEngine.validatedReplacement` before mutating anything, so a
    /// field that changed since planning is rejected instead of overwritten.
    func replace(range: UTF16Range, in snapshot: String, with new: String) throws
    /// Best effort; failures are ignored.
    func setSelection(_ range: UTF16Range)
}

public protocol FocusProviding {
    func focusedField() -> EditableField?
}

public protocol LayoutSwitching {
    /// Opaque platform identifier of the active input source.
    func currentInputSourceID() -> String?
    func currentScript() -> Script?
    func selectLayout(for script: Script) -> Bool
    func selectInputSource(id: String) -> Bool
}

/// Runs a correction against a field: checks, plan, write, verification,
/// layout switch, and the guarded undo.
public final class CorrectionEngine {
    public enum Mode: String, Sendable {
        case selectionOrLastWord
        case wholeField
    }

    public struct UndoRecord {
        public let field: EditableField
        /// Where the replacement sits in the post-edit text.
        public let replacedRange: UTF16Range
        public let original: String
        public let replacement: String
        public let textBefore: String
        public let textAfter: String
        public let selectionBefore: UTF16Range
        public let priorInputSourceID: String?
        public let layoutSwitched: Bool
    }

    public struct Success {
        public let mode: Mode
        public let target: CorrectionTarget
        public let sourceScript: Script
        public let layoutSwitched: Bool
        public let undo: UndoRecord
    }

    /// Fields longer than this (UTF-16 units) are skipped.
    public static let maxFieldLength = 200_000

    private let planner: CorrectionPlanner
    private let focus: FocusProviding
    private let layouts: LayoutSwitching
    public var switchesLayout = true

    public init(planner: CorrectionPlanner, focus: FocusProviding, layouts: LayoutSwitching) {
        self.planner = planner
        self.focus = focus
        self.layouts = layouts
    }

    /// - Parameter capturedField: the field that had focus when the shortcut
    ///   was first pressed. The correction only runs if it still has focus.
    public func correct(mode: Mode, capturedField: EditableField?) -> Result<Success, Rejection> {
        guard let captured = capturedField, let field = focus.focusedField() else { return .failure(.noFocusedField) }
        guard field.isSameField(as: captured) else { return .failure(.focusChanged) }
        guard !field.isSecure else { return .failure(.secureField) }
        guard field.isEditableText else { return .failure(.unsupportedField) }

        guard let text = try? field.readText(), let selection = try? field.readSelection() else {
            return .failure(.readFailed)
        }
        let length = text.utf16.count
        guard length <= Self.maxFieldLength else { return .failure(.fieldTooLarge) }

        let target: CorrectionTarget
        switch mode {
        case .wholeField: target = .wholeField
        case .selectionOrLastWord:
            target = selection.length > 0 ? .selection(selection) : .lastWord(caret: selection.location)
        }

        let plan: CorrectionPlan
        switch planner.plan(text: text, target: target, hint: layouts.currentScript()) {
        case .success(let p): plan = p
        case .failure(let rejection): return .failure(rejection)
        }

        guard let expected = Self.replacing(plan.range, in: text, with: plan.replacement) else {
            return .failure(.invalidRange)
        }
        do {
            try field.replace(range: plan.range, in: text, with: plan.replacement)
        } catch let rejection as Rejection {
            return .failure(rejection)
        } catch {
            return .failure(.writeFailed)
        }
        guard let written = try? field.readText(), written == expected else {
            return .failure(.verificationFailed)
        }

        let newLength = plan.replacement.utf16.count
        let replacedRange = UTF16Range(location: plan.range.location, length: newLength)
        switch target {
        case .selection:
            field.setSelection(replacedRange)
        case .lastWord(let caret):
            field.setSelection(UTF16Range(location: caret + newLength - plan.range.length, length: 0))
        case .wholeField:
            field.setSelection(UTF16Range(location: newLength, length: 0))
        }

        // Only switch the layout once the write has been verified.
        let prior = layouts.currentInputSourceID()
        var switched = false
        if switchesLayout, layouts.currentScript() != plan.targetScript {
            switched = layouts.selectLayout(for: plan.targetScript)
        }

        let undo = UndoRecord(
            field: field, replacedRange: replacedRange, original: plan.original,
            replacement: plan.replacement, textBefore: text, textAfter: expected,
            selectionBefore: selection, priorInputSourceID: prior, layoutSwitched: switched)
        return .success(Success(
            mode: mode, target: target, sourceScript: plan.sourceScript, layoutSwitched: switched, undo: undo))
    }

    /// Restores the original text and layout, but only if the same field is
    /// still focused and still holds exactly the post-edit text.
    public func undo(_ record: UndoRecord) -> Result<Void, Rejection> {
        guard let field = focus.focusedField(), field.isSameField(as: record.field), !field.isSecure else {
            return .failure(.undoStateChanged)
        }
        guard let current = try? field.readText(), current == record.textAfter else {
            return .failure(.undoStateChanged)
        }
        do {
            try field.replace(range: record.replacedRange, in: record.textAfter, with: record.original)
        } catch let rejection as Rejection {
            return .failure(rejection)
        } catch {
            return .failure(.writeFailed)
        }
        guard let restored = try? field.readText(), restored == record.textBefore else {
            return .failure(.verificationFailed)
        }
        field.setSelection(record.selectionBefore)
        if record.layoutSwitched, let prior = record.priorInputSourceID {
            _ = layouts.selectInputSource(id: prior)
        }
        return .success(())
    }

    /// `text` with `range` replaced, or `nil` if the range is out of bounds or
    /// would split a surrogate pair.
    public static func replacing(_ range: UTF16Range, in text: String, with replacement: String) -> String? {
        var units = Array(text.utf16)
        guard CorrectionPlanner.isValid(range, in: units) else { return nil }
        units.replaceSubrange(range.location..<range.end, with: Array(replacement.utf16))
        return String(decoding: units, as: UTF16.self)
    }

    /// The check every field implementation runs immediately before writing.
    ///
    /// - Parameters:
    ///   - snapshot: the full text the range was planned against.
    ///   - current: the field's text, re-read just now.
    /// - Returns: the full text the field must hold after the write.
    /// - Throws: `.fieldChanged` if the field no longer holds the snapshot,
    ///   `.invalidRange` if the range does not fit it.
    public static func validatedReplacement(
        of range: UTF16Range, in snapshot: String, current: String, with replacement: String
    ) throws -> String {
        guard current == snapshot else { throw Rejection.fieldChanged }
        guard let result = replacing(range, in: snapshot, with: replacement) else { throw Rejection.invalidRange }
        return result
    }
}
