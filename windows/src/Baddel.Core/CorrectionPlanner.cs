using System.Text;

namespace Baddel.Core;

/// <summary>A range of UTF-16 code units (what .NET strings and UI Automation use).</summary>
public readonly record struct Utf16Range(int Location, int Length)
{
    public int End => Location + Length;
}

public enum TargetKind
{
    Selection,
    LastWord,
    WholeField,
}

public readonly record struct CorrectionTarget(TargetKind Kind, Utf16Range Selection = default, int Caret = 0)
{
    public static CorrectionTarget ForSelection(Utf16Range range) => new(TargetKind.Selection, Selection: range);
    public static CorrectionTarget ForLastWord(int caret) => new(TargetKind.LastWord, Caret: caret);
    public static CorrectionTarget ForWholeField() => new(TargetKind.WholeField);
}

/// <summary>Stable, text-free codes; the names match the Swift <c>Rejection</c> raw values.</summary>
public enum Rejection
{
    NoFocusedField,
    FocusChanged,
    FieldChanged,
    SecureField,
    UnsupportedField,
    ReadFailed,
    FieldTooLarge,
    EmptyField,
    NoWord,
    InvalidRange,
    AmbiguousDirection,
    NothingToConvert,
    WriteFailed,
    VerificationFailed,
    UndoStateChanged,
}

public sealed record CorrectionPlan(Utf16Range Range, string Original, string Replacement, Script SourceScript);

public readonly record struct PlanResult(CorrectionPlan? Plan, Rejection? Rejection)
{
    public static implicit operator PlanResult(CorrectionPlan plan) => new(plan, null);
    public static implicit operator PlanResult(Rejection rejection) => new(null, rejection);
}

/// <summary>Pure planning; mirrors <c>CorrectionPlanner.swift</c>.</summary>
public sealed class CorrectionPlanner
{
    private readonly ScriptEvidence evidence;
    private readonly LayoutConverter latinToArabic;
    private readonly LayoutConverter arabicToLatin;

    public CorrectionPlanner(LayoutPair pair)
    {
        evidence = new ScriptEvidence(pair);
        latinToArabic = new LayoutConverter(pair.Latin, pair.Arabic);
        arabicToLatin = new LayoutConverter(pair.Arabic, pair.Latin);
    }

    /// <param name="protectedRanges">
    /// Ranges of <paramref name="text"/> that must come back unchanged. A token that
    /// touches one is copied as it is and does not count as evidence for either script.
    /// </param>
    /// <param name="hintDecidesMixedText">
    /// When the text has letters of both scripts, take the direction from
    /// <paramref name="hint"/> instead of from whichever script has more letters. Used
    /// for command lines and drafts, where correct text in one script (a command, a
    /// pasted log) often outweighs the few words typed with the wrong layout.
    /// </param>
    public PlanResult Plan(
        string text, CorrectionTarget target, Script? hint, IReadOnlyList<Utf16Range>? protectedRanges = null,
        bool hintDecidesMixedText = false)
    {
        Utf16Range range;
        switch (target.Kind)
        {
            case TargetKind.WholeField:
                if (text.Length == 0) return Rejection.EmptyField;
                range = new Utf16Range(0, text.Length);
                break;
            case TargetKind.Selection:
                if (target.Selection.Length <= 0 || !IsValid(target.Selection, text)) return Rejection.InvalidRange;
                range = target.Selection;
                break;
            default:
                if (!IsValid(new Utf16Range(target.Caret, 0), text)) return Rejection.InvalidRange;
                var word = LastWord(target.Caret, text);
                if (word is null) return Rejection.NoWord;
                range = word.Value;
                break;
        }

        var segment = text.Substring(range.Location, range.Length);
        var tokens = Tokens(segment);
        if (tokens.Count == 0) return Rejection.NothingToConvert;

        var kept = tokens.Select(t => protectedRanges is not null && protectedRanges.Any(p =>
            p.Length > 0 && p.Location < range.Location + t.End && range.Location + t.Location < p.End)).ToList();
        var counts = tokens.Select((t, i) => kept[i] ? new EvidenceCounts() : evidence.Count(segment.AsSpan(t.Location, t.Length))).ToList();
        var total = counts.Aggregate(new EvidenceCounts(), (a, b) => a + b);
        var mixed = total.StrongLatin > 0 && total.StrongArabic > 0;
        var source = hintDecidesMixedText && mixed ? hint ?? total.DominantScript : total.DominantScript ?? hint;
        if (source is null) return Rejection.AmbiguousDirection;
        var converter = source == Script.Latin ? latinToArabic : arabicToLatin;

        var result = new StringBuilder(segment.Length);
        var cursor = 0;
        for (var i = 0; i < tokens.Count; i++)
        {
            var token = tokens[i];
            result.Append(segment, cursor, token.Location - cursor);
            var tokenText = segment.Substring(token.Location, token.Length);
            // Protected text and text already in the other script are left untouched.
            result.Append(kept[i] || counts[i].UniformScript == source.Value.Opposite() ? tokenText : converter.Convert(tokenText));
            cursor = token.End;
        }
        result.Append(segment, cursor, segment.Length - cursor);

        var replacement = result.ToString();
        if (replacement == segment) return Rejection.NothingToConvert;
        return new CorrectionPlan(range, segment, replacement, source.Value);
    }

    // Code points are written as integers: C# does not allow line-separator
    // characters, even as \u escapes, inside character literals.
    public static bool IsHorizontalSpace(char unit) =>
        (int)unit is 0x09 or 0x20 or 0xA0 or 0x1680 or (>= 0x2000 and <= 0x200A) or 0x202F or 0x205F or 0x3000;

    public static bool IsLineBreak(char unit) =>
        (int)unit is 0x0A or 0x0B or 0x0C or 0x0D or 0x85 or 0x2028 or 0x2029;

    public static bool IsWhitespace(char unit) => IsHorizontalSpace(unit) || IsLineBreak(unit);

    public static bool IsValid(Utf16Range range, string text)
    {
        if (range.Location < 0 || range.Length < 0 || range.End > text.Length) return false;
        bool SplitsPair(int offset) =>
            offset > 0 && offset < text.Length && char.IsHighSurrogate(text[offset - 1]) && char.IsLowSurrogate(text[offset]);
        return !SplitsPair(range.Location) && !SplitsPair(range.End);
    }

    public static Utf16Range? LastWord(int caret, string text)
    {
        var end = caret;
        while (end > 0 && IsHorizontalSpace(text[end - 1])) end--;
        var start = end;
        while (start > 0 && !IsWhitespace(text[start - 1])) start--;
        return end > start ? new Utf16Range(start, end - start) : null;
    }

    public static List<Utf16Range> Tokens(string segment)
    {
        var tokens = new List<Utf16Range>();
        var start = -1;
        for (var index = 0; index < segment.Length; index++)
        {
            if (IsWhitespace(segment[index]))
            {
                if (start >= 0)
                {
                    tokens.Add(new Utf16Range(start, index - start));
                    start = -1;
                }
            }
            else if (start < 0)
            {
                start = index;
            }
        }
        if (start >= 0) tokens.Add(new Utf16Range(start, segment.Length - start));
        return tokens;
    }
}
