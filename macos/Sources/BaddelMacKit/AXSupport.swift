import ApplicationServices
import Foundation

/// Thin, typed wrappers over the Accessibility C API.
enum AX {
    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    static func rect(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    static func rangeValue(location: Int, length: Int) -> AXValue? {
        var range = CFRange(location: location, length: length)
        return AXValueCreate(.cfRange, &range)
    }
}

/// Chromium-based apps (Electron apps such as Claude, the ChatGPT desktop app,
/// browsers) build their accessibility tree only once an assistive client asks
/// for it. Until then such an app reports no focused element at all, so a
/// correction would be refused before any field was looked at.
///
/// `wake` asks one app to expose its tree, using the switches Chromium
/// documents for this: `AXManualAccessibility` (Electron; no side effects) and,
/// where an app does not offer that, `AXEnhancedUserInterface`. The second one
/// is only set on an app whose bundle is positively identified as Chromium
/// based, and `restoreEnhanced` puts it back, because some window tools react
/// to it. Nothing here reads or changes any text.
public enum WebAccessibility {
    public enum Wake: String, Sendable {
        /// This process already asked this app (the tree may still be building).
        case alreadyAsked
        /// `AXManualAccessibility` was set.
        case manual
        /// `AXEnhancedUserInterface` was set on a Chromium-based app.
        case enhanced
        /// Not an app this applies to; nothing was changed.
        case notApplicable
    }

    private static var asked: [pid_t: Wake] = [:]
    private static var enhancedSince: [pid_t: Date] = [:]

    /// Whether the app's bundle contains Chromium's renderer helper, which
    /// every Chromium embedder ships (Electron, Chrome, Edge, CEF and the
    /// ChatGPT app's own framework).
    public static func isChromiumBased(bundleURL: URL) -> Bool {
        let fileManager = FileManager.default
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks")
        guard let entries = try? fileManager.contentsOfDirectory(atPath: frameworks.path) else { return false }
        func isRendererHelper(_ name: String) -> Bool { name.hasSuffix("Helper (Renderer).app") }
        if entries.contains(where: isRendererHelper) { return true }
        for entry in entries where entry.hasSuffix(".framework") {
            for helpers in ["Helpers", "Versions/A/Helpers", "Versions/Current/Helpers"] {
                let path = frameworks.appendingPathComponent(entry).appendingPathComponent(helpers).path
                if let names = try? fileManager.contentsOfDirectory(atPath: path), names.contains(where: isRendererHelper) {
                    return true
                }
            }
        }
        return false
    }

    /// Asks the app to expose its accessibility tree. Safe to call repeatedly.
    @discardableResult
    public static func wake(processID: pid_t, bundleURL: URL?) -> Wake {
        if asked[processID] != nil { return .alreadyAsked }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 1.0)
        if AX.set(application, "AXManualAccessibility", kCFBooleanTrue) {
            asked[processID] = .manual
            return .manual
        }
        guard let bundleURL, isChromiumBased(bundleURL: bundleURL) else { return .notApplicable }
        if (AX.copy(application, "AXEnhancedUserInterface") as? Bool) != true,
           !AX.set(application, "AXEnhancedUserInterface", kCFBooleanTrue) {
            return .notApplicable
        }
        asked[processID] = .enhanced
        enhancedSince[processID] = Date()
        return .enhanced
    }

    /// Marks an app Baddel set `AXEnhancedUserInterface` on as still in use.
    public static func touch(processID: pid_t) {
        if enhancedSince[processID] != nil { enhancedSince[processID] = Date() }
    }

    /// Clears `AXEnhancedUserInterface` on apps where Baddel set it and has not
    /// used it for `idle` seconds, and forgets processes that have exited.
    public static func restoreEnhanced(idleFor idle: TimeInterval) {
        let now = Date()
        for (processID, since) in enhancedSince where now.timeIntervalSince(since) >= idle {
            AX.set(AXUIElementCreateApplication(processID), "AXEnhancedUserInterface", kCFBooleanFalse)
            enhancedSince[processID] = nil
            asked[processID] = nil
        }
        for processID in asked.keys where kill(processID, 0) != 0 { asked[processID] = nil }
    }
}

public enum AccessibilityPermission {
    /// Whether the user has granted this process Accessibility access.
    /// Never prompts.
    public static var isGranted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show its own "would like to control this computer"
    /// dialog. Only called from an explicit user action.
    public static func requestSystemPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}
