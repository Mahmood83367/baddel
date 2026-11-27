import AppKit
import BaddelCore
import BaddelMacKit

/// Connects the hot key to the correction engine and the Undo panel.
final class CorrectionCoordinator {
    private let store: LayoutStore
    private let settings: Settings
    private let focus = AXFocusProvider()
    private let switcher: InputSourceSwitcher
    private let hud = HUDController()

    private var detector: DoublePressDetector
    private var capturedField: EditableField?
    private var timer: DispatchWorkItem?
    private var lastUndo: (engine: CorrectionEngine, record: CorrectionEngine.UndoRecord)?

    /// Called when the shortcut is pressed without Accessibility access.
    var onNeedsPermission: (() -> Void)?
    var onUndoAvailabilityChanged: ((Bool) -> Void)?

    init(store: LayoutStore, settings: Settings) {
        self.store = store
        self.settings = settings
        switcher = InputSourceSwitcher(store: store)
        detector = DoublePressDetector(windowMs: settings.doublePressMs)
        // The original text is kept only while Undo is on offer.
        hud.onHide = { [weak self] in self?.forgetUndo() }
    }

    func settingsChanged() {
        detector = DoublePressDetector(windowMs: settings.doublePressMs)
        timer?.cancel()
        capturedField = nil
    }

    // MARK: - Hot key

    func hotKeyPressed(isRepeat: Bool) {
        guard AccessibilityPermission.isGranted else {
            if !isRepeat { onNeedsPermission?() }
            return
        }
        let now = Int(ProcessInfo.processInfo.systemUptime * 1000)
        switch detector.press(atMs: now, isRepeat: isRepeat) {
        case .armed:
            arm()
        case .double:
            // Second distinct press inside the window: nothing has been
            // changed yet, so the whole field is fixed in one operation.
            timer?.cancel()
            run(.wholeField)
        case .singleThenArmed:
            timer?.cancel()
            run(.selectionOrLastWord)
            arm()
        case .single, .none:
            break
        }
    }

    func hotKeyReleased() {
        detector.release()
    }

    /// Remembers which field had focus at the first press and waits for a
    /// possible second press before touching any text.
    private func arm() {
        capturedField = focus.focusedField()
        let generation = detector.generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.detector.timeout(generation: generation) == .single else { return }
            self.run(.selectionOrLastWord)
        }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(detector.windowMs), execute: work)
    }

    // MARK: - Correction

    private func run(_ mode: CorrectionEngine.Mode) {
        let captured = capturedField
        capturedField = nil
        hud.hide(notify: false)
        forgetUndo()

        switcher.preferredArabicLayoutID = settings.arabicLayoutID
        focus.pasteFallback = settings.pasteFallbackEnabled ? PasteFallback() : nil
        guard let pair = switcher.resolvePair() else { return }
        let engine = CorrectionEngine(planner: CorrectionPlanner(pair: pair), focus: focus, layouts: switcher)
        engine.switchesLayout = settings.switchesLayout

        let field = captured as? AXField
        let bundleID = field.flatMap { NSRunningApplication(processIdentifier: $0.processID)?.bundleIdentifier }

        switch engine.correct(mode: mode, capturedField: captured) {
        case .success(let success):
            DiagnosticsLog.record(
                DiagnosticEvent(
                    kind: .corrected, mode: mode, utf16Length: success.undo.replacedRange.length,
                    layoutSwitched: success.layoutSwitched),
                bundleID: bundleID, role: field?.role)
            lastUndo = (engine, success.undo)
            onUndoAvailabilityChanged?(true)
            let edited = success.undo.field as? AXField
            let anchor = edited?.bounds(for: success.undo.replacedRange) ?? edited?.frame
            hud.show(
                message: mode == .wholeField ? "Field fixed" : "Fixed", anchor: anchor, duration: 6,
                undo: { [weak self] in self?.undoLast() })
        case .failure(let rejection):
            DiagnosticsLog.record(
                DiagnosticEvent(kind: .rejected, mode: mode, rejection: rejection),
                bundleID: bundleID, role: field?.role)
            hud.show(message: Self.message(for: rejection), anchor: field?.frame, duration: 2.2)
        }
    }

    func undoLast() {
        guard let (engine, record) = lastUndo else { return }
        forgetUndo()
        hud.hide(notify: false)
        let anchor = (record.field as? AXField)?.frame
        switch engine.undo(record) {
        case .success:
            DiagnosticsLog.record(DiagnosticEvent(kind: .undone, utf16Length: record.replacedRange.length))
            hud.show(message: "Restored", anchor: anchor, duration: 1.5)
        case .failure(let rejection):
            DiagnosticsLog.record(DiagnosticEvent(kind: .undoRejected, rejection: rejection))
            hud.show(message: "Can't undo: the text has changed", anchor: anchor, duration: 2.5)
        }
    }

    private func forgetUndo() {
        guard lastUndo != nil else { return }
        lastUndo = nil
        onUndoAvailabilityChanged?(false)
    }

    private static func message(for rejection: Rejection) -> String {
        switch rejection {
        case .secureField: return "Secure field — skipped"
        case .noFocusedField, .unsupportedField, .readFailed: return "This field isn't supported"
        case .focusChanged: return "Focus changed — nothing was modified"
        case .fieldChanged: return "The text changed — nothing was modified"
        case .fieldTooLarge: return "Field too large — skipped"
        case .emptyField, .noWord, .nothingToConvert: return "Nothing to fix"
        case .ambiguousDirection: return "Can't tell which layout was meant"
        case .invalidRange: return "Couldn't locate the text"
        case .writeFailed: return "This app didn't accept the change"
        case .verificationFailed: return "Couldn't verify the change"
        case .undoStateChanged: return "Can't undo: the text has changed"
        }
    }
}
