import Foundation
import ServiceManagement

/// "Open at login", through `SMAppService.mainApp` (macOS 13+).
///
/// This registers the app itself as a login item for the current user. It is
/// the mechanism behind System Settings → General → Login Items, where the
/// user can see it and turn it off at any time. Baddel installs no launch
/// agent or daemon, needs no administrator rights for this, and only changes
/// the setting when the user asks.
public enum LoginItem {
    /// The one place Baddel is installed. Opening at login is only offered from
    /// here, so a copy in Downloads or on a disk image can never register itself.
    public static let canonicalPath = "/Applications/Baddel.app"

    public enum State: String, Equatable {
        /// Registered: Baddel opens when the user logs in.
        case enabled
        /// Not registered.
        case disabled
        /// Registered, but macOS is waiting for the user to allow it in
        /// System Settings → General → Login Items.
        case requiresApproval
        /// macOS could not find the app to register.
        case notFound
    }

    public enum Failure: Error, Equatable {
        /// The app is not running from `/Applications/Baddel.app`.
        case notInstalledInApplications
        /// macOS refused the request.
        case refused
    }

    /// Whether this copy of the app is the installed one.
    public static var isInstalledCopy: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path == canonicalPath
    }

    public static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .disabled
        @unknown default: return .disabled
        }
    }

    /// Turns opening at login on or off. Turning it off always works, wherever
    /// the app is; turning it on requires the installed copy.
    public static func set(_ enabled: Bool) -> Result<State, Failure> {
        do {
            if enabled {
                guard isInstalledCopy else { return .failure(.notInstalledInApplications) }
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            return .success(state)
        } catch {
            return .failure(.refused)
        }
    }

    /// Opens System Settings at Login Items, where the user allows or removes it.
    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Clears Baddel's own entry in the Accessibility list.
///
/// Builds before 0.2.1 were ad-hoc signed, so macOS keeps a separate entry for
/// each of them. After an upgrade the list can show Baddel switched on while
/// the entry belongs to the old copy and does nothing for the new one. Removing
/// the entry lets the user grant access again. This only ever removes a
/// permission, only for Baddel, and only when the user asks for it.
public enum AccessibilityEntry {
    public static let bundleIdentifier = "app.baddel.Baddel"

    @discardableResult
    public static func reset() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleIdentifier]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
