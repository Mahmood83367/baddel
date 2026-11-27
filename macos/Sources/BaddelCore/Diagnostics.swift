/// A diagnostic record. By construction it can only carry codes and counts:
/// there is no field that could hold text read from or written to a field.
public struct DiagnosticEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case corrected
        case rejected
        case undone
        case undoRejected
    }

    public let kind: Kind
    public let mode: CorrectionEngine.Mode?
    public let rejection: Rejection?
    /// Length of the replaced text in UTF-16 units.
    public let utf16Length: Int?
    public let layoutSwitched: Bool?

    public init(
        kind: Kind, mode: CorrectionEngine.Mode? = nil, rejection: Rejection? = nil,
        utf16Length: Int? = nil, layoutSwitched: Bool? = nil
    ) {
        self.kind = kind
        self.mode = mode
        self.rejection = rejection
        self.utf16Length = utf16Length
        self.layoutSwitched = layoutSwitched
    }

    public var summary: String {
        var parts = ["event=\(kind.rawValue)"]
        if let mode { parts.append("mode=\(mode.rawValue)") }
        if let rejection { parts.append("reason=\(rejection.rawValue)") }
        if let utf16Length { parts.append("utf16Length=\(utf16Length)") }
        if let layoutSwitched { parts.append("layoutSwitched=\(layoutSwitched)") }
        return parts.joined(separator: " ")
    }
}
