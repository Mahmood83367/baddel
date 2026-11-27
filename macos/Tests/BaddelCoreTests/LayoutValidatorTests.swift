import XCTest
@testable import BaddelCore

final class LayoutValidatorTests: XCTestCase {
    private func layout(id: String = "custom-test", _ edit: (inout [KeyboardLayout.Key]) -> Void = { _ in }) -> KeyboardLayout {
        var keys = Shared.store.layout(id: "us-english")!.keys
        edit(&keys)
        return KeyboardLayout(id: id, name: "Test", script: .latin, platformIds: [:], keys: keys)
    }

    private func codes(_ layout: KeyboardLayout) -> [String] {
        LayoutValidator.validate(layout).map { "\($0.code.rawValue):\($0.key ?? "-")" }
    }

    func testEveryBuiltInLayoutIsValid() {
        for layout in Shared.store.layouts.values {
            XCTAssertEqual(LayoutValidator.validate(layout).filter(\.isError), [], layout.id)
        }
        XCTAssertEqual(LayoutValidator.standardKeyCodes.count, 47)
        XCTAssertEqual(Shared.store.layout(id: "us-english")!.keys.map(\.code), LayoutValidator.standardKeyCodes)
    }

    func testProblemsAreReported() {
        XCTAssertEqual(codes(layout()), [])
        XCTAssertEqual(codes(layout(id: "Bad Id")), ["invalidId:-"])
        XCTAssertEqual(codes(layout(id: "")), ["invalidId:-"])
        XCTAssertEqual(codes(layout { $0.removeLast() }), ["missingKey:Slash"])
        XCTAssertEqual(codes(layout { $0.append(.init(code: "KeyQ", base: "q", shift: "Q")) }),
                       ["duplicateKey:KeyQ", "duplicateOutput:KeyQ", "duplicateOutput:KeyQ"])
        XCTAssertEqual(codes(layout { $0.append(.init(code: "IntlBackslash", base: "x", shift: "X")) }), ["unknownKey:IntlBackslash"])
        XCTAssertEqual(codes(layout { $0[0] = .init(code: "Backquote", base: "", shift: "~") }), ["emptyBase:Backquote"])
        XCTAssertEqual(codes(layout { $0[0] = .init(code: "Backquote", base: "abcde", shift: "~") }), ["outputTooLong:Backquote"])
        XCTAssertEqual(codes(layout { $0[0] = .init(code: "Backquote", base: " ", shift: "~") }), ["invalidCharacter:Backquote"])
        XCTAssertEqual(codes(layout { $0[0] = .init(code: "Backquote", base: "\u{7}", shift: "~") }), ["invalidCharacter:Backquote"])
        // Two keys typing the same thing is allowed, with a warning.
        let duplicate = LayoutValidator.validate(layout { $0[0] = .init(code: "Backquote", base: "1", shift: "~") })
        XCTAssertEqual(duplicate.map(\.code), [.duplicateOutput])
        XCTAssertFalse(duplicate[0].isError)
    }

    func testCustomLayoutsAreAddedOnlyWhenValidAndNeverReplaceBuiltIns() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("baddel-custom-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func write(_ name: String, _ layout: KeyboardLayout) throws {
            try JSONEncoder().encode(layout).write(to: directory.appendingPathComponent(name))
        }
        try write("a-good.json", layout(id: "custom-dvorak-ish"))
        try write("b-not-prefixed.json", layout(id: "my-layout"))
        try write("c-shadows-built-in.json", layout(id: "us-english"))
        try write("d-missing-key.json", layout(id: "custom-broken") { $0.removeLast() })
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("e-garbage.json"))
        try Data("ignored".utf8).write(to: directory.appendingPathComponent("notes.txt"))

        let (store, reports) = Shared.store.addingCustomLayouts(from: directory)
        XCTAssertEqual(reports.map(\.file), ["a-good.json", "b-not-prefixed.json", "c-shadows-built-in.json", "d-missing-key.json", "e-garbage.json"])
        XCTAssertEqual(reports.map(\.accepted), [true, false, false, false, false])
        XCTAssertEqual(store.layouts.count, Shared.store.layouts.count + 1)
        XCTAssertEqual(store.layout(id: "custom-dvorak-ish")?.platformIds, [:])
        // Built-in layouts are untouched.
        XCTAssertEqual(store.layout(id: "us-english"), Shared.store.layout(id: "us-english"))
        // A missing folder changes nothing.
        let none = Shared.store.addingCustomLayouts(from: directory.appendingPathComponent("missing"))
        XCTAssertEqual(none.store.layouts.count, Shared.store.layouts.count)
        XCTAssertTrue(none.reports.isEmpty)
    }
}
