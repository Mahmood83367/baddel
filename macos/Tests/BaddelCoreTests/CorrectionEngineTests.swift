import XCTest
@testable import BaddelCore

final class FakeField: EditableField {
    var text: String
    var selection: UTF16Range
    var isSecure = false
    var isEditableText = true
    var failsRead = false
    /// What a write does: apply it, silently drop it, or apply something else.
    enum WriteBehavior { case apply, ignore, corrupt, fail }
    var writeBehavior = WriteBehavior.apply
    var writes = 0

    init(_ text: String, caret: Int? = nil, selection: UTF16Range? = nil) {
        self.text = text
        self.selection = selection ?? UTF16Range(location: caret ?? text.utf16.count, length: 0)
    }

    func isSameField(as other: EditableField) -> Bool { other === self }
    func readText() throws -> String {
        if failsRead { throw Rejection.readFailed }
        return text
    }
    func readSelection() throws -> UTF16Range { selection }
    /// Simulates the app or the user editing the field after the engine has
    /// read it but before the write.
    var editBeforeWrite: ((FakeField) -> Void)?

    func replace(range: UTF16Range, in snapshot: String, with new: String) throws {
        editBeforeWrite?(self)
        // Same pre-write check the real Accessibility field runs.
        let expected = try CorrectionEngine.validatedReplacement(of: range, in: snapshot, current: text, with: new)
        writes += 1
        switch writeBehavior {
        case .apply: text = expected
        case .ignore: break
        case .corrupt: text = expected + "!"
        case .fail: throw Rejection.writeFailed
        }
    }
    func setSelection(_ range: UTF16Range) { selection = range }
}

final class FakeFocus: FocusProviding {
    var field: EditableField?
    func focusedField() -> EditableField? { field }
}

final class FakeLayouts: LayoutSwitching {
    var current = "en"
    var selectable = true
    func currentInputSourceID() -> String? { current }
    func currentScript() -> Script? { current == "en" ? .latin : .arabic }
    func selectLayout(for script: Script) -> Bool {
        guard selectable else { return false }
        current = script == .latin ? "en" : "ar"
        return true
    }
    func selectInputSource(id: String) -> Bool { current = id; return true }
}

final class CorrectionEngineTests: XCTestCase {
    let focus = FakeFocus()
    let layouts = FakeLayouts()
    lazy var engine = CorrectionEngine(
        planner: CorrectionPlanner(pair: Shared.pair()), focus: focus, layouts: layouts)

    private func run(_ field: FakeField, _ mode: CorrectionEngine.Mode = .selectionOrLastWord)
        -> Result<CorrectionEngine.Success, Rejection> {
        focus.field = field
        return engine.correct(mode: mode, capturedField: field)
    }

    private func rejection<T>(_ result: Result<T, Rejection>) -> Rejection? {
        if case .failure(let r) = result { return r }
        return nil
    }

    func testFixesLastWordAndKeepsCaretAfterTrailingSpace() throws {
        let field = FakeField("hi ugd;l ")
        let success = try run(field).get()
        XCTAssertEqual(field.text, "hi عليكم ")
        XCTAssertEqual(field.selection, UTF16Range(location: 9, length: 0))
        XCTAssertEqual(success.target, .lastWord(caret: 9))
        XCTAssertTrue(success.layoutSwitched)
        XCTAssertEqual(layouts.current, "ar")
    }

    func testFixesExactlyTheSelection() throws {
        let field = FakeField("ugd;l ugd;l ugd;l", selection: UTF16Range(location: 6, length: 5))
        _ = try run(field).get()
        XCTAssertEqual(field.text, "ugd;l عليكم ugd;l")
        XCTAssertEqual(field.selection, UTF16Range(location: 6, length: 5))
    }

    func testWholeFieldIsOneWrite() throws {
        let field = FakeField("hgsghl ugd;l", caret: 3)
        _ = try run(field, .wholeField).get()
        XCTAssertEqual(field.text, "السلام عليكم")
        XCTAssertEqual(field.writes, 1)
    }

    func testArabicToEnglishSwitchesToLatin() throws {
        layouts.current = "ar"
        let field = FakeField("اثممخ")
        _ = try run(field).get()
        XCTAssertEqual(field.text, "hello")
        XCTAssertEqual(layouts.current, "en")
    }

    func testSecureFieldIsNeverReadOrWritten() {
        let field = FakeField("ugd;l")
        field.isSecure = true
        field.failsRead = true
        XCTAssertEqual(rejection(run(field)), .secureField)
        XCTAssertEqual(field.writes, 0)
    }

    func testUnsupportedAndUnreadableFields() {
        let unsupported = FakeField("ugd;l")
        unsupported.isEditableText = false
        XCTAssertEqual(rejection(run(unsupported)), .unsupportedField)
        let unreadable = FakeField("ugd;l")
        unreadable.failsRead = true
        XCTAssertEqual(rejection(run(unreadable)), .readFailed)
        XCTAssertEqual(unsupported.writes + unreadable.writes, 0)
    }

    func testFocusChangeBetweenPressAndCorrection() {
        let captured = FakeField("ugd;l")
        let other = FakeField("ugd;l")
        focus.field = other
        XCTAssertEqual(rejection(engine.correct(mode: .wholeField, capturedField: captured)), .focusChanged)
        focus.field = nil
        XCTAssertEqual(rejection(engine.correct(mode: .wholeField, capturedField: captured)), .noFocusedField)
        XCTAssertEqual(captured.text, "ugd;l")
        XCTAssertEqual(other.text, "ugd;l")
    }

    func testTooLargeFieldIsSkipped() {
        let field = FakeField(String(repeating: "a", count: CorrectionEngine.maxFieldLength + 1))
        XCTAssertEqual(rejection(run(field)), .fieldTooLarge)
    }

    func testUnverifiedWriteDoesNotSwitchLayoutOrOfferUndo() {
        for behavior in [FakeField.WriteBehavior.ignore, .corrupt] {
            let field = FakeField("ugd;l")
            field.writeBehavior = behavior
            XCTAssertEqual(rejection(run(field)), .verificationFailed)
            XCTAssertEqual(layouts.current, "en")
        }
        let failing = FakeField("ugd;l")
        failing.writeBehavior = .fail
        XCTAssertEqual(rejection(run(failing)), .writeFailed)
        XCTAssertEqual(layouts.current, "en")
    }

    func testFieldShortenedBetweenPlanAndWriteIsNotOverwritten() {
        for mode in [CorrectionEngine.Mode.selectionOrLastWord, .wholeField] {
            let field = FakeField("hgsghl ugd;l")
            field.editBeforeWrite = { $0.text = "hg" }
            XCTAssertEqual(rejection(run(field, mode)), .fieldChanged)
            XCTAssertEqual(field.text, "hg")
            XCTAssertEqual(field.writes, 0)
            XCTAssertEqual(layouts.current, "en")
        }
    }

    func testFieldEditedBetweenPlanAndWriteKeepsNewerText() {
        let field = FakeField("hgsghl ugd;l")
        field.editBeforeWrite = { $0.text = "hgsghl ugd;l and more" }
        XCTAssertEqual(rejection(run(field, .wholeField)), .fieldChanged)
        XCTAssertEqual(field.text, "hgsghl ugd;l and more")
        XCTAssertEqual(field.writes, 0)
    }

    func testUndoRefusedWhenFieldChangesJustBeforeTheUndoWrite() throws {
        let field = FakeField("ugd;l")
        let success = try run(field).get()
        field.editBeforeWrite = { $0.text = "عل" }
        XCTAssertEqual(rejection(engine.undo(success.undo)), .fieldChanged)
        XCTAssertEqual(field.text, "عل")
        XCTAssertEqual(layouts.current, "ar")
    }

    func testValidatedReplacementRejectsStaleTextAndBadRanges() {
        let range = UTF16Range(location: 7, length: 5)
        XCTAssertEqual(
            try CorrectionEngine.validatedReplacement(of: range, in: "hgsghl ugd;l", current: "hgsghl ugd;l", with: "x"),
            "hgsghl x")
        XCTAssertThrowsError(
            try CorrectionEngine.validatedReplacement(of: range, in: "hgsghl ugd;l", current: "hgs", with: "x")
        ) { XCTAssertEqual($0 as? Rejection, .fieldChanged) }
        // Same length, different content: still stale.
        XCTAssertThrowsError(
            try CorrectionEngine.validatedReplacement(of: range, in: "hgsghl ugd;l", current: "hgsghl ugd;X", with: "x")
        ) { XCTAssertEqual($0 as? Rejection, .fieldChanged) }
        for bad in [UTF16Range(location: 7, length: 6), UTF16Range(location: 13, length: 0),
                    UTF16Range(location: -1, length: 2), UTF16Range(location: 2, length: -1)] {
            XCTAssertThrowsError(
                try CorrectionEngine.validatedReplacement(of: bad, in: "hgsghl ugd;l", current: "hgsghl ugd;l", with: "x")
            ) { XCTAssertEqual($0 as? Rejection, .invalidRange) }
            XCTAssertNil(CorrectionEngine.replacing(bad, in: "hgsghl ugd;l", with: "x"))
        }
        // A range that would split a surrogate pair is refused, not applied.
        XCTAssertNil(CorrectionEngine.replacing(UTF16Range(location: 1, length: 1), in: "😀a", with: "x"))
    }

    func testLayoutSwitchFailureIsReported() throws {
        layouts.selectable = false
        let success = try run(FakeField("ugd;l")).get()
        XCTAssertFalse(success.layoutSwitched)
    }

    func testSwitchingCanBeDisabled() throws {
        engine.switchesLayout = false
        let success = try run(FakeField("ugd;l")).get()
        XCTAssertFalse(success.layoutSwitched)
        XCTAssertEqual(layouts.current, "en")
    }

    func testUndoRestoresTextSelectionAndLayout() throws {
        let field = FakeField("x ugd;l  ")
        let success = try run(field).get()
        XCTAssertEqual(field.text, "x عليكم  ")
        try engine.undo(success.undo).get()
        XCTAssertEqual(field.text, "x ugd;l  ")
        XCTAssertEqual(field.selection, UTF16Range(location: 9, length: 0))
        XCTAssertEqual(layouts.current, "en")
    }

    func testUndoRefusedAfterTextChanged() throws {
        let field = FakeField("ugd;l")
        let success = try run(field).get()
        field.text += "x"
        XCTAssertEqual(rejection(engine.undo(success.undo)), .undoStateChanged)
        XCTAssertEqual(field.text, "عليكمx")
        XCTAssertEqual(layouts.current, "ar")
    }

    func testUndoRefusedWhenAnotherFieldHasFocus() throws {
        let field = FakeField("ugd;l")
        let success = try run(field).get()
        focus.field = FakeField("عليكم")
        XCTAssertEqual(rejection(engine.undo(success.undo)), .undoStateChanged)
        XCTAssertEqual(field.text, "عليكم")
    }

    func testUndoDoesNotTouchLayoutWhenItWasNotSwitched() throws {
        layouts.current = "ar"
        let field = FakeField("ugd;l")
        let success = try run(field).get()
        XCTAssertFalse(success.layoutSwitched)
        layouts.current = "en"
        try engine.undo(success.undo).get()
        XCTAssertEqual(layouts.current, "en")
    }

    func testDiagnosticsCarryNoText() {
        let event = DiagnosticEvent(kind: .rejected, mode: .wholeField, rejection: .secureField, utf16Length: 5)
        XCTAssertEqual(event.summary, "event=rejected mode=wholeField reason=secureField utf16Length=5")
        // Every stored property is a code, a count or a flag.
        for child in Mirror(reflecting: event).children {
            XCTAssertFalse(child.value is String, "\(child.label ?? "?") must not be free text")
        }
    }
}
