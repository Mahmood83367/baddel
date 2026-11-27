/// A range of UTF-16 code units, the unit Accessibility (macOS) and UI
/// Automation (Windows) text ranges use.
public struct UTF16Range: Equatable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public var end: Int { location + length }
}

public enum CorrectionTarget: Equatable, Sendable {
    /// Exactly the selected text.
    case selection(UTF16Range)
    /// The last word before the caret (UTF-16 offset).
    case lastWord(caret: Int)
    /// The whole field.
    case wholeField
}

/// Reasons a correction is refused. Raw values are stable codes that are safe
/// to log; they never contain user text.
public enum Rejection: String, Error, Equatable, Sendable, CaseIterable {
    case noFocusedField
    case focusChanged
    /// The field's text changed between planning and writing.
    case fieldChanged
    case secureField
    case unsupportedField
    case readFailed
    case fieldTooLarge
    case emptyField
    case noWord
    case invalidRange
    case ambiguousDirection
    case nothingToConvert
    case writeFailed
    case verificationFailed
    case undoStateChanged
}

public struct CorrectionPlan: Equatable, Sendable {
    /// The range of the field's current text to replace.
    public let range: UTF16Range
    public let original: String
    public let replacement: String
    /// The script the text was (wrongly) typed in.
    public let sourceScript: Script
    public var targetScript: Script { sourceScript.opposite }
}

/// Pure planning: given a field's text and a target, works out what to replace
/// and with what. See `docs/CORRECTION_RULES.md` for the rules.
public struct CorrectionPlanner: Sendable {
    public let pair: LayoutPair
    private let evidence: ScriptEvidence
    private let latinToArabic: LayoutConverter
    private let arabicToLatin: LayoutConverter

    public init(pair: LayoutPair) {
        self.pair = pair
        evidence = ScriptEvidence(pair: pair)
        latinToArabic = LayoutConverter(from: pair.latin, to: pair.arabic)
        arabicToLatin = LayoutConverter(from: pair.arabic, to: pair.latin)
    }

    /// - Parameter hint: the script of the currently active keyboard layout,
    ///   used only when the text itself does not decide the direction.
    public func plan(text: String, target: CorrectionTarget, hint: Script?) -> Result<CorrectionPlan, Rejection> {
        let units = Array(text.utf16)
        let range: UTF16Range
        switch target {
        case .wholeField:
            guard !units.isEmpty else { return .failure(.emptyField) }
            range = UTF16Range(location: 0, length: units.count)
        case .selection(let selection):
            guard selection.length > 0, Self.isValid(selection, in: units) else { return .failure(.invalidRange) }
            range = selection
        case .lastWord(let caret):
            guard Self.isValid(UTF16Range(location: caret, length: 0), in: units) else { return .failure(.invalidRange) }
            guard let word = Self.lastWord(before: caret, in: units) else { return .failure(.noWord) }
            range = word
        }

        let segment = units[range.location..<range.end]
        let tokens = Self.tokens(in: segment)
        guard !tokens.isEmpty else { return .failure(.nothingToConvert) }

        let tokenCounts = tokens.map { evidence.count(segment[$0]) }
        let total = tokenCounts.reduce(ScriptEvidence.Counts(), +)
        guard let source = total.dominantScript ?? hint else { return .failure(.ambiguousDirection) }
        let converter = source == .latin ? latinToArabic : arabicToLatin

        var result: [UInt16] = []
        result.reserveCapacity(segment.count)
        var cursor = segment.startIndex
        for (token, counts) in zip(tokens, tokenCounts) {
            result.append(contentsOf: segment[cursor..<token.lowerBound])
            if counts.uniformScript == source.opposite {
                // Text already in the other script is left untouched.
                result.append(contentsOf: segment[token])
            } else {
                result.append(contentsOf: converter.convert(Array(segment[token])))
            }
            cursor = token.upperBound
        }
        result.append(contentsOf: segment[cursor..<segment.endIndex])

        guard result != Array(segment) else { return .failure(.nothingToConvert) }
        return .success(CorrectionPlan(
            range: range,
            original: String(decoding: segment, as: UTF16.self),
            replacement: String(decoding: result, as: UTF16.self),
            sourceScript: source))
    }

    // MARK: - Text helpers (UTF-16)

    static func isHorizontalSpace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x202F, 0x205F, 0x3000: return true
        default: return false
        }
    }

    static func isLineBreak(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: return true
        default: return false
        }
    }

    static func isWhitespace(_ unit: UInt16) -> Bool { isHorizontalSpace(unit) || isLineBreak(unit) }

    /// A range is valid when it lies inside the text and neither edge splits a
    /// surrogate pair.
    static func isValid(_ range: UTF16Range, in units: [UInt16]) -> Bool {
        guard range.location >= 0, range.length >= 0, range.end <= units.count else { return false }
        func splitsPair(_ offset: Int) -> Bool {
            guard offset > 0, offset < units.count else { return false }
            return (0xD800...0xDBFF).contains(units[offset - 1]) && (0xDC00...0xDFFF).contains(units[offset])
        }
        return !splitsPair(range.location) && !splitsPair(range.end)
    }

    /// The run of non-whitespace before `caret`, skipping spaces and tabs
    /// between the word and the caret but never crossing a line break.
    static func lastWord(before caret: Int, in units: [UInt16]) -> UTF16Range? {
        var end = caret
        while end > 0, isHorizontalSpace(units[end - 1]) { end -= 1 }
        var start = end
        while start > 0, !isWhitespace(units[start - 1]) { start -= 1 }
        return end > start ? UTF16Range(location: start, length: end - start) : nil
    }

    /// Whitespace-delimited tokens of a segment, as index ranges into it.
    static func tokens(in segment: ArraySlice<UInt16>) -> [Range<Int>] {
        var tokens: [Range<Int>] = []
        var start: Int?
        for index in segment.indices {
            if isWhitespace(segment[index]) {
                if let s = start { tokens.append(s..<index); start = nil }
            } else if start == nil {
                start = index
            }
        }
        if let s = start { tokens.append(s..<segment.endIndex) }
        return tokens
    }
}
