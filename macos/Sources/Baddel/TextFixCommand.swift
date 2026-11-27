import BaddelCore
import BaddelMacKit
import Foundation

/// The command-line form of `TextFix`, used by the shell integration and as
/// Claude Code's external editor. It runs, answers and exits; it does not
/// start the menu bar app and needs no Accessibility access.
///
///     Baddel --fix-text [--mode word|line] [--cursor N] [--selection START LENGTH]
///            [--unit utf16|scalars|bytes] [--hint latin|arabic|none]
///         reads the buffer from standard input (UTF-8) and writes
///         "ok CURSOR\n" followed by the corrected buffer, or "no CODE\n".
///     Baddel --fix-draft [--any-file] [--hint …] FILE
///         corrects a Claude Code draft file in place; the file is rewritten
///         only when a correction was made.
///
/// Exit codes: 0 corrected, 1 left unchanged, 2 wrong usage. Messages carry
/// stable codes and never the text.
enum TextFixCommand {
    static let draftPrefix = "claude-prompt-"

    static func handles(_ arguments: [String]) -> Bool {
        arguments.contains("--fix-text") || arguments.contains("--fix-draft")
    }

    private struct UsageError: Error {}

    static func run(_ arguments: [String]) -> Int32 {
        let draft = arguments.contains("--fix-draft")
        var mode: TextFix.Mode = draft ? .line : .word
        var unit: TextFix.Unit = .utf16
        var cursor: Int?
        var selection: UTF16Range?
        var hintName: String?
        var file: String?
        var anyFile = false
        do {
            var index = 1
            func next() throws -> String {
                index += 1
                guard index < arguments.count else { throw UsageError() }
                return arguments[index]
            }
            func number() throws -> Int {
                guard let value = Int(try next()) else { throw UsageError() }
                return value
            }
            while index < arguments.count {
                switch arguments[index] {
                case "--fix-text", "--fix-draft": break
                case "--any-file": anyFile = true
                case "--mode":
                    guard let value = TextFix.Mode(rawValue: try next()) else { throw UsageError() }
                    mode = value
                case "--unit":
                    guard let value = TextFix.Unit(rawValue: try next()) else { throw UsageError() }
                    unit = value
                case "--cursor": cursor = try number()
                case "--selection":
                    let start = try number()
                    selection = UTF16Range(location: start, length: try number())
                case "--hint":
                    let value = try next()
                    guard ["latin", "arabic", "none"].contains(value) else { throw UsageError() }
                    hintName = value
                case let other:
                    guard draft, file == nil, !other.hasPrefix("--") else { throw UsageError() }
                    file = other
                }
                index += 1
            }
            if draft, file == nil { throw UsageError() }
        } catch {
            say("baddel: usage: --fix-text [--mode word|line] [--cursor N] [--selection START LENGTH] "
                + "[--unit utf16|scalars|bytes] [--hint latin|arabic|none] | --fix-draft [--any-file] FILE")
            return 2
        }

        func refuse(_ code: String) -> Int32 {
            if draft {
                say("baddel: draft left unchanged (\(code))")
            } else {
                FileHandle.standardOutput.write(Data("no \(code)\n".utf8))
            }
            return 1
        }

        let url = file.map { URL(fileURLWithPath: $0) }
        if let url, !anyFile, !url.lastPathComponent.hasPrefix(draftPrefix) { return refuse("notAClaudeDraft") }

        let data: Data
        if let url {
            guard let contents = try? Data(contentsOf: url) else { return refuse(Rejection.readFailed.rawValue) }
            data = contents
        } else {
            data = FileHandle.standardInput.readDataToEndOfFile()
        }
        guard let text = String(data: data, encoding: .utf8) else { return refuse(Rejection.readFailed.rawValue) }

        guard let store = try? BaddelResources.loadLayouts() else { return refuse("noLayouts") }
        let switcher = InputSourceSwitcher(store: store)
        switcher.preferredArabicLayoutID = Settings.shared.arabicLayoutID
        switcher.preferredEnglishLayoutID = Settings.shared.englishLayoutID
        guard let pair = switcher.resolvePair() else { return refuse("noLayouts") }
        let hint: Script?
        switch hintName {
        case "latin": hint = .latin
        case "arabic": hint = .arabic
        case "none": hint = nil
        default: hint = switcher.currentScript()
        }

        let request = TextFix.Request(
            text: text, mode: mode, unit: unit, cursor: cursor, selection: selection, hint: hint,
            keepsClaudePlaceholders: draft)
        switch TextFix.run(request, planner: CorrectionPlanner(pair: pair)) {
        case .failure(let rejection):
            return refuse(rejection.rawValue)
        case .success(let output):
            if let url {
                // Written in place: Claude Code reads this same file back.
                guard (try? Data(output.text.utf8).write(to: url)) != nil else {
                    return refuse(Rejection.writeFailed.rawValue)
                }
                say("baddel: draft corrected")
            } else {
                FileHandle.standardOutput.write(Data("ok \(output.cursor)\n\(output.text)".utf8))
            }
            return 0
        }
    }

    private static func say(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
