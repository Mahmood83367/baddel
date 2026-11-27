import AppKit
import BaddelCore
import Carbon.HIToolbox

import BaddelMacKit

// `Baddel --self-check` verifies the pieces that need no user interaction and
// exits: layout data loads and the system accepts the configured shortcut.
if CommandLine.arguments.contains("--self-check") {
    let layouts = (try? BaddelResources.loadLayouts())?.layouts.keys.sorted() ?? []
    let registered = HotKeyCenter().register(Settings.shared.shortcut)
    print("layouts=\(layouts.joined(separator: ","))")
    print("shortcut=\(Settings.shared.shortcut.displayString) registered=\(registered)")
    print("accessibilityTrusted=\(AccessibilityPermission.isGranted)")
    print("version=\(AppInfo.version) \(AppInfo.copyright)")
    exit(layouts.count >= 3 && registered ? 0 : 1)
}

// `Baddel --check-updates [stable|preview]` performs the same check as the
// menu item and prints the result.
if let index = CommandLine.arguments.firstIndex(of: "--check-updates") {
    let channel = CommandLine.arguments.dropFirst(index + 1).first.flatMap(UpdateChannel.init(rawValue:)) ?? .stable
    var finished = false
    UpdateChecker.check(current: AppInfo.version == "development build" ? "0.0.0" : AppInfo.version, channel: channel) { outcome in
        switch outcome {
        case .failed:
            print("updateCheck=failed")
        case .result(let result):
            print("channel=\(result.channel.rawValue) current=\(result.current) latest=\(result.latest ?? "none") "
                + "updateAvailable=\(result.updateAvailable) page=\(result.releasePage ?? "-")")
        }
        print("automaticInstallationPossible=\(UpdateManifest.automaticInstallationPossible)")
        finished = true
    }
    let deadline = Date().addingTimeInterval(20)
    while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    exit(finished ? 0 : 1)
}

// `Baddel --login-item status|enable|disable` reports or changes "Open at
// login" exactly as the Settings checkbox does, and prints what macOS reports.
// Enabling is refused unless this is the copy in /Applications.
if let index = CommandLine.arguments.firstIndex(of: "--login-item") {
    let action = CommandLine.arguments.dropFirst(index + 1).first ?? "status"
    print("installedCopy=\(LoginItem.isInstalledCopy) path=\(Bundle.main.bundleURL.path == LoginItem.canonicalPath ? "canonical" : "other")")
    switch action {
    case "enable", "disable":
        switch LoginItem.set(action == "enable") {
        case .success(let state): print("\(action)=ok state=\(state.rawValue)")
        case .failure(let failure): print("\(action)=refused reason=\(failure) state=\(LoginItem.state.rawValue)")
        }
    default:
        print("state=\(LoginItem.state.rawValue)")
    }
    exit(0)
}

// `Baddel --reset-accessibility-entry` does what the "Remove Old Entry…" button
// does after its confirmation: it removes Baddel's own entry from the
// Accessibility list. It only ever removes a permission. Used by the checks.
if CommandLine.arguments.contains("--reset-accessibility-entry") {
    let removed = AccessibilityEntry.reset()
    print("accessibilityEntryReset=\(removed)")
    exit(removed ? 0 : 1)
}

// `Baddel --hotkey-coexistence-check` registers two hot keys the way the app
// does (correction = id 1, clipboard = id 2) on two throwaway combinations,
// presses each once, and checks that each press reaches only its own handler.
// It does not use, or interfere with, the real shortcuts.
if CommandLine.arguments.contains("--hotkey-coexistence-check") {
    let first = HotKeyCenter(id: 1), second = HotKeyCenter(id: 2)
    let modifiers = UInt32(controlKey | optionKey | cmdKey | shiftKey)
    let keyA = UInt32(kVK_ANSI_9), keyB = UInt32(kVK_ANSI_0)
    var hits: [Int] = []
    first.onPress = { _ in hits.append(1) }
    second.onPress = { _ in hits.append(2) }
    let registered = first.register(Shortcut(keyCode: keyA, carbonModifiers: modifiers))
        && second.register(Shortcut(keyCode: keyB, carbonModifiers: modifiers))
    print("bothRegistered=\(registered)")
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    func press(_ key: UInt32) {
        // Posted from a background thread, with a pause between down and up, the
        // way a separate process would press the key.
        DispatchQueue.global().async {
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down)
                event?.flags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
                event?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.04)
            }
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { press(keyB) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { press(keyA) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { press(keyB) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
        print("handlerOrder=\(hits.map(String.init).joined(separator: ","))")
        let ok = registered && hits == [2, 1, 2]
        print(ok ? "result=PASS each press reached only its own handler" : "result=FAIL")
        exit(ok ? 0 : 1)
    }
    app.run()
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Menu bar utility: no Dock icon, never steals focus on launch.
application.setActivationPolicy(.accessory)
application.run()
