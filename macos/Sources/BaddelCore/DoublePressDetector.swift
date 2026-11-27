/// Turns hot key presses into "single" or "double" decisions without touching
/// any text until the decision is made.
///
/// The caller feeds presses, releases and timer expiries:
/// - the first distinct press returns `.armed`; the caller remembers the
///   focused field and starts a timer for `windowMs`;
/// - a second distinct press (the key was released in between) within the
///   window returns `.double`;
/// - the timer expiring returns `.single`;
/// - auto-repeat and presses without an intervening release are ignored.
public struct DoublePressDetector: Sendable {
    public enum Action: String, Equatable, Sendable {
        case none
        /// First press registered; start the timer with `generation`.
        case armed
        case single
        case double
        /// A second press arrived after the window but before the timer was
        /// delivered: run the pending single correction, then treat this press
        /// as a new first press.
        case singleThenArmed
    }

    public let windowMs: Int
    /// Identifies the timer that belongs to the current pending press.
    public private(set) var generation = 0
    private var pendingSince: Int?
    private var released = true

    public init(windowMs: Int = 300) {
        self.windowMs = windowMs
    }

    public mutating func press(atMs time: Int, isRepeat: Bool) -> Action {
        // A press without a release in between is a held key.
        if isRepeat || !released { return .none }
        released = false
        if let first = pendingSince {
            if time - first <= windowMs {
                pendingSince = nil
                generation += 1
                return .double
            }
            pendingSince = time
            generation += 1
            return .singleThenArmed
        }
        pendingSince = time
        generation += 1
        return .armed
    }

    public mutating func release() {
        released = true
    }

    public mutating func timeout(generation timerGeneration: Int) -> Action {
        guard pendingSince != nil, timerGeneration == generation else { return .none }
        pendingSince = nil
        return .single
    }
}
