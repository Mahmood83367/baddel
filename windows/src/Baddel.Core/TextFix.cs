using System.Text;
using System.Text.RegularExpressions;

namespace Baddel.Core;

public enum TextFixMode
{
    /// <summary>The selection when there is one, otherwise the last word before the cursor.</summary>
    Word,
    /// <summary>The whole buffer.</summary>
    Line,
}

/// <summary>What the host counts cursor positions in.</summary>
public enum TextFixUnit
{
    Utf16,
    /// <summary>Unicode code points (zsh, Bash 5.0 and later).</summary>
    Scalars,
    /// <summary>UTF-8 bytes (Bash before 5.0).</summary>
    Bytes,
}

public sealed record TextFixRequest(string Text, TextFixMode Mode)
{
    public TextFixUnit Unit { get; init; } = TextFixUnit.Utf16;
    /// <summary><c>null</c> means the end of the text.</summary>
    public int? Cursor { get; init; }
    /// <summary>Start and length in <see cref="Unit"/>; used in word mode only.</summary>
    public Utf16Range? Selection { get; init; }
    public Script? Hint { get; init; }
    /// <summary>
    /// Keeps Claude Code's <c>[Image #1]</c> and <c>[Pasted text #1 +5 lines]</c> markers, and the
    /// previous-reply block it may put at the top of a draft file, as they are.
    /// </summary>
    public bool KeepsClaudePlaceholders { get; init; }
}

public sealed record TextFixOutput(string Text, int Cursor, Script SourceScript);

public readonly record struct TextFixResult(TextFixOutput? Output, Rejection? Rejection);

/// <summary>
/// Corrects text handed over by a host that owns its own editing buffer: a shell
/// line editor (zsh, Bash, PSReadLine) or the draft file Claude Code passes to an
/// external editor. The host sends the whole buffer and where the cursor is; it
/// gets the whole buffer back and puts it in place itself, so its own undo covers
/// the change. Nothing here reads a screen or sends keys.
/// The macOS implementation is <c>TextFix.swift</c>; both run
/// <c>shared/fixtures/text-fix.json</c>.
/// </summary>
public static partial class TextFix
{
    public static TextFixResult Run(TextFixRequest request, CorrectionPlanner planner)
    {
        var text = request.Text;
        if (text.Length > CorrectionEngine.MaxFieldLength) return new(null, Rejection.FieldTooLarge);
        if (text.Length == 0) return new(null, Rejection.EmptyField);

        int caret;
        if (request.Cursor is { } cursor)
        {
            if (Utf16Offset(cursor, request.Unit, text) is not { } offset) return new(null, Rejection.InvalidRange);
            caret = offset;
        }
        else
        {
            caret = text.Length;
        }

        CorrectionTarget target;
        var selected = false;
        if (request.Mode == TextFixMode.Line)
        {
            target = CorrectionTarget.ForWholeField();
        }
        else if (request.Selection is { Length: > 0 } selection)
        {
            if (Utf16Offset(selection.Location, request.Unit, text) is not { } start
                || Utf16Offset(selection.End, request.Unit, text) is not { } end)
            {
                return new(null, Rejection.InvalidRange);
            }
            target = CorrectionTarget.ForSelection(new Utf16Range(start, end - start));
            selected = true;
        }
        else
        {
            target = CorrectionTarget.ForLastWord(caret);
        }

        var kept = request.KeepsClaudePlaceholders ? ClaudePlaceholders(text) : null;
        var planned = planner.Plan(text, target, request.Hint, kept, hintDecidesMixedText: true);
        if (planned.Plan is not { } plan) return new(null, planned.Rejection ?? Rejection.NothingToConvert);

        var result = string.Concat(text.AsSpan(0, plan.Range.Location), plan.Replacement, text.AsSpan(plan.Range.End));
        int newCaret;
        if (request.Mode == TextFixMode.Line) newCaret = caret >= text.Length ? result.Length : Math.Min(caret, result.Length);
        else if (selected) newCaret = plan.Range.Location + plan.Replacement.Length;
        else newCaret = caret + plan.Replacement.Length - plan.Range.Length;
        // Never leave the cursor inside a surrogate pair.
        if (newCaret > 0 && newCaret < result.Length && char.IsHighSurrogate(result[newCaret - 1]) && char.IsLowSurrogate(result[newCaret]))
        {
            newCaret--;
        }
        return new(new TextFixOutput(result, Position(newCaret, request.Unit, result), plan.SourceScript), null);
    }

    [GeneratedRegex(@"\[(?:Image #[0-9]+|Pasted text #[0-9]+(?: \+[0-9]+ lines)?|\.\.\.Truncated text #[0-9]+ \+[0-9]+ lines\.\.\.)\]")]
    private static partial Regex PlaceholderPattern();

    /// <summary>
    /// The markers Claude Code shows in a draft for an attached image or a collapsed
    /// paste. They refer to content held by Claude Code, so they must survive a
    /// correction letter for letter.
    /// </summary>
    public static List<Utf16Range> ClaudePlaceholders(string text)
    {
        var ranges = PlaceholderPattern().Matches(text).Select(m => new Utf16Range(m.Index, m.Length)).ToList();
        if (ClaudeReferenceBlock(text) is { } reference) ranges.Insert(0, reference);
        return ranges;
    }

    /// <summary>
    /// The line Claude Code writes under its previous reply when "Show last response
    /// in external editor" is on. Everything up to and including this line is
    /// reference material that Claude Code removes again on save.
    /// </summary>
    public const string ClaudeReplySeparator = "# \u2500\u2500\u2500 Write your reply below this line \u2500\u2500\u2500";

    /// <summary>
    /// The previous-reply block at the top of a draft file, when there is one. It is
    /// not the user's text: it must not decide the direction and must come back
    /// unchanged, or Claude Code can no longer find and remove it.
    /// </summary>
    public static Utf16Range? ClaudeReferenceBlock(string text)
    {
        var separator = text.IndexOf(ClaudeReplySeparator, StringComparison.Ordinal);
        if (separator < 0) return null;
        var end = text.IndexOf('\n', separator);
        return new Utf16Range(0, end < 0 ? text.Length : end + 1);
    }

    /// <summary>
    /// The UTF-16 offset of position <paramref name="index"/> counted in
    /// <paramref name="unit"/>, or <c>null</c> when it lies outside the text or inside a character.
    /// </summary>
    public static int? Utf16Offset(int index, TextFixUnit unit, string text)
    {
        if (index < 0) return null;
        if (unit == TextFixUnit.Utf16) return index <= text.Length ? index : null;
        var remaining = index;
        var offset = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            if (remaining == 0) return offset;
            var width = unit == TextFixUnit.Scalars ? 1 : rune.Utf8SequenceLength;
            if (remaining < width) return null;
            remaining -= width;
            offset += rune.Utf16SequenceLength;
        }
        return remaining == 0 ? offset : null;
    }

    /// <summary>
    /// The inverse of <see cref="Utf16Offset"/>; an offset inside a surrogate pair
    /// counts as the position before the pair.
    /// </summary>
    public static int Position(int offset, TextFixUnit unit, string text)
    {
        if (unit == TextFixUnit.Utf16) return Math.Clamp(offset, 0, text.Length);
        var position = 0;
        var seen = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            if (seen + rune.Utf16SequenceLength > offset) break;
            seen += rune.Utf16SequenceLength;
            position += unit == TextFixUnit.Scalars ? 1 : rune.Utf8SequenceLength;
        }
        return position;
    }
}

/// <summary>
/// The command-line form of <see cref="TextFix"/>, shared by <c>Baddel.exe</c> and
/// the Linux <c>baddel</c>.
/// <code>
/// baddel --fix-text [--mode word|line] [--cursor N] [--selection START LENGTH]
///        [--unit utf16|scalars|bytes] [--hint latin|arabic|none]
///     reads the buffer from standard input (UTF-8) and writes
///     "ok CURSOR\n" followed by the corrected buffer, or "no CODE\n".
/// baddel --fix-draft [--any-file] [--hint …] FILE
///     corrects a Claude Code draft file in place; the file is rewritten only
///     when a correction was made.
/// </code>
/// Exit codes for --fix-text: 0 corrected, 1 left unchanged, 2 wrong usage. For
/// --fix-draft: 0 corrected or left unchanged, 1 not a Claude Code draft, 2 wrong
/// usage. Messages carry
/// stable codes and never the text.
/// </summary>
public static class TextFixCommand
{
    public const string DraftPrefix = "claude-prompt-";

    public static bool Handles(string[] args) => args.Contains("--fix-text") || args.Contains("--fix-draft");

    public static string Code(Rejection rejection)
    {
        var name = rejection.ToString();
        return char.ToLowerInvariant(name[0]) + name[1..];
    }

    public static int Run(
        string[] args, Func<LayoutPair?> pair, Func<Script?> activeScript, Stream input, Stream output, TextWriter error)
    {
        var draft = args.Contains("--fix-draft");
        var mode = draft ? TextFixMode.Line : TextFixMode.Word;
        var unit = TextFixUnit.Utf16;
        int? cursor = null;
        Utf16Range? selection = null;
        string? hintName = null, file = null;
        var anyFile = false;
        try
        {
            for (var i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--fix-text" or "--fix-draft": break;
                    case "--any-file": anyFile = true; break;
                    case "--mode": mode = args[++i] switch { "word" => TextFixMode.Word, "line" => TextFixMode.Line, _ => throw new FormatException() }; break;
                    case "--unit": unit = args[++i] switch { "utf16" => TextFixUnit.Utf16, "scalars" => TextFixUnit.Scalars, "bytes" => TextFixUnit.Bytes, _ => throw new FormatException() }; break;
                    case "--cursor": cursor = int.Parse(args[++i], System.Globalization.CultureInfo.InvariantCulture); break;
                    case "--selection":
                        selection = new Utf16Range(
                            int.Parse(args[++i], System.Globalization.CultureInfo.InvariantCulture),
                            int.Parse(args[++i], System.Globalization.CultureInfo.InvariantCulture));
                        break;
                    case "--hint": hintName = args[++i]; if (hintName is not ("latin" or "arabic" or "none")) throw new FormatException(); break;
                    default:
                        if (!draft || file is not null || args[i].StartsWith("--", StringComparison.Ordinal)) throw new FormatException();
                        file = args[i];
                        break;
                }
            }
            if (draft && file is null) throw new FormatException();
        }
        catch (Exception e) when (e is FormatException or IndexOutOfRangeException or OverflowException)
        {
            error.WriteLine("baddel: usage: --fix-text [--mode word|line] [--cursor N] [--selection START LENGTH] [--unit utf16|scalars|bytes] [--hint latin|arabic|none] | --fix-draft [--any-file] FILE");
            return 2;
        }

        var utf8 = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);
        int Refuse(string code)
        {
            if (draft) error.WriteLine($"baddel: draft left unchanged ({code})");
            else output.Write(utf8.GetBytes($"no {code}\n"));
            // Claude Code reports an editor that exits with an error as "quit
            // unexpectedly". Leaving a draft as it is is not an error.
            return draft ? 0 : 1;
        }

        // Another program's file (a commit message, say) is refused with an error
        // exit, so that program does not carry on as if it had been edited.
        if (draft && !anyFile && !Path.GetFileName(file!).StartsWith(DraftPrefix, StringComparison.Ordinal))
        {
            error.WriteLine("baddel: not a Claude Code draft; file left unchanged (notAClaudeDraft)");
            return 1;
        }

        string text;
        try
        {
            if (draft)
            {
                text = utf8.GetString(File.ReadAllBytes(file!));
            }
            else
            {
                using var buffer = new MemoryStream();
                input.CopyTo(buffer);
                text = utf8.GetString(buffer.ToArray());
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or DecoderFallbackException)
        {
            return Refuse(Code(Rejection.ReadFailed));
        }

        if (pair() is not { } layouts) return Refuse("noLayouts");
        Script? hint = hintName switch
        {
            "latin" => Script.Latin,
            "arabic" => Script.Arabic,
            "none" => null,
            _ => activeScript(),
        };
        var result = TextFix.Run(
            new TextFixRequest(text, mode) { Unit = unit, Cursor = cursor, Selection = selection, Hint = hint, KeepsClaudePlaceholders = draft },
            new CorrectionPlanner(layouts));
        if (result.Output is not { } fixedText) return Refuse(Code(result.Rejection ?? Rejection.NothingToConvert));

        if (draft)
        {
            try
            {
                File.WriteAllBytes(file!, utf8.GetBytes(fixedText.Text));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                return Refuse(Code(Rejection.WriteFailed));
            }
            error.WriteLine("baddel: draft corrected");
        }
        else
        {
            output.Write(utf8.GetBytes($"ok {fixedText.Cursor}\n{fixedText.Text}"));
        }
        return 0;
    }
}
