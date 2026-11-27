// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Baddel",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BaddelCore", targets: ["BaddelCore"]),
        .executable(name: "Baddel", targets: ["Baddel"]),
        .executable(name: "baddel-axcheck", targets: ["BaddelAXCheck"]),
    ],
    targets: [
        // Platform-independent conversion and correction logic (Foundation only).
        .target(name: "BaddelCore"),
        // macOS integrations: Accessibility, input sources, hot key, pasteboard.
        .target(name: "BaddelMacKit", dependencies: ["BaddelCore"]),
        // The menu bar app.
        .executableTarget(name: "Baddel", dependencies: ["BaddelCore", "BaddelMacKit"]),
        // Developer tool: runs the correction engine against another app's
        // focused field through Accessibility and reports outcome codes only.
        .executableTarget(name: "BaddelAXCheck", dependencies: ["BaddelCore", "BaddelMacKit"]),
        .testTarget(name: "BaddelCoreTests", dependencies: ["BaddelCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
