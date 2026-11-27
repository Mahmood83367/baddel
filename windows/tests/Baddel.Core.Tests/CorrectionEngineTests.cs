using Baddel.Core;
using Xunit;

namespace Baddel.Core.Tests;

internal enum WriteBehavior
{
    Apply,
    Ignore,
    Corrupt,
    Fail,
}

internal sealed class FakeField(string text, int? caret = null, Utf16Range? selection = null) : IEditableField
{
    public string Text = text;
    public Utf16Range Selection = selection ?? new Utf16Range(caret ?? text.Length, 0);
    public bool Secure;
    public bool Editable = true;
    public bool FailsRead;
    public WriteBehavior Behavior = WriteBehavior.Apply;
    public int Writes;

    /// <summary>Simulates an edit after the engine has read the field but before the write.</summary>
    public Action<FakeField>? EditBeforeWrite;

    public bool IsSameField(IEditableField other) => ReferenceEquals(other, this);
    public bool IsSecure => Secure;
    public bool IsEditableText => Editable;
    public string ReadText() => FailsRead ? throw new RejectionException(Rejection.ReadFailed) : Text;
    public Utf16Range ReadSelection() => Selection;

    public void Replace(Utf16Range range, string snapshot, string replacement)
    {
        EditBeforeWrite?.Invoke(this);
        var expected = CorrectionEngine.ValidatedReplacement(range, snapshot, Text, replacement);
        Writes++;
        switch (Behavior)
        {
            case WriteBehavior.Apply: Text = expected; break;
            case WriteBehavior.Corrupt: Text = expected + "!"; break;
            case WriteBehavior.Fail: throw new RejectionException(Rejection.WriteFailed);
        }
    }

    public void SetSelection(Utf16Range range) => Selection = range;
}

internal sealed class FakeFocus : IFocusProvider
{
    public IEditableField? Field;
    public IEditableField? FocusedField() => Field;
}

internal sealed class FakeLayouts : ILayoutSwitcher
{
    public string Current = "en";
    public bool Selectable = true;
    public string? CurrentLayoutId() => Current;
    public Script? CurrentScript() => Current == "en" ? Script.Latin : Script.Arabic;

    public bool SelectLayout(Script script)
    {
        if (!Selectable) return false;
        Current = script == Script.Latin ? "en" : "ar";
        return true;
    }

    public bool SelectLayoutById(string id)
    {
        Current = id;
        return true;
    }
}

public class CorrectionEngineTests
{
    private readonly FakeFocus focus = new();
    private readonly FakeLayouts layouts = new();
    private readonly CorrectionEngine engine;

    public CorrectionEngineTests()
    {
        var store = new LayoutStore(Path.Combine(SharedFixtureTests.FindShared(), "layouts"));
        var pair = new LayoutPair(store.Get("us-english"), store.Get("arabic-pc"));
        engine = new CorrectionEngine(new CorrectionPlanner(pair), focus, layouts);
    }

    private CorrectionResult Run(FakeField field, CorrectionMode mode = CorrectionMode.SelectionOrLastWord)
    {
        focus.Field = field;
        return engine.Correct(mode, field);
    }

    [Fact]
    public void FixesLastWordAndKeepsCaretAfterTrailingSpace()
    {
        var field = new FakeField("hi ugd;l ");
        var result = Run(field);
        Assert.NotNull(result.Success);
        Assert.Equal("hi عليكم ", field.Text);
        Assert.Equal(new Utf16Range(9, 0), field.Selection);
        Assert.True(result.Success!.LayoutSwitched);
        Assert.Equal("ar", layouts.Current);
    }

    [Fact]
    public void FixesExactlyTheSelection()
    {
        var field = new FakeField("ugd;l ugd;l ugd;l", selection: new Utf16Range(6, 5));
        Assert.NotNull(Run(field).Success);
        Assert.Equal("ugd;l عليكم ugd;l", field.Text);
        Assert.Equal(new Utf16Range(6, 5), field.Selection);
    }

    [Fact]
    public void WholeFieldIsOneWrite()
    {
        var field = new FakeField("hgsghl ugd;l", caret: 3);
        Assert.NotNull(Run(field, CorrectionMode.WholeField).Success);
        Assert.Equal("السلام عليكم", field.Text);
        Assert.Equal(1, field.Writes);
    }

    [Fact]
    public void SecureFieldIsNeverReadOrWritten()
    {
        var field = new FakeField("ugd;l") { Secure = true, FailsRead = true };
        Assert.Equal(Rejection.SecureField, Run(field).Rejection);
        Assert.Equal(0, field.Writes);
    }

    [Fact]
    public void UnsupportedAndUnreadableFields()
    {
        var unsupported = new FakeField("ugd;l") { Editable = false };
        Assert.Equal(Rejection.UnsupportedField, Run(unsupported).Rejection);
        var unreadable = new FakeField("ugd;l") { FailsRead = true };
        Assert.Equal(Rejection.ReadFailed, Run(unreadable).Rejection);
        Assert.Equal(0, unsupported.Writes + unreadable.Writes);
    }

    [Fact]
    public void FocusChangeBetweenPressAndCorrection()
    {
        var captured = new FakeField("ugd;l");
        var other = new FakeField("ugd;l");
        focus.Field = other;
        Assert.Equal(Rejection.FocusChanged, engine.Correct(CorrectionMode.WholeField, captured).Rejection);
        focus.Field = null;
        Assert.Equal(Rejection.NoFocusedField, engine.Correct(CorrectionMode.WholeField, captured).Rejection);
        Assert.Equal("ugd;l", captured.Text);
        Assert.Equal("ugd;l", other.Text);
    }

    [Fact]
    public void FieldShortenedBetweenPlanAndWriteIsNotOverwritten()
    {
        foreach (var mode in new[] { CorrectionMode.SelectionOrLastWord, CorrectionMode.WholeField })
        {
            var field = new FakeField("hgsghl ugd;l") { EditBeforeWrite = f => f.Text = "hg" };
            Assert.Equal(Rejection.FieldChanged, Run(field, mode).Rejection);
            Assert.Equal("hg", field.Text);
            Assert.Equal(0, field.Writes);
            Assert.Equal("en", layouts.Current);
        }
    }

    [Fact]
    public void UnverifiedWriteDoesNotSwitchLayoutOrOfferUndo()
    {
        foreach (var behavior in new[] { WriteBehavior.Ignore, WriteBehavior.Corrupt })
        {
            var field = new FakeField("ugd;l") { Behavior = behavior };
            Assert.Equal(Rejection.VerificationFailed, Run(field).Rejection);
            Assert.Equal("en", layouts.Current);
        }
        var failing = new FakeField("ugd;l") { Behavior = WriteBehavior.Fail };
        Assert.Equal(Rejection.WriteFailed, Run(failing).Rejection);
        Assert.Equal("en", layouts.Current);
    }

    [Fact]
    public void UndoRestoresTextSelectionAndLayout()
    {
        var field = new FakeField("x ugd;l  ");
        var success = Run(field).Success!;
        Assert.Equal("x عليكم  ", field.Text);
        Assert.Null(engine.Undo(success.Undo));
        Assert.Equal("x ugd;l  ", field.Text);
        Assert.Equal(new Utf16Range(9, 0), field.Selection);
        Assert.Equal("en", layouts.Current);
    }

    [Fact]
    public void UndoRefusedAfterTextChangedOrFocusMoved()
    {
        var field = new FakeField("ugd;l");
        var success = Run(field).Success!;
        field.Text += "x";
        Assert.Equal(Rejection.UndoStateChanged, engine.Undo(success.Undo));
        Assert.Equal("عليكمx", field.Text);
        Assert.Equal("ar", layouts.Current);

        var second = new FakeField("ugd;l");
        layouts.Current = "en";
        var secondSuccess = Run(second).Success!;
        focus.Field = new FakeField("عليكم");
        Assert.Equal(Rejection.UndoStateChanged, engine.Undo(secondSuccess.Undo));
        Assert.Equal("عليكم", second.Text);
    }

    [Fact]
    public void UndoRefusedWhenFieldChangesJustBeforeTheUndoWrite()
    {
        var field = new FakeField("ugd;l");
        var success = Run(field).Success!;
        field.EditBeforeWrite = f => f.Text = "عل";
        Assert.Equal(Rejection.FieldChanged, engine.Undo(success.Undo));
        Assert.Equal("عل", field.Text);
    }

    [Fact]
    public void ValidatedReplacementRejectsStaleTextAndBadRanges()
    {
        const string text = "hgsghl ugd;l";
        Assert.Equal("hgsghl x", CorrectionEngine.ValidatedReplacement(new Utf16Range(7, 5), text, text, "x"));
        Assert.Equal(
            Rejection.FieldChanged,
            Assert.Throws<RejectionException>(
                () => CorrectionEngine.ValidatedReplacement(new Utf16Range(7, 5), text, "hgs", "x")).Rejection);
        foreach (var bad in new[] { new Utf16Range(7, 6), new Utf16Range(13, 0), new Utf16Range(-1, 2), new Utf16Range(2, -1) })
        {
            Assert.Equal(
                Rejection.InvalidRange,
                Assert.Throws<RejectionException>(
                    () => CorrectionEngine.ValidatedReplacement(bad, text, text, "x")).Rejection);
            Assert.Null(CorrectionEngine.Replacing(bad, text, "x"));
        }
        Assert.Null(CorrectionEngine.Replacing(new Utf16Range(1, 1), "😀a", "x"));
    }

    [Fact]
    public void DiagnosticsCarryNoText()
    {
        var diagnostic = new DiagnosticEvent(DiagnosticKind.Rejected, CorrectionMode.WholeField, Rejection.SecureField, 5);
        Assert.Equal("event=Rejected mode=WholeField reason=SecureField utf16Length=5", diagnostic.Summary);
        Assert.DoesNotContain(
            typeof(DiagnosticEvent).GetProperties(),
            property => property.PropertyType == typeof(string) && property.Name != nameof(DiagnosticEvent.Summary));
    }
}
