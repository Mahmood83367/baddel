// Dumps base and Shift outputs of installed macOS keyboard layouts into the
// shared JSON format (shared/layouts/*.json). Run on macOS:
//
//   swift tools/dump-macos-layouts.swift shared/layouts
//
// The script only reads layout tables via UCKeyTranslate; it does not observe
// any keyboard input.
import Carbon
import Foundation

let keys: [(code: String, mac: UInt16)] = [
    ("Backquote", 50), ("Digit1", 18), ("Digit2", 19), ("Digit3", 20), ("Digit4", 21),
    ("Digit5", 23), ("Digit6", 22), ("Digit7", 26), ("Digit8", 28), ("Digit9", 25),
    ("Digit0", 29), ("Minus", 27), ("Equal", 24),
    ("KeyQ", 12), ("KeyW", 13), ("KeyE", 14), ("KeyR", 15), ("KeyT", 17), ("KeyY", 16),
    ("KeyU", 32), ("KeyI", 34), ("KeyO", 31), ("KeyP", 35), ("BracketLeft", 33),
    ("BracketRight", 30), ("Backslash", 42),
    ("KeyA", 0), ("KeyS", 1), ("KeyD", 2), ("KeyF", 3), ("KeyG", 5), ("KeyH", 4),
    ("KeyJ", 38), ("KeyK", 40), ("KeyL", 37), ("Semicolon", 41), ("Quote", 39),
    ("KeyZ", 6), ("KeyX", 7), ("KeyC", 8), ("KeyV", 9), ("KeyB", 11), ("KeyN", 45),
    ("KeyM", 46), ("Comma", 43), ("Period", 47), ("Slash", 44),
]

let layouts: [(file: String, id: String, name: String, script: String, sourceIDs: [String], windowsIDs: [String])] = [
    ("us-english", "us-english", "US English", "latin", ["com.apple.keylayout.US", "com.apple.keylayout.ABC"], ["00000409"]),
    ("uk-english-mac", "uk-english-mac", "UK English (macOS)", "latin", ["com.apple.keylayout.British"], []),
    ("arabic-mac", "arabic-mac", "Arabic (macOS)", "arabic", ["com.apple.keylayout.Arabic"], []),
    ("arabic-pc", "arabic-pc", "Arabic – PC", "arabic", ["com.apple.keylayout.ArabicPC"], []),
]

func translate(_ layout: UnsafePointer<UCKeyboardLayout>, key: UInt16, shift: Bool) -> String? {
    var dead: UInt32 = 0
    var length = 0
    var chars = [UniChar](repeating: 0, count: 8)
    let modifiers: UInt32 = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
    let status = UCKeyTranslate(
        layout, key, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, chars.count, &length, &chars)
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: chars, count: length)
}

func esc(_ s: String) -> String {
    var out = "\""
    for u in s.unicodeScalars {
        switch u {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        default:
            // Keep printable ASCII and Arabic letters readable; escape the rest.
            if (0x20...0x7E).contains(u.value) || (0x0621...0x064A).contains(u.value) {
                out.unicodeScalars.append(u)
            } else {
                out += String(format: "\\u%04X", u.value)
            }
        }
    }
    return out + "\""
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for l in layouts {
    let filter = [kTISPropertyInputSourceID as String: l.sourceIDs[0]] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
          let source = list.first,
          let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else {
        FileHandle.standardError.write("missing layout \(l.sourceIDs[0])\n".data(using: .utf8)!)
        exit(1)
    }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    var lines: [String] = []
    data.withUnsafeBytes { buf in
        let p = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress!
        for k in keys {
            let b = translate(p, key: k.mac, shift: false) ?? ""
            let s = translate(p, key: k.mac, shift: true) ?? ""
            lines.append("    { \"code\": \(esc(k.code)), \"base\": \(esc(b)), \"shift\": \(esc(s)) }")
        }
    }
    // The Windows US layout table was compared with this one on Windows. The
    // Windows Arabic layouts are generated there by `baddel-wincheck --dump-layouts`.
    let windows = l.windowsIDs.isEmpty ? "" : ", \"windows\": [\(l.windowsIDs.map(esc).joined(separator: ", "))]"
    let json = """
    {
      "id": \(esc(l.id)),
      "name": \(esc(l.name)),
      "script": \(esc(l.script)),
      "platformIds": { "macos": [\(l.sourceIDs.map(esc).joined(separator: ", "))]\(windows) },
      "keys": [
    \(lines.joined(separator: ",\n"))
      ]
    }

    """
    try! json.write(toFile: "\(outDir)/\(l.file).json", atomically: true, encoding: .utf8)
}
