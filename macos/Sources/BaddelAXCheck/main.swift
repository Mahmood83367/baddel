// Developer check: runs the real correction engine against the focused text
// field of one application through Accessibility, and prints outcome codes.
// It refuses to touch a field unless it holds exactly the fixture text passed
// with --initial, so it cannot modify unrelated content. No field text is
// printed.
//
//   baddel-axcheck --pid 123 --mode field --initial in.txt --expected out.txt [--undo]
//                  [--select LOC,LEN | --caret N] [--arabic arabic-pc] [--tamper]
import AppKit
import BaddelCore
import BaddelMacKit
import Foundation

func fail(_ message: String) -> Never {
    print("result=FAIL \(message)")
    exit(1)
}

var options: [String: String] = [:]
var flags = Set<String>()
var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let name = arguments.removeFirst()
    guard name.hasPrefix("--") else { fail("unexpected-argument") }
    if ["--undo", "--tamper", "--sources", "--frontmost", "--select-only", "--compare-only", "--click-undo", "--describe", "--paste", "--composer-check"].contains(name) {
        flags.insert(name)
    } else if !arguments.isEmpty {
        options[name] = arguments.removeFirst()
    }
}

guard let store = try? BaddelResources.loadLayouts() else { fail("layouts-not-found") }

if flags.contains("--sources") {
    let switcher = InputSourceSwitcher(store: store)
    switcher.preferredEnglishLayoutID = options["--english"]
    switcher.preferredArabicLayoutID = options["--arabic"]
    print("enabledSources=\(switcher.enabledInputSourceIDs().joined(separator: ","))")
    print("currentSource=\(switcher.currentInputSourceID() ?? "-")")
    print("currentScript=\(switcher.currentScript()?.rawValue ?? "-")")
    print("resolvedArabic=\(switcher.resolvePair()?.arabic.id ?? "-")")
    print("resolvedEnglish=\(switcher.resolvePair()?.latin.id ?? "-")")
    exit(0)
}

// Puts back the input source that was active before a check.
if let id = options["--restore-source"] {
    print("sourceRestored=\(InputSourceSwitcher(store: store).selectInputSource(id: id))")
    exit(0)
}

// `--describe --pid N` reports, read-only, what Baddel sees as the focused
// element of that app: codes, roles and capabilities, never text. It uses the
// same focus provider as the app, so it also asks a Chromium-based app for its
// accessibility tree, exactly as a shortcut press would.
if flags.contains("--describe") {
    guard let pid = options["--pid"].flatMap({ pid_t($0) }) else { fail("missing--pid") }
    let app = NSRunningApplication(processIdentifier: pid)
    let version = app?.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? "-"
    print("accessibilityTrusted=\(AccessibilityPermission.isGranted)")
    print("app=\(app?.bundleIdentifier ?? "-") version=\(version) frontmost=\(app?.isActive ?? false) "
        + "chromiumBased=\(app?.bundleURL.map(WebAccessibility.isChromiumBased) ?? false)")
    let provider = AXFocusProvider(processID: pid)
    provider.pasteFallback = flags.contains("--paste") ? PasteFallback() : nil
    let field = provider.focusedField() as? AXField
    let report = provider.lastReport
    print("foundElement=\(report.foundElement) wake=\(report.wake?.rawValue ?? "-") waitedMs=\(report.waitedMs)")
    guard let field else {
        print("result=noFocusedField")
        exit(0)
    }
    func settable(_ name: String) -> Bool {
        var value: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(field.element, name as CFString, &value) == .success && value.boolValue
    }
    let length = (try? field.readText())?.utf16.count
    print("role=\(field.role) subrole=\(field.subrole.isEmpty ? "-" : field.subrole) secure=\(field.isSecure) "
        + "textLength=\(length.map(String.init) ?? "unreadable") selectionReadable=\((try? field.readSelection()) != nil)")
    print("settable value=\(settable("AXValue")) selectedText=\(settable("AXSelectedText")) selectedTextRange=\(settable("AXSelectedTextRange"))")
    print("result=\(field.isSecure ? "secureField" : field.unsupportedReason ?? "supported")")
    exit(0)
}

// `--composer-check --pid N` exercises Baddel's write path on a web app's
// message box without needing the app in front: it finds the one editable text
// area in the app's focused window, refuses unless that is empty, places a
// fixture, corrects it with `AXField.replace`, verifies the result and puts the
// box back to empty. Nothing is sent, and no existing text is ever touched.
if flags.contains("--composer-check") {
    guard let pid = options["--pid"].flatMap({ pid_t($0) }) else { fail("missing--pid") }
    let application = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(application, 2)
    WebAccessibility.wake(processID: pid, bundleURL: NSRunningApplication(processIdentifier: pid)?.bundleURL)
    func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
    var areas: [AXUIElement] = []
    var deadline = Date().addingTimeInterval(3)
    repeat {
        areas = []
        var queue: [AXUIElement] = (value(application, "AXFocusedWindow")).map { [$0 as! AXUIElement] } ?? []
        var visited = 0
        while !queue.isEmpty, visited < 4000 {
            let element = queue.removeFirst()
            visited += 1
            if value(element, "AXRole") as? String == "AXTextArea" { areas.append(element) }
            queue.append(contentsOf: (value(element, "AXChildren") as? [AXUIElement]) ?? [])
        }
        if areas.isEmpty { Thread.sleep(forTimeInterval: 0.2) }
    } while areas.isEmpty && Date() < deadline
    print("textAreas=\(areas.count)")
    guard areas.count == 1, let element = areas.first else { print("result=SKIP need-exactly-one-text-area"); exit(0) }
    let field = AXField(element: element)
    print("role=\(field.role) supported=\(field.unsupportedReason ?? "yes")")
    // Some editors expose their placeholder as the value of an empty box; the
    // placeholder is marked as such on the element's only child.
    let children = (value(element, "AXChildren") as? [AXUIElement]) ?? []
    let showsPlaceholder = children.count == 1
        && ((value(children[0], "AXDOMClassList") as? [String]) ?? []).contains { $0 == "placeholder" || $0 == "is-empty" }
    guard let empty = try? field.readText(), showsPlaceholder || empty.allSatisfy({ $0.isWhitespace || $0.isNewline }) else {
        print("result=SKIP composer-not-empty")
        exit(0)
    }
    print("emptyState=\(showsPlaceholder ? "placeholder" : "blank")")
    func settle(_ expected: (String) -> Bool) -> String? {
        deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            if let now = try? field.readText(), expected(now) { return now }
            Thread.sleep(forTimeInterval: 0.03)
        }
        return nil
    }
    let fixture = "ugd;l hgsghl"
    AXUIElementSetAttributeValue(element, "AXValue" as CFString, fixture as CFString)
    guard let placed = settle({ $0.hasPrefix(fixture) }) else {
        AXUIElementSetAttributeValue(element, "AXValue" as CFString, (showsPlaceholder ? "" : empty) as CFString)
        print("result=SKIP fixture-could-not-be-placed")
        exit(0)
    }
    print("fixturePlaced=true trailing=\(placed.utf16.count - fixture.utf16.count)")
    var outcome = "FAIL"
    let pair = LayoutPair(latin: store.layout(id: "us-english")!, arabic: store.layout(id: "arabic-mac")!)
    if case .success(let plan) = CorrectionPlanner(pair: pair).plan(text: placed, target: .wholeField, hint: nil) {
        do {
            try field.replace(range: plan.range, in: placed, with: plan.replacement)
            let corrected = (try? field.readText()) ?? ""
            let ok = corrected.hasPrefix("عليكم السلام")
            outcome = ok ? "PASS" : "FAIL"
            print("replaced strategy=\(field.lastWriteStrategy) verified=\(ok)")
            // The reverse direction, as Undo does it.
            if ok, case .success(let back) = CorrectionPlanner(pair: pair).plan(text: corrected, target: .wholeField, hint: nil) {
                try field.replace(range: back.range, in: corrected, with: back.replacement)
                print("undoLikeReplace verified=\(((try? field.readText()) ?? "").hasPrefix(fixture)) strategy=\(field.lastWriteStrategy)")
            }
        } catch {
            print("replaceRejected=\((error as? Rejection)?.rawValue ?? "error")")
        }
    }
    AXUIElementSetAttributeValue(element, "AXValue" as CFString, (showsPlaceholder ? "" : empty) as CFString)
    let restored = settle({ $0 == empty || $0.allSatisfy({ $0.isWhitespace || $0.isNewline }) }) != nil
    print("composerRestoredToEmpty=\(restored)")
    print("result=\(outcome)")
    exit(outcome == "PASS" && restored ? 0 : 1)
}

if flags.contains("--frontmost") {
    print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")
    exit(0)
}

// Posts the default Baddel shortcut (Option-Shift-Space) as distinct presses,
// each with its own key-up, to exercise the running app end to end.
if let presses = options["--press"].flatMap({ Int($0) }) {
    let gap = options["--gap-ms"].flatMap { Double($0) } ?? 120
    let source = CGEventSource(stateID: .privateState)
    for index in 0..<presses {
        if index > 0 { Thread.sleep(forTimeInterval: gap / 1000) }
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: keyDown)
            event?.flags = [.maskAlternate, .maskShift]
            event?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.03)
        }
    }
    print("posted=\(presses)")
    exit(0)
}

// Finds Baddel's on-screen Undo panel, reports whether it sits next to the
// given text range, and clicks its Undo button with a real mouse click.
if flags.contains("--click-undo") {
    let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    let panel = windows.first { ($0[kCGWindowOwnerName as String] as? String) == "Baddel" }
    guard let boundsValue = panel?[kCGWindowBounds as String],
          let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary)
    else { fail("undo-panel-not-on-screen") }
    print("undoPanelVisible=true")
    if let pid = options["--pid"].flatMap({ pid_t($0) }),
       let range = options["--near-range"]?.split(separator: ",").compactMap({ Int($0) }), range.count == 2,
       let field = AXFocusProvider(processID: pid).focusedField() as? AXField,
       let text = field.bounds(for: UTF16Range(location: range[0], length: range[1])) {
        // Both rectangles use top-left screen coordinates.
        let gap = bounds.minY - text.maxY
        print("panelBelowEditedText=\(gap >= 0 && gap <= 16) horizontalOffset=\(Int(abs(bounds.minX - text.minX)))")
    } else {
        print("panelBelowEditedText=unknown")
    }
    let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
    let restore = CGEvent(source: nil)?.location
    let point = CGPoint(x: bounds.maxX - 34, y: bounds.midY)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
    }
    Thread.sleep(forTimeInterval: 0.4)
    if let restore { CGWarpMouseCursorPosition(restore) }
    let after = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
    print("frontmostUnchangedByClick=\(before == after) frontmost=\(after)")
    exit(before == after ? 0 : 1)
}

func read(_ option: String) -> String {
    guard let path = options[option], let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("missing\(option)")
    }
    return text
}

print("accessibilityTrusted=\(AccessibilityPermission.isGranted)")
guard AccessibilityPermission.isGranted else { fail("accessibility-not-granted") }
guard let pid = options["--pid"].flatMap({ pid_t($0) }) else { fail("missing--pid") }
if flags.contains("--compare-only") {
    let text = (AXFocusProvider(processID: pid).focusedField() as? AXField).flatMap { try? $0.readText() }
    let matches = text == read("--expected")
    print("matchesExpected=\(matches)")
    exit(matches ? 0 : 1)
}
let initial = read("--initial")
if flags.contains("--select-only") {
    guard let target = AXFocusProvider(processID: pid).focusedField() as? AXField,
          (try? target.readText()) == initial else { fail("field-does-not-hold-fixture-text") }
    target.setSelection(UTF16Range(location: Int(options["--caret"] ?? "") ?? 0, length: 0))
    print("selectionSet=\((try? target.readSelection())?.location ?? -1)")
    exit(0)
}
let expected = read("--expected")
let mode: CorrectionEngine.Mode = options["--mode"] == "field" ? .wholeField : .selectionOrLastWord

guard let arabic = store.layout(id: options["--arabic"] ?? "arabic-pc"), let latin = store.layout(id: "us-english")
else { fail("unknown-layout") }

let focus = AXFocusProvider(processID: pid)
guard let field = focus.focusedField() as? AXField else { fail("no-focused-element") }
print("role=\(field.role) subrole=\(field.subrole.isEmpty ? "-" : field.subrole)")
print("secure=\(field.isSecure) editableText=\(field.isEditableText)")
if field.isSecure {
    // Expected outcome for a secure field: the engine refuses.
    let engine = CorrectionEngine(
        planner: CorrectionPlanner(pair: LayoutPair(latin: latin, arabic: arabic)),
        focus: focus, layouts: InertLayoutSwitcher())
    if case .failure(let rejection) = engine.correct(mode: mode, capturedField: field) {
        print("correction=rejected reason=\(rejection.rawValue)")
        print(rejection == .secureField ? "result=PASS" : "result=FAIL")
        exit(rejection == .secureField ? 0 : 1)
    }
    fail("secure-field-was-modified")
}
guard (try? field.readText()) == initial else { fail("field-does-not-hold-fixture-text") }

if let selection = options["--select"]?.split(separator: ",").compactMap({ Int($0) }), selection.count == 2 {
    field.setSelection(UTF16Range(location: selection[0], length: selection[1]))
} else if let caret = options["--caret"].flatMap({ Int($0) }) {
    field.setSelection(UTF16Range(location: caret, length: 0))
}
if let selection = try? field.readSelection() {
    print("selection=\(selection.location),\(selection.length)")
}

let engine = CorrectionEngine(
    planner: CorrectionPlanner(pair: LayoutPair(latin: latin, arabic: arabic)),
    focus: focus, layouts: InertLayoutSwitcher())

switch engine.correct(mode: mode, capturedField: field) {
case .failure(let rejection):
    print("correction=rejected reason=\(rejection.rawValue)")
    let unchanged = (try? field.readText()) == initial
    print("fieldUnchanged=\(unchanged)")
    if options["--expect-reject"] == rejection.rawValue, unchanged {
        print("result=PASS")
        exit(0)
    }
    fail("unexpected-rejection")
case .success(let success):
    let after = (focus.focusedField() as? AXField).flatMap { try? $0.readText() }
    print("correction=ok strategy=\((success.undo.field as? AXField)?.lastWriteStrategy ?? "-")")
    print("replacedRange=\(success.undo.replacedRange.location),\(success.undo.replacedRange.length)")
    print("matchesExpected=\(after == expected)")
    print("rangeBounds=\(field.bounds(for: success.undo.replacedRange) != nil) fieldFrame=\(field.frame != nil)")
    if let selection = try? field.readSelection() {
        print("selectionAfter=\(selection.location),\(selection.length)")
    }
    guard after == expected else { fail("text-mismatch") }

    if flags.contains("--tamper") {
        // Change the field behind the engine's back; undo must refuse.
        field.setSelection(UTF16Range(location: 0, length: 0))
        _ = try? field.replace(range: UTF16Range(location: 0, length: 0), in: expected, with: "x")
        if case .failure(let rejection) = engine.undo(success.undo) {
            print("undoAfterTamper=rejected reason=\(rejection.rawValue)")
            let untouched = (try? field.readText()) == "x" + expected
            print("fieldUntouchedByUndo=\(untouched)")
            print(rejection == .undoStateChanged && untouched ? "result=PASS" : "result=FAIL")
            exit(rejection == .undoStateChanged && untouched ? 0 : 1)
        }
        fail("undo-ran-on-changed-field")
    }
    if flags.contains("--undo") {
        switch engine.undo(success.undo) {
        case .success:
            let restored = (try? field.readText()) == initial
            print("undo=ok restoredOriginal=\(restored)")
            guard restored else { fail("undo-mismatch") }
        case .failure(let rejection):
            print("undo=rejected reason=\(rejection.rawValue)")
            fail("undo-rejected")
        }
    }
    print("result=PASS")
}
