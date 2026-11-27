import Foundation
import XCTest
@testable import BaddelCore

enum Shared {
    /// `<repo>/shared`, located relative to this source file.
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared")

    static let store: LayoutStore = try! LayoutStore(directory: directory.appendingPathComponent("layouts"))

    static let cases: Cases = {
        let url = directory.appendingPathComponent("fixtures/cases.json")
        return try! JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
    }()

    static func pair(arabic: String = "arabic-pc") -> LayoutPair {
        LayoutPair(latin: store.layout(id: "us-english")!, arabic: store.layout(id: arabic)!)
    }
}

struct Cases: Decodable {
    struct Conversion: Decodable {
        let name: String, from: String, to: String, input: String, output: String
    }
    struct Plan: Decodable {
        struct Target: Decodable {
            let type: String
            let caret: Int?, location: Int?, length: Int?
        }
        struct Expect: Decodable {
            let location: Int?, length: Int?, replacement: String?, sourceScript: Script?, reject: String?
        }
        let name: String, arabicLayout: String, text: String
        let target: Target
        let hint: Script?
        let expect: Expect

        var correctionTarget: CorrectionTarget {
            switch target.type {
            case "lastWord": return .lastWord(caret: target.caret!)
            case "selection": return .selection(UTF16Range(location: target.location!, length: target.length!))
            default: return .wholeField
            }
        }
    }
    struct DoublePress: Decodable {
        struct Event: Decodable { let type: String; let t: Int? }
        let name: String, windowMs: Int, events: [Event], expect: [String]
    }
    let conversions: [Conversion]
    let plans: [Plan]
    let doublePress: [DoublePress]
}
