import Foundation

/// Corrects text handed over by a host that owns its own editing buffer: a
/// shell line editor (zsh, Bash, PSReadLine) or the draft file Claude Code
/// passes to an external editor. The host sends the whole buffer and where the
/// cursor is; it gets the whole buffer back and puts it in place itself, so
/// its own undo covers the change. Nothing here reads a screen or sends keys.
///
/// The Windows and Linux implementation is `TextFix.cs`; both run
/// `shared/fixtures/text-fix.json`.
public enum TextFix {
    public enum Mode: String, Sendable {
        /// The selection when there is one, otherwise the last word before the cursor.
        case word
        /// The whole buffer.
        case line
    }

    /// What the host counts cursor positions in.
    public enum Unit: String, Sendable {
        case utf16
        /// Unicode code points (zsh, Bash 5.0 and later).
        case scalars
        /// UTF-8 bytes (Bash before 5.0).
        case bytes
    }

    public struct Request: Sendable {
        public var text: String
        public var mode: Mode
        public var unit: Unit
        /// `nil` means the end of the text.
        public var cursor: Int?
        /// Start and length in `unit`; used in `.word` mode only.
        public var selection: UTF16Range?
        public var hint: Script?
        /// Keeps Claude Code's `[Image #1]` and `[Pasted text #1 +5 lines]` markers as they are.
        public var keepsClaudePlaceholders: Bool

        public init(
            text: String, mode: Mode, unit: Unit = .utf16, cursor: Int? = nil, selection: UTF16Range? = nil,
            hint: Script? = nil, keepsClaudePlaceholders: Bool = false
        ) {
            self.text = text
            self.mode = mode
            self.unit = unit
            self.cursor = cursor
            self.selection = selection
            self.hint = hint
            self.keepsClaudePlaceholders = keepsClaudePlaceholders
        }
    }

    public struct Output: Equatable, Sendable {
        public let text: String
        /// Where the cursor belongs in `text`, in the request's unit.
        public let cursor: Int
        public let sourceScript: Script
    }

    public static func run(_ request: Request, planner: CorrectionPlanner) -> Result<Output, Rejection> {
        let units = Array(request.text.utf16)
        guard units.count <= CorrectionEngine.maxFieldLength else { return .failure(.fieldTooLarge) }
        guard !units.isEmpty else { return .failure(.emptyField) }

        let caret: Int
        if let cursor = request.cursor {
            guard let offset = utf16Offset(of: cursor, unit: request.unit, in: request.text) else {
                return .failure(.invalidRange)
            }
            caret = offset
        } else {
            caret = units.count
        }

        let target: CorrectionTarget
        var selected = false
        switch request.mode {
        case .line:
            target = .wholeField
        case .word:
            if let selection = request.selection, selection.length > 0 {
                guard let start = utf16Offset(of: selection.location, unit: request.unit, in: request.text),
                      let end = utf16Offset(of: selection.end, unit: request.unit, in: request.text) else {
                    return .failure(.invalidRange)
                }
                target = .selection(UTF16Range(location: start, length: end - start))
                selected = true
            } else {
                target = .lastWord(caret: caret)
            }
        }

        let protected = request.keepsClaudePlaceholders ? claudePlaceholders(in: request.text) : []
        switch planner.plan(
            text: request.text, target: target, hint: request.hint, protected: protected, hintDecidesMixedText: true) {
        case .failure(let rejection):
            return .failure(rejection)
        case .success(let plan):
            let replacement = Array(plan.replacement.utf16)
            let result = Array(units[..<plan.range.location]) + replacement + Array(units[plan.range.end...])
            var newCaret: Int
            switch request.mode {
            case .line:
                newCaret = caret >= units.count ? result.count : min(caret, result.count)
            case .word:
                newCaret = selected
                    ? plan.range.location + replacement.count
                    : caret + replacement.count - plan.range.length
            }
            // Never leave the cursor inside a surrogate pair.
            if newCaret > 0, newCaret < result.count,
               (0xD800...0xDBFF).contains(result[newCaret - 1]), (0xDC00...0xDFFF).contains(result[newCaret]) {
                newCaret -= 1
            }
            let text = String(decoding: result, as: UTF16.self)
            return .success(Output(
                text: text,
                cursor: position(ofUTF16: newCaret, unit: request.unit, in: text),
                sourceScript: plan.sourceScript))
        }
    }

    // MARK: - Claude Code markers

    private static let placeholderPattern = try! NSRegularExpression(
        pattern: #"\[(?:Image #\d+|Pasted text #\d+(?: \+\d+ lines)?|\.\.\.Truncated text #\d+ \+\d+ lines\.\.\.)\]"#)

    /// The markers Claude Code shows in a draft for an attached image or a
    /// collapsed paste. They refer to content held by Claude Code, so they
    /// must survive a correction letter for letter.
    public static func claudePlaceholders(in text: String) -> [UTF16Range] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        return placeholderPattern.matches(in: text, range: whole).map {
            UTF16Range(location: $0.range.location, length: $0.range.length)
        }
    }

    // MARK: - Cursor units

    /// The UTF-16 offset of position `index` counted in `unit`, or `nil` when
    /// it lies outside the text or inside a character.
    public static func utf16Offset(of index: Int, unit: Unit, in text: String) -> Int? {
        guard index >= 0 else { return nil }
        switch unit {
        case .utf16:
            return index <= text.utf16.count ? index : nil
        case .scalars, .bytes:
            var remaining = index
            var offset = 0
            for scalar in text.unicodeScalars {
                if remaining == 0 { return offset }
                let width = unit == .scalars ? 1 : UTF8.width(scalar)
                guard remaining >= width else { return nil }
                remaining -= width
                offset += UTF16.width(scalar)
            }
            return remaining == 0 ? offset : nil
        }
    }

    /// The inverse of `utf16Offset`; an offset inside a surrogate pair counts
    /// as the position before the pair.
    public static func position(ofUTF16 offset: Int, unit: Unit, in text: String) -> Int {
        switch unit {
        case .utf16:
            return min(max(offset, 0), text.utf16.count)
        case .scalars, .bytes:
            var position = 0
            var seen = 0
            for scalar in text.unicodeScalars {
                let width = UTF16.width(scalar)
                guard seen + width <= offset else { break }
                seen += width
                position += unit == .scalars ? 1 : UTF8.width(scalar)
            }
            return position
        }
    }
}
