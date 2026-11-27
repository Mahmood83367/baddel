import XCTest
@testable import BaddelCore

/// Runs the fixtures in `shared/fixtures/cases.json`, which the Windows
/// implementation runs as well.
final class SharedFixtureTests: XCTestCase {
    func testLayoutsLoad() {
        XCTAssertEqual(Set(Shared.store.layouts.keys), ["us-english", "arabic-mac", "arabic-pc"])
        for layout in Shared.store.layouts.values {
            XCTAssertEqual(layout.keys.count, 47, layout.id)
            XCTAssertEqual(Set(layout.keys.map(\.code)).count, 47, layout.id)
        }
        XCTAssertEqual(Shared.store.layout(platform: "macos", platformID: "com.apple.keylayout.ABC")?.id, "us-english")
        XCTAssertEqual(Shared.store.layout(platform: "macos", platformID: "com.apple.keylayout.ArabicPC")?.id, "arabic-pc")
        XCTAssertNil(Shared.store.layout(platform: "macos", platformID: "com.apple.keylayout.French"))
    }

    func testConversions() {
        XCTAssertGreaterThan(Shared.cases.conversions.count, 20)
        for c in Shared.cases.conversions {
            let converter = LayoutConverter(
                from: Shared.store.layout(id: c.from)!, to: Shared.store.layout(id: c.to)!)
            XCTAssertEqual(converter.convert(c.input), c.output, c.name)
        }
    }

    func testPlans() {
        XCTAssertGreaterThan(Shared.cases.plans.count, 30)
        for c in Shared.cases.plans {
            let planner = CorrectionPlanner(pair: Shared.pair(arabic: c.arabicLayout))
            switch planner.plan(text: c.text, target: c.correctionTarget, hint: c.hint) {
            case .success(let plan):
                XCTAssertNil(c.expect.reject, c.name)
                XCTAssertEqual(plan.range.location, c.expect.location, c.name)
                XCTAssertEqual(plan.range.length, c.expect.length, c.name)
                XCTAssertEqual(plan.replacement, c.expect.replacement, c.name)
                XCTAssertEqual(plan.sourceScript, c.expect.sourceScript, c.name)
            case .failure(let rejection):
                XCTAssertEqual(rejection.rawValue, c.expect.reject, c.name)
            }
        }
    }

    func testDoublePress() {
        XCTAssertGreaterThan(Shared.cases.doublePress.count, 5)
        for c in Shared.cases.doublePress {
            var detector = DoublePressDetector(windowMs: c.windowMs)
            var actions: [String] = []
            for event in c.events {
                switch event.type {
                case "press": actions.append(detector.press(atMs: event.t!, isRepeat: false).rawValue)
                case "repeat": actions.append(detector.press(atMs: event.t!, isRepeat: true).rawValue)
                case "release": detector.release(); actions.append("none")
                case "timeout": actions.append(detector.timeout(generation: detector.generation).rawValue)
                case "staleTimeout": actions.append(detector.timeout(generation: detector.generation - 1).rawValue)
                default: XCTFail("unknown event \(event.type)")
                }
            }
            XCTAssertEqual(actions, c.expect, c.name)
        }
    }

    /// Converting to the other layout and back returns the same key for
    /// every key of the US layout, pressed on its own.
    func testRoundTripFromUS() {
        let us = Shared.store.layout(id: "us-english")!
        for arabicID in ["arabic-pc", "arabic-mac"] {
            let arabic = Shared.store.layout(id: arabicID)!
            let there = LayoutConverter(from: us, to: arabic)
            let back = LayoutConverter(from: arabic, to: us)
            for key in us.keys {
                XCTAssertEqual(back.convert(there.convert(key.base)), key.base, "\(arabicID) \(key.code)")
            }
        }
    }

    /// Documented ambiguity: on Arabic-PC, `g` then `h` produces the same text
    /// as the `b` key, and the reverse conversion prefers the single key.
    func testLamAlefAmbiguityPrefersSingleKey() {
        let us = Shared.store.layout(id: "us-english")!
        let pc = Shared.store.layout(id: "arabic-pc")!
        XCTAssertEqual(LayoutConverter(from: pc, to: us).convert(LayoutConverter(from: us, to: pc).convert("gh")), "b")
    }
}
