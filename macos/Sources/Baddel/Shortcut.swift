import AppKit
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
}

/// User preferences, stored in `UserDefaults`. Nothing here is user text.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

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

    /// Experimental and off by default.
    var pasteFallbackEnabled: Bool {
        get { defaults.bool(forKey: "pasteFallbackEnabled") }
        set { defaults.set(newValue, forKey: "pasteFallbackEnabled") }
    }
}
