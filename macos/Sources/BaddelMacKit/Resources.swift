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

    /// Where a user can place their own layout files:
    /// `~/Library/Application Support/Baddel/Layouts`, or the folder named by
    /// `BADDEL_CUSTOM_LAYOUTS_DIR`.
    public static var customLayoutsDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["BADDEL_CUSTOM_LAYOUTS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Baddel/Layouts", isDirectory: true)
    }

    /// The built-in layouts plus any valid user-supplied ones. Invalid files
    /// are skipped; the built-in layouts are never changed.
    public static func loadLayouts() throws -> LayoutStore {
        guard let directory = layoutsDirectory() else { throw LayoutStore.LoadError.noLayouts }
        let builtIn = try LayoutStore(directory: directory)
        let (store, reports) = builtIn.addingCustomLayouts(from: customLayoutsDirectory)
        lastCustomLayoutReports = reports
        return store
    }

    public private(set) static var lastCustomLayoutReports: [CustomLayoutReport] = []
}

/// Writes diagnostics to the unified log. Records are built from
/// `DiagnosticEvent`, which cannot carry field text, plus the app's bundle
/// identifier and the element's accessibility role.
public enum DiagnosticsLog {
    private static let logger = Logger(subsystem: "app.baddel", category: "correction")

    /// `detail` is a short code such as `noFocusedElement` or `wake=manual`;
    /// like everything else here it never holds text from a field. Records are
    /// kept by the system log, so `log show --predicate 'subsystem == "app.baddel"'`
    /// can explain a refusal afterwards.
    public static func record(
        _ event: DiagnosticEvent, bundleID: String? = nil, role: String? = nil, detail: String? = nil
    ) {
        logger.notice(
            "\(event.summary, privacy: .public) app=\(bundleID ?? "-", privacy: .public) role=\(role ?? "-", privacy: .public) detail=\(detail ?? "-", privacy: .public)")
    }
}
