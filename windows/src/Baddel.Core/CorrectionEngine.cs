namespace Baddel.Core;

/// <summary>Thrown by field implementations to refuse an operation with a text-free code.</summary>
public sealed class RejectionException(Rejection rejection) : Exception(rejection.ToString())
{
    public Rejection Rejection { get; } = rejection;
}

/// <summary>A focused text field, abstracted from the platform accessibility API.</summary>
public interface IEditableField
{
    bool IsSameField(IEditableField other);

    /// <summary>Password and other protected fields; never read or modified.</summary>
    bool IsSecure { get; }

    /// <summary>Whether the element is a text field Baddel knows how to edit.</summary>
    bool IsEditableText { get; }

    string ReadText();

    /// <summary>The selection as a UTF-16 range; a zero length is the caret.</summary>
    Utf16Range ReadSelection();

    /// <summary>
    /// Replaces <paramref name="range"/> with <paramref name="replacement"/>.
    /// <paramref name="snapshot"/> is the full text the range was planned against; an
    /// implementation must re-read the field and call
    /// <see cref="CorrectionEngine.ValidatedReplacement"/> before mutating anything.
    /// </summary>
    void Replace(Utf16Range range, string snapshot, string replacement);

    /// <summary>Best effort; failures are ignored.</summary>
    void SetSelection(Utf16Range range);
}

public interface IFocusProvider
{
    IEditableField? FocusedField();
}

public interface ILayoutSwitcher
{
    /// <summary>Opaque platform identifier of the active keyboard layout.</summary>
    string? CurrentLayoutId();

    Script? CurrentScript();

    bool SelectLayout(Script script);

    bool SelectLayoutById(string id);
}

public enum CorrectionMode
{
    SelectionOrLastWord,
    WholeField,
}

public sealed record UndoRecord(
    IEditableField Field,
    Utf16Range ReplacedRange,
    string Original,
    string Replacement,
    string TextBefore,
    string TextAfter,
    Utf16Range SelectionBefore,
    string? PriorLayoutId,
    bool LayoutSwitched);

public sealed record CorrectionSuccess(
    CorrectionMode Mode,
    CorrectionTarget Target,
    Script SourceScript,
    bool LayoutSwitched,
    UndoRecord Undo);

public readonly record struct CorrectionResult(CorrectionSuccess? Success, Rejection? Rejection)
{
    public static implicit operator CorrectionResult(CorrectionSuccess success) => new(success, null);
    public static implicit operator CorrectionResult(Rejection rejection) => new(null, rejection);
}

/// <summary>
/// Runs a correction against a field: checks, plan, write, verification, layout
/// switch, and the guarded undo. Mirrors <c>CorrectionEngine.swift</c>.
/// </summary>
public sealed class CorrectionEngine(CorrectionPlanner planner, IFocusProvider focus, ILayoutSwitcher layouts)
{
    /// <summary>Fields longer than this (UTF-16 units) are skipped.</summary>
    public const int MaxFieldLength = 200_000;

    public bool SwitchesLayout { get; set; } = true;

    /// <param name="mode">What to correct.</param>
    /// <param name="capturedField">
    /// The field that had focus when the shortcut was first pressed. The correction
    /// only runs if it still has focus.
    /// </param>
    public CorrectionResult Correct(CorrectionMode mode, IEditableField? capturedField)
    {
        var field = focus.FocusedField();
        if (capturedField is null || field is null) return Rejection.NoFocusedField;
        if (!field.IsSameField(capturedField)) return Rejection.FocusChanged;
        if (field.IsSecure) return Rejection.SecureField;
        if (!field.IsEditableText) return Rejection.UnsupportedField;

        string text;
        Utf16Range selection;
        try
        {
            text = field.ReadText();
            selection = field.ReadSelection();
        }
        catch (Exception)
        {
            return Rejection.ReadFailed;
        }
        if (text.Length > MaxFieldLength) return Rejection.FieldTooLarge;

        var target = mode == CorrectionMode.WholeField
            ? CorrectionTarget.ForWholeField()
            : selection.Length > 0
                ? CorrectionTarget.ForSelection(selection)
                : CorrectionTarget.ForLastWord(selection.Location);

        var planned = planner.Plan(text, target, layouts.CurrentScript());
        if (planned.Plan is not { } plan) return planned.Rejection!.Value;

        var expected = Replacing(plan.Range, text, plan.Replacement);
        if (expected is null) return Rejection.InvalidRange;
        try
        {
            field.Replace(plan.Range, text, plan.Replacement);
        }
        catch (RejectionException exception)
        {
            return exception.Rejection;
        }
        catch (Exception)
        {
            return Rejection.WriteFailed;
        }

        if (!TryRead(field, out var written) || written != expected) return Rejection.VerificationFailed;

        var newLength = plan.Replacement.Length;
        var replacedRange = new Utf16Range(plan.Range.Location, newLength);
        switch (target.Kind)
        {
            case TargetKind.Selection:
                field.SetSelection(replacedRange);
                break;
            case TargetKind.LastWord:
                field.SetSelection(new Utf16Range(target.Caret + newLength - plan.Range.Length, 0));
                break;
            default:
                field.SetSelection(new Utf16Range(newLength, 0));
                break;
        }

        // Only switch the layout once the write has been verified.
        var prior = layouts.CurrentLayoutId();
        var targetScript = plan.SourceScript.Opposite();
        var switched = false;
        if (SwitchesLayout && layouts.CurrentScript() != targetScript)
        {
            switched = layouts.SelectLayout(targetScript);
        }

        var undo = new UndoRecord(
            field, replacedRange, plan.Original, plan.Replacement, text, expected, selection, prior, switched);
        return new CorrectionSuccess(mode, target, plan.SourceScript, switched, undo);
    }

    /// <summary>
    /// Restores the original text and layout, but only if the same field is still
    /// focused and still holds exactly the post-edit text.
    /// </summary>
    /// <returns><c>null</c> on success, otherwise the reason it was refused.</returns>
    public Rejection? Undo(UndoRecord record)
    {
        var field = focus.FocusedField();
        if (field is null || !field.IsSameField(record.Field) || field.IsSecure) return Rejection.UndoStateChanged;
        if (!TryRead(field, out var current) || current != record.TextAfter) return Rejection.UndoStateChanged;
        try
        {
            field.Replace(record.ReplacedRange, record.TextAfter, record.Original);
        }
        catch (RejectionException exception)
        {
            return exception.Rejection;
        }
        catch (Exception)
        {
            return Rejection.WriteFailed;
        }
        if (!TryRead(field, out var restored) || restored != record.TextBefore) return Rejection.VerificationFailed;
        field.SetSelection(record.SelectionBefore);
        if (record.LayoutSwitched && record.PriorLayoutId is not null)
        {
            layouts.SelectLayoutById(record.PriorLayoutId);
        }
        return null;
    }

    private static bool TryRead(IEditableField field, out string text)
    {
        try
        {
            text = field.ReadText();
            return true;
        }
        catch (Exception)
        {
            text = string.Empty;
            return false;
        }
    }

    /// <summary>
    /// <paramref name="text"/> with <paramref name="range"/> replaced, or <c>null</c> if
    /// the range is out of bounds or would split a surrogate pair.
    /// </summary>
    public static string? Replacing(Utf16Range range, string text, string replacement)
    {
        if (!CorrectionPlanner.IsValid(range, text)) return null;
        return string.Concat(text.AsSpan(0, range.Location), replacement, text.AsSpan(range.End));
    }

    /// <summary>The check every field implementation runs immediately before writing.</summary>
    /// <exception cref="RejectionException">
    /// <see cref="Rejection.FieldChanged"/> if the field no longer holds the snapshot,
    /// <see cref="Rejection.InvalidRange"/> if the range does not fit it.
    /// </exception>
    public static string ValidatedReplacement(Utf16Range range, string snapshot, string current, string replacement)
    {
        if (current != snapshot) throw new RejectionException(Rejection.FieldChanged);
        return Replacing(range, snapshot, replacement) ?? throw new RejectionException(Rejection.InvalidRange);
    }
}

/// <summary>
/// A diagnostic record. It can only carry codes, counts and flags: there is no
/// member that could hold text read from or written to a field.
/// </summary>
public sealed record DiagnosticEvent(
    DiagnosticKind Kind,
    CorrectionMode? Mode = null,
    Rejection? Rejection = null,
    int? Utf16Length = null,
    bool? LayoutSwitched = null)
{
    public string Summary
    {
        get
        {
            var parts = new List<string> { $"event={Kind}" };
            if (Mode is not null) parts.Add($"mode={Mode}");
            if (Rejection is not null) parts.Add($"reason={Rejection}");
            if (Utf16Length is not null) parts.Add($"utf16Length={Utf16Length}");
            if (LayoutSwitched is not null) parts.Add($"layoutSwitched={LayoutSwitched}");
            return string.Join(' ', parts);
        }
    }
}

public enum DiagnosticKind
{
    Corrected,
    Rejected,
    Undone,
    UndoRejected,
}
