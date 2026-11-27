/// Converts text that was typed with `source` active into what the same
/// physical key presses would have produced with `target` active.
///
/// The converter works on UTF-16 code units. Every layout output is in the
/// Basic Multilingual Plane, so code units that are not produced by the source
/// layout (including surrogate pairs, emoji and whitespace) pass through
/// untouched.
///
/// Rules:
/// - Reverse lookup prefers unshifted keys over shifted ones, then the key
///   order of the layout file.
/// - Multi-character outputs (Arabic-PC `لا`, `لأ`, `لإ`, `لآ`) are matched
///   longest-first, so `لا` maps back to the single key that produces it.
/// - If the target has no output for a shifted key, the unshifted output of the
///   same key is used. If that is empty too, the text passes through.
public struct LayoutConverter: Sendable {
    public let sourceID: String
    public let targetID: String
    private let table: [[UInt16]: [UInt16]]
    private let maxLength: Int

    public init(from source: KeyboardLayout, to target: KeyboardLayout) {
        sourceID = source.id
        targetID = target.id
        let targetKeys = Dictionary(target.keys.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        var table: [[UInt16]: [UInt16]] = [:]
        var maxLength = 1
        for shifted in [false, true] {
            for key in source.keys {
                let output = Array((shifted ? key.shift : key.base).utf16)
                guard !output.isEmpty, table[output] == nil, let targetKey = targetKeys[key.code] else { continue }
                var replacement = shifted ? targetKey.shift : targetKey.base
                if replacement.isEmpty { replacement = targetKey.base }
                guard !replacement.isEmpty else { continue }
                table[output] = Array(replacement.utf16)
                maxLength = max(maxLength, output.count)
            }
        }
        self.table = table
        self.maxLength = maxLength
    }

    public func convert(_ units: [UInt16]) -> [UInt16] {
        var result: [UInt16] = []
        result.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            var matched = false
            var length = min(maxLength, units.count - index)
            while length >= 1 {
                if let replacement = table[Array(units[index..<(index + length)])] {
                    result.append(contentsOf: replacement)
                    index += length
                    matched = true
                    break
                }
                length -= 1
            }
            if !matched {
                result.append(units[index])
                index += 1
            }
        }
        return result
    }

    public func convert(_ text: String) -> String {
        String(decoding: convert(Array(text.utf16)), as: UTF16.self)
    }
}
