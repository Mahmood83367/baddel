import BaddelCore
import Carbon
import Foundation

/// Reads and selects keyboard input sources through Text Input Sources.
/// Only sources the user has already enabled are ever selected.
public final class InputSourceSwitcher: LayoutSwitching {
    private let store: LayoutStore
    /// Layout id (`arabic-mac` / `arabic-pc`) to prefer, or `nil` for automatic.
    public var preferredArabicLayoutID: String?

    public init(store: LayoutStore) {
        self.store = store
    }

    private func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
    }

    private func identifier(_ source: TISInputSource) -> String? {
        property(source, kTISPropertyInputSourceID)
    }

    private func script(of source: TISInputSource) -> Script? {
        if let id = identifier(source), let layout = store.layout(platform: "macos", platformID: id) {
            return layout.script
        }
        let languages: [String] = property(source, kTISPropertyInputSourceLanguages) ?? []
        if languages.first == "ar" { return .arabic }
        let asciiCapable: Bool = property(source, kTISPropertyInputSourceIsASCIICapable) ?? false
        return asciiCapable ? .latin : nil
    }

    /// Enabled, selectable keyboard input sources.
    private func enabledSources() -> [TISInputSource] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    public func enabledInputSourceIDs() -> [String] {
        enabledSources().compactMap(identifier)
    }

    public func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return identifier(source)
    }

    public func currentScript() -> Script? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return script(of: source)
    }

    /// The layouts to convert between: US English and the user's Arabic
    /// layout (the preferred one, else the first enabled known Arabic layout,
    /// else macOS Arabic).
    public func resolvePair() -> LayoutPair? {
        guard let latin = store.layout(id: "us-english") else { return nil }
        var arabic = preferredArabicLayoutID.flatMap { store.layout(id: $0) }
        if arabic == nil {
            arabic = enabledInputSourceIDs()
                .compactMap { store.layout(platform: "macos", platformID: $0) }
                .first { $0.script == .arabic }
        }
        guard let arabic = arabic ?? store.layout(id: "arabic-mac") else { return nil }
        return LayoutPair(latin: latin, arabic: arabic)
    }

    public func selectLayout(for script: Script) -> Bool {
        let candidates = enabledSources().filter { self.script(of: $0) == script }
        guard !candidates.isEmpty else { return false }
        let wanted = script == .arabic ? resolvePair()?.arabic : store.layout(id: "us-english")
        let preferredIDs = wanted?.platformIds["macos"] ?? []
        let choice = candidates.first { source in identifier(source).map(preferredIDs.contains) ?? false }
            ?? candidates[0]
        return TISSelectInputSource(choice) == noErr
    }

    public func selectInputSource(id: String) -> Bool {
        guard let source = enabledSources().first(where: { identifier($0) == id }) else { return false }
        return TISSelectInputSource(source) == noErr
    }
}

/// A switcher that never changes anything; used by checks that must not touch
/// the user's active layout.
public final class InertLayoutSwitcher: LayoutSwitching {
    private let script: Script?
    public init(script: Script? = nil) { self.script = script }
    public func currentInputSourceID() -> String? { nil }
    public func currentScript() -> Script? { script }
    public func selectLayout(for script: Script) -> Bool { false }
    public func selectInputSource(id: String) -> Bool { false }
}
