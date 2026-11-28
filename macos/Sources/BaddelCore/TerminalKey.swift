/// Works out how Baddel's one shortcut reaches a program inside a terminal.
///
/// A terminal does not pass key combinations on as such: it sends bytes. A
/// combination with Control arrives as one control character, one with
/// Option or Alt as Escape followed by the key, and one with Command or the
/// Windows key does not arrive at all. From the combination chosen in
/// Baddel's settings this type derives what a shell has to bind, what
/// PSReadLine and Claude Code call the same key, or the reason it cannot be
/// delivered.
///
/// The Windows and Linux implementation is `TerminalKey.cs`; both run
/// `shared/fixtures/terminal-keys.json`.
public struct TerminalKey: Equatable, Sendable {
    public enum Platform: String, Sendable { case macos, windows, linux }

    public struct Combination: Equatable, Sendable {
        public var control: Bool
        /// Option on macOS, Alt elsewhere.
        public var alt: Bool
        public var shift: Bool
        /// Command on macOS, the Windows or Super key elsewhere.
        public var command: Bool
        /// `space`, or one lower-case ASCII character such as `t` or `]`.
        public var key: String

        public init(control: Bool = false, alt: Bool = false, shift: Bool = false, command: Bool = false, key: String) {
            self.control = control
            self.alt = alt
            self.shift = shift
            self.command = command
            self.key = key
        }
    }

    /// The byte sequences a shell should bind, most specific first. Empty when
    /// the combination cannot be delivered.
    public let sequences: [[UInt8]]
    /// Why it cannot be delivered, as a stable code.
    public let reason: String?
    /// macOS Terminal sends Option combinations as Escape sequences only with
    /// "Use Option as Meta key" on. Shells are still served when `sequences`
    /// starts with the character Terminal types instead (Option-Space).
    public let needsOptionAsMeta: Bool
    /// The chord in PSReadLine's notation.
    public let psReadLineChord: String?
    /// The keystroke in Claude Code's `keybindings.json` notation; more than
    /// one when a terminal may or may not report Shift.
    public let claudeKeystrokes: [String]

    public var isDeliverable: Bool { !sequences.isEmpty }

    /// Control characters a terminal or line editor already gives a fixed
    /// meaning: interrupt, end of input, backspace, tab, newline, return, flow
    /// control, suspend.
    static let reservedControlLetters: Set<Character> = ["c", "d", "h", "i", "j", "m", "q", "s", "z"]

    public static func resolve(_ combination: Combination, platform: Platform) -> TerminalKey {
        func refuse(_ reason: String) -> TerminalKey {
            TerminalKey(sequences: [], reason: reason, needsOptionAsMeta: false, psReadLineChord: nil, claudeKeystrokes: [])
        }
        if combination.command { return refuse("usesCommandKey") }
        guard combination.control || combination.alt else { return refuse("needsControlOrAlt") }
        let isSpace = combination.key == "space"
        guard isSpace || (combination.key.count == 1 && combination.key.unicodeScalars.first!.isASCII
            && combination.key.unicodeScalars.first!.value > 0x20 && combination.key.unicodeScalars.first!.value < 0x7F)
        else { return refuse("keyHasNoTerminalSequence") }
        let character = isSpace ? Character(" ") : Character(combination.key)
        let ascii = character.asciiValue!

        var sequences: [[UInt8]] = []
        if combination.control {
            let controlByte: UInt8
            if isSpace {
                controlByte = 0x00
            } else if character.isLetter {
                guard !reservedControlLetters.contains(character) else { return refuse("reservedInTerminals") }
                controlByte = ascii & 0x1F
            } else if character == "]" || character == "^" || character == "_" {
                controlByte = ascii & 0x1F
            } else if character == "[" || character == "\\" {
                return refuse("reservedInTerminals")
            } else {
                return refuse("keyHasNoTerminalSequence")
            }
            sequences = [combination.alt ? [0x1B, controlByte] : [controlByte]]
        } else {
            // Alt or Option alone: Escape, then the key as typed.
            guard isSpace || character.isLetter || character.isNumber || !combination.shift else {
                return refuse("keyHasNoTerminalSequence")
            }
            let typed = combination.shift && character.isLetter ? Character(character.uppercased()).asciiValue! : ascii
            sequences = [[0x1B, typed]]
            // macOS Terminal with its default settings types what Option makes
            // of the key. For Space that is a non-breaking space on the Latin
            // and Arabic layouts alike, a character with no other use on a
            // command line, so a shell can bind it. For other keys it is an
            // ordinary character that must stay typeable.
            if platform == .macos, isSpace { sequences.insert([0xC2, 0xA0], at: 0) }
        }

        var modifiers: [String] = []
        if combination.control { modifiers.append("ctrl") }
        if combination.alt { modifiers.append("alt") }
        let name = isSpace ? "space" : combination.key
        var claude = [(modifiers + (combination.shift ? ["shift"] : []) + [name]).joined(separator: "+")]
        // Without a protocol that reports modifiers, a terminal cannot tell
        // Shift apart for these keys, so Claude Code sees the plain keystroke.
        if combination.shift { claude.append((modifiers + [name]).joined(separator: "+")) }

        var chord: [String] = []
        if combination.control { chord.append("Ctrl") }
        if combination.alt { chord.append("Alt") }
        if combination.shift { chord.append("Shift") }
        chord.append(isSpace ? "Spacebar" : combination.key)

        return TerminalKey(
            sequences: sequences, reason: nil,
            needsOptionAsMeta: platform == .macos && combination.alt,
            psReadLineChord: chord.joined(separator: "+"), claudeKeystrokes: claude)
    }

    public enum Shell: String, Sendable { case zsh, bash }

    /// The sequences in the notation `bindkey` (zsh) or `bind` (Bash) reads.
    public func notation(for shell: Shell) -> [String] {
        sequences.map { bytes in
            bytes.map { byte -> String in
                switch byte {
                case 0x1B: return "\\e"
                case 0x00: return shell == .zsh ? "^@" : "\\C-@"
                case 0x01...0x1A:
                    let letter = String(UnicodeScalar(byte + 0x60))
                    return shell == .zsh ? "^" + letter.uppercased() : "\\C-" + letter
                case 0x1C...0x1F:
                    let symbol = String(UnicodeScalar(byte + 0x40))
                    return shell == .zsh ? "^" + symbol : "\\C-" + symbol
                case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return String(UnicodeScalar(byte))
                default:
                    let hex = String(byte, radix: 16)
                    return "\\x" + (hex.count == 1 ? "0" + hex : hex)
                }
            }.joined()
        }
    }
}
