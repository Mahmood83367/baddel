import AppKit

import BaddelMacKit

// `Baddel --self-check` verifies the pieces that need no user interaction and
// exits: layout data loads and the system accepts the configured shortcut.
if CommandLine.arguments.contains("--self-check") {
    let layouts = (try? BaddelResources.loadLayouts())?.layouts.keys.sorted() ?? []
    let registered = HotKeyCenter().register(Settings.shared.shortcut)
    print("layouts=\(layouts.joined(separator: ","))")
    print("shortcut=\(Settings.shared.shortcut.displayString) registered=\(registered)")
    print("accessibilityTrusted=\(AccessibilityPermission.isGranted)")
    exit(layouts.count == 3 && registered ? 0 : 1)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Menu bar utility: no Dock icon, never steals focus on launch.
application.setActivationPolicy(.accessory)
application.run()
