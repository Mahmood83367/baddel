import AppKit
import BaddelCore
import Carbon.HIToolbox

/// A global shortcut: a virtual key code plus Carbon modifier flags.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// ⌥⇧Space.
    static let `default` = Shortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey | shiftKey))

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Builds a shortcut from a key-down event; `nil` unless it includes
    /// Control, Option or Command (Shift alone would shadow normal typing).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        guard modifiers != 0 else { return nil }
        if flags.contains(.shift) { modifiers |= shiftKey }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: UInt32(modifiers))
    }

    var displayString: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    private static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
    ]

    private static func keyName(_ keyCode: UInt32) -> String {
        keyNames[Int(keyCode)] ?? "Key \(keyCode)"
    }

    /// The same combination as a terminal would have to deliver it.
    var terminalCombination: TerminalKey.Combination {
        let name = Self.keyName(keyCode)
        return TerminalKey.Combination(
            control: carbonModifiers & UInt32(controlKey) != 0, alt: carbonModifiers & UInt32(optionKey) != 0,
            shift: carbonModifiers & UInt32(shiftKey) != 0, command: carbonModifiers & UInt32(cmdKey) != 0,
            key: name == "Space" ? "space" : name.lowercased())
    }

    var terminalKey: TerminalKey { TerminalKey.resolve(terminalCombination, platform: .macos) }
}

/// How the one shortcut is shared with terminal apps.
///
/// A registered global shortcut is consumed before the frontmost app sees it,
/// so a terminal can only receive the combination while Baddel is not holding
/// it. With pass-through active, Baddel releases the shortcut whenever a
/// terminal app is in front and takes it back when another app is.
enum TerminalSharing {
    enum Mode: String {
        /// Pass through once the shell or Claude Code integration has asked for the key.
        case automatic
        case on
        case off
    }

    /// Terminal apps the shortcut is passed to. More can be added with
    /// `defaults write app.baddel.Baddel terminalBundleIDs -array-add <bundle id>`.
    static let knownTerminals = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
        "org.alacritty", "com.github.wez.wezterm", "dev.warp.Warp-Stable",
    ]

    static func isTerminal(bundleID: String?, settings: Settings) -> Bool {
        guard let bundleID else { return false }
        return knownTerminals.contains(bundleID) || settings.extraTerminalBundleIDs.contains(bundleID)
    }

    /// Whether the shortcut is currently left to terminal apps.
    static func isActive(settings: Settings) -> Bool {
        guard settings.shortcut.terminalKey.isDeliverable else { return false }
        switch settings.terminalSharing {
        case .on: return true
        case .off: return false
        case .automatic: return settings.terminalIntegrationSeen
        }
    }

    /// One place that says what is active, for Settings and `--terminal-key status`.
    static func summary(settings: Settings) -> [String] {
        let shortcut = settings.shortcut
        let key = shortcut.terminalKey
        var lines = ["Shortcut: \(shortcut.displayString) (set in Baddel’s Settings; used everywhere)"]
        guard key.isDeliverable else {
            lines.append("In a terminal: not available. \(reasonText(key.reason)) The shell integration falls back to Ctrl+T, and Claude Code to Ctrl+G.")
            return lines
        }
        let sharing: String
        switch settings.terminalSharing {
        case .on: sharing = "on"
        case .off: sharing = "off (the shortcut is not passed to terminal apps)"
        case .automatic:
            sharing = settings.terminalIntegrationSeen
                ? "on (automatic: a terminal integration is installed)"
                : "waiting (automatic: starts when a shell or Claude Code integration first asks for the key)"
        }
        lines.append("Passed to terminal apps: \(sharing)")
        if key.needsOptionAsMeta {
            lines.append(key.sequences.count > 1
                ? "zsh: works with Terminal’s default settings. Claude Code: needs “Use Option as Meta key” in Terminal’s profile, or a terminal that reports modifier keys; otherwise use Ctrl+G."
                : "Needs “Use Option as Meta key” in Terminal’s profile, or a terminal that reports modifier keys.")
        } else {
            lines.append("zsh and Claude Code receive it in any terminal.")
        }
        return lines
    }

    static func reasonText(_ reason: String?) -> String {
        switch reason {
        case "usesCommandKey": return "Terminals do not pass on combinations that use Command."
        case "reservedInTerminals": return "That combination already has a fixed meaning in every terminal."
        case "needsControlOrAlt": return "A terminal needs Control or Option in the combination."
        default: return "A terminal sends nothing a program could recognise for that key."
        }
    }
}

/// User preferences, stored in `UserDefaults`. Nothing here is user text.
final class Settings {
    static let shared = Settings()
    /// `BADDEL_SETTINGS_SUITE` names another preferences domain, so checks never
    /// read or change the real settings.
    private let defaults: UserDefaults = ProcessInfo.processInfo.environment["BADDEL_SETTINGS_SUITE"]
        .flatMap { $0.isEmpty ? nil : UserDefaults(suiteName: $0) } ?? .standard

    var shortcut: Shortcut {
        get {
            guard defaults.object(forKey: "shortcutKeyCode") != nil else { return .default }
            return Shortcut(
                keyCode: UInt32(defaults.integer(forKey: "shortcutKeyCode")),
                carbonModifiers: UInt32(defaults.integer(forKey: "shortcutModifiers")))
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: "shortcutKeyCode")
            defaults.set(Int(newValue.carbonModifiers), forKey: "shortcutModifiers")
        }
    }

    /// `nil` means "detect from the enabled input sources".
    var arabicLayoutID: String? {
        get { defaults.string(forKey: "arabicLayoutID") }
        set { defaults.set(newValue, forKey: "arabicLayoutID") }
    }

    /// `nil` means "detect from the enabled input sources".
    var englishLayoutID: String? {
        get { defaults.string(forKey: "englishLayoutID") }
        set { defaults.set(newValue, forKey: "englishLayoutID") }
    }

    /// Window for the second press, in milliseconds.
    var doublePressMs: Int {
        get {
            let value = defaults.integer(forKey: "doublePressMs")
            return value == 0 ? 300 : min(max(value, 150), 600)
        }
        set { defaults.set(newValue, forKey: "doublePressMs") }
    }

    var switchesLayout: Bool {
        get { defaults.object(forKey: "switchesLayout") == nil ? true : defaults.bool(forKey: "switchesLayout") }
        set { defaults.set(newValue, forKey: "switchesLayout") }
    }

    /// Which releases "Check for Updates" reports. Stable unless the user chooses previews.
    var updateChannel: UpdateChannel {
        get { defaults.string(forKey: "updateChannel").flatMap(UpdateChannel.init(rawValue:)) ?? .stable }
        set { defaults.set(newValue.rawValue, forKey: "updateChannel") }
    }

    /// Off by default. When on, Baddel asks GitHub for the release list once a
    /// day and mentions a newer version in its menu. It never downloads or installs.
    var checksForUpdatesAutomatically: Bool {
        get { defaults.bool(forKey: "checksForUpdatesAutomatically") }
        set { defaults.set(newValue, forKey: "checksForUpdatesAutomatically") }
    }

    var lastAutomaticUpdateCheck: Date? {
        get { defaults.object(forKey: "lastAutomaticUpdateCheck") as? Date }
        set { defaults.set(newValue, forKey: "lastAutomaticUpdateCheck") }
    }

    /// Whether terminal apps are left the shortcut. See `TerminalSharing`.
    var terminalSharing: TerminalSharing.Mode {
        get { defaults.string(forKey: "terminalSharing").flatMap(TerminalSharing.Mode.init(rawValue:)) ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: "terminalSharing") }
    }

    /// Set the first time a shell or Claude Code integration asks which key to bind.
    var terminalIntegrationSeen: Bool {
        get { defaults.bool(forKey: "terminalIntegrationSeen") }
        set { defaults.set(newValue, forKey: "terminalIntegrationSeen") }
    }

    var extraTerminalBundleIDs: [String] { defaults.stringArray(forKey: "terminalBundleIDs") ?? [] }

    /// Experimental and off by default.
    var pasteFallbackEnabled: Bool {
        get { defaults.bool(forKey: "pasteFallbackEnabled") }
        set { defaults.set(newValue, forKey: "pasteFallbackEnabled") }
    }
}
