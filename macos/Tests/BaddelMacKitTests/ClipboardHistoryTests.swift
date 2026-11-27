import AppKit
import XCTest
@testable import BaddelMacKit

final class ClipboardHistoryTests: XCTestCase {
    private func withHistory(
        _ test: (ClipboardHistory, FixtureClipboard, URL) throws -> Void
    ) throws {
        let pasteboard = FixtureClipboard()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BaddelClipboardCheck-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let history = ClipboardHistory(directory: root.appendingPathComponent("history"), pasteboard: pasteboard)
        try test(history, pasteboard, root)
    }

    func testPersistsTextAndSkipsConcealedCopies() throws {
        try withHistory { history, board, root in
            board.clearContents()
            XCTAssertTrue(board.setString("مرحبا", forType: .string))
            history.captureIfChanged()
            XCTAssertEqual(history.entries.map(\.title), ["مرحبا"])

            board.clearContents()
            XCTAssertTrue(board.setString("fixture concealed value", forType: .string))
            board.clipboardTypes.append(.init("org.nspasteboard.ConcealedType"))
            history.captureIfChanged()
            XCTAssertEqual(history.entries.count, 1)

            let reloaded = ClipboardHistory(directory: root.appendingPathComponent("history"), pasteboard: board)
            try reloaded.restore(XCTUnwrap(reloaded.entries.first))
            XCTAssertEqual(board.string(forType: .string), "مرحبا")
            reloaded.captureIfChanged()
            XCTAssertEqual(reloaded.entries.count, 1)
        }
    }

    func testImageCanBeRestored() throws {
        try withHistory { history, board, _ in
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j6sQAAAAASUVORK5CYII=")!
            board.clearContents()
            XCTAssertTrue(board.setData(png, forType: .png))
            history.captureIfChanged()
            let entry = try XCTUnwrap(history.entries.first)
            XCTAssertNotNil(history.image(for: entry))
            board.clearContents()
            try history.restore(entry)
            XCTAssertEqual(board.data(forType: .png), png)
        }
    }

    func testPinnedCopySurvivesDeletedOriginalAndClearRecent() throws {
        try withHistory { history, board, root in
            let original = root.appendingPathComponent("fixture.txt")
            let contents = Data("test file".utf8)
            try contents.write(to: original)
            board.clearContents()
            XCTAssertTrue(board.writeFileURLs([original]))
            history.captureIfChanged()
            let entry = try XCTUnwrap(history.entries.first)
            XCTAssertFalse(entry.isPinned)
            try history.pin(entry)
            try FileManager.default.removeItem(at: original)
            XCTAssertThrowsError(try history.restore(entry))

            board.clearContents()
            XCTAssertTrue(board.setString("another item", forType: .string))
            history.captureIfChanged()
            try history.clearRecent()

            let reloaded = ClipboardHistory(directory: root.appendingPathComponent("history"), pasteboard: board)
            XCTAssertEqual(reloaded.entries.count, 1)
            let pinned = try XCTUnwrap(reloaded.entries.first)
            XCTAssertTrue(pinned.isPinned)
            try reloaded.restore(pinned)
            let saved = try XCTUnwrap(board.readFileURLs().first)
            XCTAssertEqual(try Data(contentsOf: saved), contents)
            try reloaded.remove(pinned)
            XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
        }
    }
}

private final class FixtureClipboard: ClipboardBuffer {
    var changeCount = 0
    var clipboardTypes: [NSPasteboard.PasteboardType] = []
    private var text: String?
    private var payloads: [NSPasteboard.PasteboardType: Data] = [:]
    private var urls: [URL] = []

    @discardableResult
    func clearContents() -> Int {
        changeCount += 1
        clipboardTypes = []
        text = nil
        payloads = [:]
        urls = []
        return changeCount
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? { text }
    func data(forType dataType: NSPasteboard.PasteboardType) -> Data? { payloads[dataType] }
    func readFileURLs() -> [URL] { urls }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        text = string
        clipboardTypes.append(dataType)
        return true
    }

    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        payloads[dataType] = data
        clipboardTypes.append(dataType)
        return true
    }

    func writeFileURLs(_ urls: [URL]) -> Bool {
        self.urls = urls
        clipboardTypes.append(.fileURL)
        return true
    }
}

/// The same behaviour against a real macOS pasteboard. Each test creates its
/// own uniquely named pasteboard and releases it afterwards; the general
/// (system) clipboard is never read or written.
final class ClipboardHistoryRealPasteboardTests: XCTestCase {
    private var directory: URL!
    private var board: NSPasteboard!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("baddel-clip-\(UUID().uuidString)")
        board = NSPasteboard(name: NSPasteboard.Name("app.baddel.tests.\(UUID().uuidString)"))
        XCTAssertNotEqual(board.name, NSPasteboard.general.name)
        board.clearContents()
    }

    override func tearDownWithError() throws {
        board.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    func testTextIsCapturedAndConcealedOrTransientCopiesAreSkipped() throws {
        let history = ClipboardHistory(directory: directory, pasteboard: board)
        board.clearContents()
        XCTAssertTrue(board.setString("fixture one", forType: .string))
        history.captureIfChanged()
        XCTAssertEqual(history.entries.map(\.title), ["fixture one"])

        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
            board.clearContents()
            let item = NSPasteboardItem()
            item.setString("must not be stored", forType: .string)
            item.setString("", forType: NSPasteboard.PasteboardType(marker))
            XCTAssertTrue(board.writeObjects([item]))
            history.captureIfChanged()
            XCTAssertEqual(history.entries.count, 1, marker)
        }
        let stored = try String(contentsOf: directory.appendingPathComponent("history.json"), encoding: .utf8)
        XCTAssertFalse(stored.contains("must not be stored"))

        // Restoring puts the text back on the same board and is not captured again.
        board.clearContents()
        try history.restore(history.entries[0])
        XCTAssertEqual(board.string(forType: .string), "fixture one")
        history.captureIfChanged()
        XCTAssertEqual(history.entries.count, 1)

        // A second instance reads the saved history from disk.
        XCTAssertEqual(ClipboardHistory(directory: directory, pasteboard: board).entries.map(\.title), ["fixture one"])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testImageRoundTripsThroughARealPasteboard() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))

        let history = ClipboardHistory(directory: directory, pasteboard: board)
        board.clearContents()
        XCTAssertTrue(board.setData(png, forType: .png))
        history.captureIfChanged()
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertNotNil(history.image(for: history.entries[0]))

        board.clearContents()
        try history.restore(history.entries[0])
        XCTAssertEqual(board.data(forType: .png), png)
    }

    func testFileReferenceAndKeptCopyThroughARealPasteboard() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source-\(UUID().uuidString).txt")
        try Data("file fixture".utf8).write(to: source)
        let root = directory.appendingPathComponent("store")
        let history = ClipboardHistory(directory: root, pasteboard: board)

        board.clearContents()
        XCTAssertTrue(board.writeObjects([source as NSURL]))
        history.captureIfChanged()
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertFalse(history.entries[0].isPinned)

        // Keep File Copy, then delete the original: the entry still restores.
        try history.pin(history.entries[0])
        XCTAssertTrue(history.entries[0].isPinned)
        try FileManager.default.removeItem(at: source)
        board.clearContents()
        try history.restore(history.entries[0])
        let restored = try XCTUnwrap(board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(try String(contentsOf: restored[0], encoding: .utf8), "file fixture")
        XCTAssertTrue(restored[0].path.hasPrefix(root.resolvingSymlinksInPath().path) || restored[0].path.hasPrefix(root.path))

        // An unpinned reference to a deleted file refuses to restore.
        let second = directory.appendingPathComponent("second.txt")
        try Data("x".utf8).write(to: second)
        board.clearContents()
        XCTAssertTrue(board.writeObjects([second as NSURL]))
        history.captureIfChanged()
        try FileManager.default.removeItem(at: second)
        XCTAssertThrowsError(try history.restore(history.entries[0]))
    }
}
