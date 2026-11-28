import XCTest
@testable import BaddelMacKit

final class WebAccessibilityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("baddel-web-ax-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func bundle(_ name: String, containing paths: [String]) throws -> URL {
        let url = root.appendingPathComponent(name)
        for path in paths {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        return url
    }

    /// The renderer helper is what identifies a Chromium embedder; only such an
    /// app is ever given `AXEnhancedUserInterface`.
    func testChromiumBundlesAreRecognisedByTheirRendererHelper() throws {
        let electron = try bundle("Electron.app", containing: [
            "Contents/Frameworks/Electron Framework.framework",
            "Contents/Frameworks/Sample Helper (Renderer).app",
        ])
        let browser = try bundle("Browser.app", containing: [
            "Contents/Frameworks/Sample Framework.framework/Versions/A/Helpers/Sample Helper (Renderer).app",
        ])
        let embedded = try bundle("Embedded.app", containing: [
            "Contents/Frameworks/Sample Framework.framework/Helpers/Sample Helper (Renderer).app",
        ])
        let renamed = try bundle("Renamed.app", containing: [
            "Contents/Frameworks/Sample Framework.framework/Helpers/Sample (Renderer).app",
        ])
        XCTAssertTrue(WebAccessibility.isChromiumBased(bundleURL: renamed))
        let native = try bundle("Native.app", containing: [
            "Contents/Frameworks/Sparkle.framework/Versions/A/Resources",
            "Contents/Frameworks/Sample Helper.app",
        ])
        let bare = try bundle("Bare.app", containing: ["Contents/MacOS"])
        XCTAssertTrue(WebAccessibility.isChromiumBased(bundleURL: electron))
        XCTAssertTrue(WebAccessibility.isChromiumBased(bundleURL: browser))
        XCTAssertTrue(WebAccessibility.isChromiumBased(bundleURL: embedded))
        XCTAssertFalse(WebAccessibility.isChromiumBased(bundleURL: native))
        XCTAssertFalse(WebAccessibility.isChromiumBased(bundleURL: bare))
    }

    /// A process that is not an application is left alone.
    func testWakeChangesNothingForAnUnknownProcess() {
        XCTAssertEqual(WebAccessibility.wake(processID: 1, bundleURL: nil), .notApplicable)
    }
}
