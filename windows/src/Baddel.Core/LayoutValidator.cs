using System.Text.Json;

namespace Baddel.Core;

public enum LayoutProblemCode
{
    InvalidId,
    MissingKey,
    UnknownKey,
    DuplicateKey,
    EmptyBase,
    OutputTooLong,
    InvalidCharacter,

    /// <summary>Warning: two keys produce the same text, so converting back picks the first.</summary>
    DuplicateOutput,
}

/// <summary>A problem found in a layout definition. It carries a code and a key name, never layout text.</summary>
public readonly record struct LayoutProblem(LayoutProblemCode Code, string? Key = null)
{
    public bool IsError => Code != LayoutProblemCode.DuplicateOutput;
}

public sealed record CustomLayoutReport(string File, string? LayoutId, IReadOnlyList<LayoutProblem> Errors, IReadOnlyList<LayoutProblem> Warnings)
{
    public bool Accepted => Errors.Count == 0;
}

/// <summary>
/// Checks a layout before it is used. Built-in layouts pass by construction; this
/// exists for layouts a user supplies. Mirrors <c>LayoutValidator.swift</c>.
/// </summary>
public static class LayoutValidator
{
    /// <summary>Ids of user-supplied layouts must start with this, so they can never shadow a built-in layout.</summary>
    public const string CustomPrefix = "custom-";

    public const int MaxOutputLength = 4;

    /// <summary>The 47 keys every layout must define, each exactly once.</summary>
    public static readonly IReadOnlyList<string> StandardKeyCodes = new[]
    {
        "Backquote", "Digit1", "Digit2", "Digit3", "Digit4", "Digit5", "Digit6", "Digit7", "Digit8", "Digit9",
        "Digit0", "Minus", "Equal",
        "KeyQ", "KeyW", "KeyE", "KeyR", "KeyT", "KeyY", "KeyU", "KeyI", "KeyO", "KeyP", "BracketLeft",
        "BracketRight", "Backslash",
        "KeyA", "KeyS", "KeyD", "KeyF", "KeyG", "KeyH", "KeyJ", "KeyK", "KeyL", "Semicolon", "Quote",
        "KeyZ", "KeyX", "KeyC", "KeyV", "KeyB", "KeyN", "KeyM", "Comma", "Period", "Slash",
    };

    public static bool IsValidId(string id) =>
        id.Length is >= 1 and <= 64 && id[0] != '-'
        && id.All(c => c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '-');

    public static List<LayoutProblem> Validate(KeyboardLayout layout)
    {
        var problems = new List<LayoutProblem>();
        if (!IsValidId(layout.Id)) problems.Add(new LayoutProblem(LayoutProblemCode.InvalidId));

        var known = StandardKeyCodes.ToHashSet(StringComparer.Ordinal);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var key in layout.Keys)
        {
            if (!known.Contains(key.Code)) problems.Add(new LayoutProblem(LayoutProblemCode.UnknownKey, key.Code));
            else if (!seen.Add(key.Code)) problems.Add(new LayoutProblem(LayoutProblemCode.DuplicateKey, key.Code));
        }
        foreach (var code in StandardKeyCodes)
        {
            if (!seen.Contains(code)) problems.Add(new LayoutProblem(LayoutProblemCode.MissingKey, code));
        }

        var baseOutputs = new HashSet<string>(StringComparer.Ordinal);
        var shiftOutputs = new HashSet<string>(StringComparer.Ordinal);
        foreach (var key in layout.Keys)
        {
            if (!known.Contains(key.Code)) continue;
            if (key.Base.Length == 0) problems.Add(new LayoutProblem(LayoutProblemCode.EmptyBase, key.Code));
            foreach (var output in new[] { key.Base, key.Shift })
            {
                if (output.Length > MaxOutputLength) problems.Add(new LayoutProblem(LayoutProblemCode.OutputTooLong, key.Code));
                if (!IsCleanText(output)) problems.Add(new LayoutProblem(LayoutProblemCode.InvalidCharacter, key.Code));
            }
            if (key.Base.Length > 0 && !baseOutputs.Add(key.Base)) problems.Add(new LayoutProblem(LayoutProblemCode.DuplicateOutput, key.Code));
            if (key.Shift.Length > 0 && !shiftOutputs.Add(key.Shift)) problems.Add(new LayoutProblem(LayoutProblemCode.DuplicateOutput, key.Code));
        }
        return problems;
    }

    /// <summary>No control characters, no whitespace, no unpaired surrogates.</summary>
    public static bool IsCleanText(string text)
    {
        for (var index = 0; index < text.Length; index++)
        {
            var unit = text[index];
            if (unit < 0x20 || unit == 0x7F || CorrectionPlanner.IsWhitespace(unit)) return false;
            if (char.IsHighSurrogate(unit))
            {
                if (index + 1 >= text.Length || !char.IsLowSurrogate(text[index + 1])) return false;
                index++;
            }
            else if (char.IsLowSurrogate(unit))
            {
                return false;
            }
        }
        return true;
    }

    /// <summary>
    /// Adds every valid layout found in <paramref name="directory"/> (<c>*.json</c>).
    /// Files that do not parse, fail validation, do not use the <c>custom-</c> id
    /// prefix, or repeat an existing id are skipped and reported; built-in layouts
    /// and defaults are never changed. A missing folder is not an error.
    /// </summary>
    public static (LayoutStore Store, List<CustomLayoutReport> Reports) AddCustomLayouts(LayoutStore store, string directory)
    {
        var all = new Dictionary<string, KeyboardLayout>(store.Layouts, StringComparer.Ordinal);
        var reports = new List<CustomLayoutReport>();
        string[] files;
        try
        {
            files = Directory.Exists(directory)
                ? Directory.GetFiles(directory, "*.json").OrderBy(f => Path.GetFileName(f), StringComparer.Ordinal).Take(32).ToArray()
                : Array.Empty<string>();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            files = Array.Empty<string>();
        }
        foreach (var file in files)
        {
            var name = Path.GetFileName(file);
            KeyboardLayout layout;
            try
            {
                if (new FileInfo(file).Length > 64 * 1024) throw new JsonException();
                layout = KeyboardLayout.Parse(File.ReadAllText(file));
            }
            catch (Exception)
            {
                reports.Add(new CustomLayoutReport(name, null, new[] { new LayoutProblem(LayoutProblemCode.InvalidCharacter) }, Array.Empty<LayoutProblem>()));
                continue;
            }
            var problems = Validate(layout);
            if (!layout.Id.StartsWith(CustomPrefix, StringComparison.Ordinal) || all.ContainsKey(layout.Id))
            {
                problems.Add(new LayoutProblem(LayoutProblemCode.InvalidId));
            }
            var errors = problems.Where(p => p.IsError).ToList();
            reports.Add(new CustomLayoutReport(name, layout.Id, errors, problems.Where(p => !p.IsError).ToList()));
            if (errors.Count == 0)
            {
                // A custom layout has no system layout behind it, so it never claims a platform identifier.
                all[layout.Id] = new KeyboardLayout
                {
                    Id = layout.Id,
                    Name = layout.Name,
                    Script = layout.Script,
                    PlatformIds = new Dictionary<string, IReadOnlyList<string>>(),
                    Keys = layout.Keys,
                };
            }
        }
        return (new LayoutStore(all.Values), reports);
    }
}
