import XCTest
@testable import BaddelCore

/// Runs `shared/fixtures/text-fix.json`, which the .NET test suite runs as well.
final class TextFixTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Case: Decodable {
            struct Expect: Decodable { let text: String?, cursor: Int?, reject: String? }
            let name: String, arabicLayout: String, text: String, mode: String, unit: String
            let cursor: Int?, selection: [Int]?, hint: Script?, claude: Bool
            let expect: Expect
        }
        let cases: [Case]
    }

    func testSharedCases() throws {
        let url = Shared.directory.appendingPathComponent("fixtures/text-fix.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(fixture.cases.count, 20)
        for c in fixture.cases {
            let request = TextFix.Request(
                text: c.text, mode: TextFix.Mode(rawValue: c.mode)!, unit: TextFix.Unit(rawValue: c.unit)!,
                cursor: c.cursor, selection: c.selection.map { UTF16Range(location: $0[0], length: $0[1]) },
                hint: c.hint, keepsClaudePlaceholders: c.claude)
            switch TextFix.run(request, planner: CorrectionPlanner(pair: Shared.pair(arabic: c.arabicLayout))) {
            case .success(let output):
                XCTAssertNil(c.expect.reject, c.name)
                XCTAssertEqual(output.text, c.expect.text, c.name)
                XCTAssertEqual(output.cursor, c.expect.cursor, c.name)
            case .failure(let rejection):
                XCTAssertEqual(rejection.rawValue, c.expect.reject, c.name)
            }
        }
    }

    func testCursorUnitsRoundTrip() {
        let text = "a😀ب c"
        for unit in [TextFix.Unit.utf16, .scalars, .bytes] {
            let end = TextFix.position(ofUTF16: text.utf16.count, unit: unit, in: text)
            XCTAssertEqual(TextFix.utf16Offset(of: end, unit: unit, in: text), text.utf16.count)
            XCTAssertNil(TextFix.utf16Offset(of: end + 1, unit: unit, in: text))
        }
        XCTAssertEqual(TextFix.position(ofUTF16: 2, unit: .scalars, in: text), 1, "inside the emoji counts as before it")
        XCTAssertNil(TextFix.utf16Offset(of: 2, unit: .bytes, in: text), "inside the emoji's bytes")
    }

    func testOversizedBufferIsRefused() {
        let text = String(repeating: "a", count: CorrectionEngine.maxFieldLength + 1)
        let result = TextFix.run(TextFix.Request(text: text, mode: .line), planner: CorrectionPlanner(pair: Shared.pair()))
        XCTAssertEqual(result, .failure(.fieldTooLarge))
    }
}
