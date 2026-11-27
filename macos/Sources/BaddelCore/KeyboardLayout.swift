import Foundation

/// The script a keyboard layout primarily produces.
public enum Script: String, Codable, Sendable {
    case latin
    case arabic

    public var opposite: Script { self == .latin ? .arabic : .latin }
}

/// A keyboard layout described by the output of each physical key.
///
/// The data lives in `shared/layouts/*.json` and is shared with the Windows
/// implementation. Keys are identified by W3C `KeyboardEvent.code` names and
/// are stored in a fixed order, which makes reverse lookups deterministic.
public struct KeyboardLayout: Codable, Equatable, Sendable {
    public struct Key: Codable, Equatable, Sendable {
        public let code: String
        public let base: String
        public let shift: String

        public init(code: String, base: String, shift: String) {
            self.code = code
            self.base = base
            self.shift = shift
        }
    }

    public let id: String
    public let name: String
    public let script: Script
    /// Platform-specific identifiers, e.g. `"macos": ["com.apple.keylayout.US"]`.
    public let platformIds: [String: [String]]
    public let keys: [Key]

    public init(id: String, name: String, script: Script, platformIds: [String: [String]], keys: [Key]) {
        self.id = id
        self.name = name
        self.script = script
        self.platformIds = platformIds
        self.keys = keys
    }
}

/// The two layouts a correction converts between.
public struct LayoutPair: Equatable, Sendable {
    public let latin: KeyboardLayout
    public let arabic: KeyboardLayout

    public init(latin: KeyboardLayout, arabic: KeyboardLayout) {
        self.latin = latin
        self.arabic = arabic
    }

    public func layout(for script: Script) -> KeyboardLayout {
        script == .latin ? latin : arabic
    }
}

/// Loads layout definitions from a directory of JSON files.
public struct LayoutStore: Sendable {
    public enum LoadError: Error { case noLayouts }

    public let layouts: [String: KeyboardLayout]

    public init(layouts: [KeyboardLayout]) {
        self.layouts = Dictionary(layouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public init(directory: URL) throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder()
        let loaded = try files.map { try decoder.decode(KeyboardLayout.self, from: Data(contentsOf: $0)) }
        guard !loaded.isEmpty else { throw LoadError.noLayouts }
        self.init(layouts: loaded)
    }

    public func layout(id: String) -> KeyboardLayout? { layouts[id] }

    public func layout(platform: String, platformID: String) -> KeyboardLayout? {
        layouts.values
            .sorted { $0.id < $1.id }
            .first { $0.platformIds[platform]?.contains(platformID) == true }
    }
}
