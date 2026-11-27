import BaddelCore
import Foundation
import os

public enum BaddelResources {
    /// Finds the layout JSON directory: inside the app bundle, from the
    /// `BADDEL_LAYOUTS_DIR` environment variable, or by walking up from the
    /// executable to the repository's `shared/layouts` (development builds).
    public static func layoutsDirectory() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("layouts"))
        }
        if let override = ProcessInfo.processInfo.environment["BADDEL_LAYOUTS_DIR"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        var directory = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0..<8 {
            directory.deleteLastPathComponent()
            candidates.append(directory.appendingPathComponent("shared/layouts"))
        }
        return candidates.first { fileManager.fileExists(atPath: $0.appendingPathComponent("us-english.json").path) }
    }

    public static func loadLayouts() throws -> LayoutStore {
        guard let directory = layoutsDirectory() else { throw LayoutStore.LoadError.noLayouts }
        return try LayoutStore(directory: directory)
    }
}

/// Writes diagnostics to the unified log. Records are built from
/// `DiagnosticEvent`, which cannot carry field text, plus the app's bundle
/// identifier and the element's accessibility role.
public enum DiagnosticsLog {
    private static let logger = Logger(subsystem: "app.baddel", category: "correction")

    public static func record(_ event: DiagnosticEvent, bundleID: String? = nil, role: String? = nil) {
        logger.info(
            "\(event.summary, privacy: .public) app=\(bundleID ?? "-", privacy: .public) role=\(role ?? "-", privacy: .public)")
    }
}
