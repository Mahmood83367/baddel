import Foundation

/// A problem found in a layout definition. Codes are stable and contain no
/// layout content beyond a key name.
public struct LayoutProblem: Equatable, Sendable {
    public enum Code: String, Sendable {
        case invalidId
        case missingKey
        case unknownKey
        case duplicateKey
        case emptyBase
        case outputTooLong
        case invalidCharacter
        /// Warning: two keys produce the same text, so converting back picks the first.
        case duplicateOutput
    }

    public let code: Code
    public let key: String?

    public var isError: Bool { code != .duplicateOutput }

    public init(_ code: Code, key: String? = nil) {
        self.code = code
        self.key = key
    }
}

/// Checks a layout before it is used. Built-in layouts pass by construction;
/// this exists for layouts a user supplies.
public enum LayoutValidator {
    /// The 47 keys every layout must define, each exactly once.
    public static let standardKeyCodes: [String] = [
        "Backquote", "Digit1", "Digit2", "Digit3", "Digit4", "Digit5", "Digit6", "Digit7", "Digit8", "Digit9",
        "Digit0", "Minus", "Equal",
        "KeyQ", "KeyW", "KeyE", "KeyR", "KeyT", "KeyY", "KeyU", "KeyI", "KeyO", "KeyP", "BracketLeft",
        "BracketRight", "Backslash",
        "KeyA", "KeyS", "KeyD", "KeyF", "KeyG", "KeyH", "KeyJ", "KeyK", "KeyL", "Semicolon", "Quote",
        "KeyZ", "KeyX", "KeyC", "KeyV", "KeyB", "KeyN", "KeyM", "Comma", "Period", "Slash",
    ]

    /// Longest output of one key, in UTF-16 units.
    public static let maxOutputLength = 4

    public static func isValidId(_ id: String) -> Bool {
        let units = Array(id.utf8)
        guard (1...64).contains(units.count), let first = units.first, first != UInt8(ascii: "-") else { return false }
        return units.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == UInt8(ascii: "-") }
    }

    public static func validate(_ layout: KeyboardLayout) -> [LayoutProblem] {
        var problems: [LayoutProblem] = []
        if !isValidId(layout.id) { problems.append(LayoutProblem(.invalidId)) }

        let known = Set(standardKeyCodes)
        var seen = Set<String>()
        for key in layout.keys {
            if !known.contains(key.code) {
                problems.append(LayoutProblem(.unknownKey, key: key.code))
            } else if !seen.insert(key.code).inserted {
                problems.append(LayoutProblem(.duplicateKey, key: key.code))
            }
        }
        for code in standardKeyCodes where !seen.contains(code) {
            problems.append(LayoutProblem(.missingKey, key: code))
        }

        var baseOutputs = Set<String>()
        var shiftOutputs = Set<String>()
        for key in layout.keys where known.contains(key.code) {
            if key.base.isEmpty { problems.append(LayoutProblem(.emptyBase, key: key.code)) }
            for output in [key.base, key.shift] {
                let units = Array(output.utf16)
                if units.count > maxOutputLength { problems.append(LayoutProblem(.outputTooLong, key: key.code)) }
                if !isCleanText(units) { problems.append(LayoutProblem(.invalidCharacter, key: key.code)) }
            }
            if !key.base.isEmpty, !baseOutputs.insert(key.base).inserted {
                problems.append(LayoutProblem(.duplicateOutput, key: key.code))
            }
            if !key.shift.isEmpty, !shiftOutputs.insert(key.shift).inserted {
                problems.append(LayoutProblem(.duplicateOutput, key: key.code))
            }
        }
        return problems
    }

    /// No control characters, no whitespace, no unpaired surrogates.
    static func isCleanText(_ units: [UInt16]) -> Bool {
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit < 0x20 || unit == 0x7F || CorrectionPlanner.isWhitespace(unit) { return false }
            if (0xD800...0xDBFF).contains(unit) {
                guard index + 1 < units.count, (0xDC00...0xDFFF).contains(units[index + 1]) else { return false }
                index += 1
            } else if (0xDC00...0xDFFF).contains(unit) {
                return false
            }
            index += 1
        }
        return true
    }
}

/// The outcome of looking for user-supplied layouts in a folder.
public struct CustomLayoutReport: Equatable, Sendable {
    public let file: String
    public let layoutId: String?
    /// Empty when the layout was accepted.
    public let errors: [LayoutProblem]
    public let warnings: [LayoutProblem]
    public var accepted: Bool { errors.isEmpty }
}

extension LayoutStore {
    /// Ids of user-supplied layouts must start with this, so they can never
    /// replace or shadow a built-in layout.
    public static let customPrefix = "custom-"

    /// Adds every valid layout found in `directory` (`*.json`). Files that do
    /// not parse, fail validation, do not use the `custom-` id prefix, or
    /// repeat an existing id are skipped and reported; built-in layouts and
    /// defaults are never changed. A missing folder is not an error.
    public func addingCustomLayouts(from directory: URL) -> (store: LayoutStore, reports: [CustomLayoutReport]) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var all = layouts
        var reports: [CustomLayoutReport] = []
        for file in files.prefix(32) {
            let name = file.lastPathComponent
            guard let data = try? Data(contentsOf: file), data.count <= 64 * 1024,
                  let layout = try? JSONDecoder().decode(KeyboardLayout.self, from: data) else {
                reports.append(CustomLayoutReport(file: name, layoutId: nil, errors: [LayoutProblem(.invalidCharacter)], warnings: []))
                continue
            }
            var problems = LayoutValidator.validate(layout)
            if !layout.id.hasPrefix(Self.customPrefix) || all[layout.id] != nil {
                problems.append(LayoutProblem(.invalidId))
            }
            let errors = problems.filter(\.isError)
            reports.append(CustomLayoutReport(
                file: name, layoutId: layout.id, errors: errors, warnings: problems.filter { !$0.isError }))
            if errors.isEmpty {
                // A custom layout has no system layout behind it, so it never
                // claims a platform identifier.
                all[layout.id] = KeyboardLayout(
                    id: layout.id, name: layout.name, script: layout.script, platformIds: [:], keys: layout.keys)
            }
        }
        return (LayoutStore(layouts: Array(all.values)), reports)
    }
}
