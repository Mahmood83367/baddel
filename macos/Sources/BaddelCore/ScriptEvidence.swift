/// Decides which layout a piece of text was most likely typed with.
///
/// Evidence comes in two strengths:
/// - **strong**: letters of a script (Arabic letters and marks, Latin letters);
/// - **weak**: non-letters that only one of the two layouts can produce, such
///   as `;` (US only) or `؟` and Arabic-Indic digits (Arabic only).
///
/// Characters both layouts can produce (`-`, `!`, …) and everything else are
/// neutral.
public struct ScriptEvidence: Sendable {
    public struct Counts: Equatable, Sendable {
        public var strongLatin = 0
        public var strongArabic = 0
        public var weakLatin = 0
        public var weakArabic = 0

        public init() {}

        public static func + (a: Counts, b: Counts) -> Counts {
            var r = Counts()
            r.strongLatin = a.strongLatin + b.strongLatin
            r.strongArabic = a.strongArabic + b.strongArabic
            r.weakLatin = a.weakLatin + b.weakLatin
            r.weakArabic = a.weakArabic + b.weakArabic
            return r
        }

        /// The script this text belongs to, `nil` when it has no evidence or
        /// evidence of both scripts at the deciding strength.
        public var uniformScript: Script? {
            if strongLatin > 0 || strongArabic > 0 {
                if strongArabic == 0 { return .latin }
                if strongLatin == 0 { return .arabic }
                return nil
            }
            if weakLatin > 0, weakArabic == 0 { return .latin }
            if weakArabic > 0, weakLatin == 0 { return .arabic }
            return nil
        }

        /// The script with more evidence: strong evidence first, weak evidence
        /// as a tie-breaker. `nil` on a full tie.
        public var dominantScript: Script? {
            if strongLatin != strongArabic { return strongLatin > strongArabic ? .latin : .arabic }
            if weakLatin != weakArabic { return weakLatin > weakArabic ? .latin : .arabic }
            return nil
        }
    }

    private let latinOnly: Set<UInt16>
    private let arabicOnly: Set<UInt16>

    public init(pair: LayoutPair) {
        func units(_ layout: KeyboardLayout) -> Set<UInt16> {
            var set = Set<UInt16>()
            for key in layout.keys {
                set.formUnion(key.base.utf16)
                set.formUnion(key.shift.utf16)
            }
            return set
        }
        let latin = units(pair.latin)
        let arabic = units(pair.arabic)
        latinOnly = latin.subtracting(arabic)
        arabicOnly = arabic.subtracting(latin)
    }

    public static func isArabicLetter(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x0621...0x0652, 0x066E...0x06D3, 0xFB50...0xFDFF, 0xFE70...0xFEFC: return true
        default: return false
        }
    }

    public static func isLatinLetter(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x41...0x5A, 0x61...0x7A: return true
        case 0xC0...0x24F: return unit != 0xD7 && unit != 0xF7
        default: return false
        }
    }

    public func count(_ units: ArraySlice<UInt16>) -> Counts {
        var counts = Counts()
        for unit in units {
            if Self.isArabicLetter(unit) {
                counts.strongArabic += 1
            } else if Self.isLatinLetter(unit) {
                counts.strongLatin += 1
            } else if arabicOnly.contains(unit) {
                counts.weakArabic += 1
            } else if latinOnly.contains(unit) {
                counts.weakLatin += 1
            }
        }
        return counts
    }
}
