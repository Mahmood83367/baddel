using System.Text;

namespace Baddel.Core;

public enum TerminalPlatform { Macos, Windows, Linux }

/// <param name="Alt">Option on macOS, Alt elsewhere.</param>
/// <param name="Command">Command on macOS, the Windows or Super key elsewhere.</param>
/// <param name="Key"><c>space</c>, or one lower-case ASCII character such as <c>t</c> or <c>]</c>.</param>
public readonly record struct KeyCombination(bool Control, bool Alt, bool Shift, bool Command, string Key);

/// <summary>
/// Works out how Baddel's one shortcut reaches a program inside a terminal.
/// A terminal does not pass key combinations on as such: it sends bytes. A
/// combination with Control arrives as one control character, one with Alt as
/// Escape followed by the key, and one with the Windows key does not arrive at
/// all. From the combination chosen in Baddel's settings this type derives what
/// a shell has to bind, what PSReadLine and Claude Code call the same key, or the
/// reason it cannot be delivered.
/// The macOS implementation is <c>TerminalKey.swift</c>; both run
/// <c>shared/fixtures/terminal-keys.json</c>.
/// </summary>
public sealed record TerminalKey(
    IReadOnlyList<byte[]> Sequences, string? Reason, bool NeedsOptionAsMeta, string? PsReadLineChord,
    IReadOnlyList<string> ClaudeKeystrokes)
{
    public bool IsDeliverable => Sequences.Count > 0;

    /// <summary>
    /// Control characters a terminal or line editor already gives a fixed meaning:
    /// interrupt, end of input, backspace, tab, newline, return, flow control, suspend.
    /// </summary>
    private const string ReservedControlLetters = "cdhijmqsz";

    private static TerminalKey Refuse(string reason) => new(Array.Empty<byte[]>(), reason, false, null, Array.Empty<string>());

    public static TerminalKey Resolve(KeyCombination combination, TerminalPlatform platform)
    {
        if (combination.Command) return Refuse("usesCommandKey");
        if (!combination.Control && !combination.Alt) return Refuse("needsControlOrAlt");
        var isSpace = combination.Key == "space";
        if (!isSpace && (combination.Key.Length != 1 || combination.Key[0] <= 0x20 || combination.Key[0] >= 0x7F))
        {
            return Refuse("keyHasNoTerminalSequence");
        }
        var character = isSpace ? ' ' : combination.Key[0];
        var isLetter = character is >= 'a' and <= 'z' or >= 'A' and <= 'Z';
        var isDigit = character is >= '0' and <= '9';

        var sequences = new List<byte[]>();
        if (combination.Control)
        {
            byte controlByte;
            if (isSpace) controlByte = 0x00;
            else if (isLetter)
            {
                if (ReservedControlLetters.Contains(char.ToLowerInvariant(character))) return Refuse("reservedInTerminals");
                controlByte = (byte)(character & 0x1F);
            }
            else if (character is ']' or '^' or '_') controlByte = (byte)(character & 0x1F);
            else if (character is '[' or '\\') return Refuse("reservedInTerminals");
            else return Refuse("keyHasNoTerminalSequence");
            sequences.Add(combination.Alt ? new byte[] { 0x1B, controlByte } : new[] { controlByte });
        }
        else
        {
            // Alt or Option alone: Escape, then the key as typed.
            if (!isSpace && !isLetter && !isDigit && combination.Shift) return Refuse("keyHasNoTerminalSequence");
            var typed = combination.Shift && isLetter ? char.ToUpperInvariant(character) : character;
            sequences.Add(new byte[] { 0x1B, (byte)typed });
            // macOS Terminal with its default settings types what Option makes of the
            // key. For Space that is a non-breaking space on the Latin and Arabic
            // layouts alike, so a shell can bind it; for other keys it is an ordinary
            // character that must stay typeable.
            if (platform == TerminalPlatform.Macos && isSpace) sequences.Insert(0, new byte[] { 0xC2, 0xA0 });
        }

        var modifiers = new List<string>();
        if (combination.Control) modifiers.Add("ctrl");
        if (combination.Alt) modifiers.Add("alt");
        var name = isSpace ? "space" : combination.Key;
        var claude = new List<string> { string.Join("+", modifiers.Concat(combination.Shift ? new[] { "shift" } : Array.Empty<string>()).Append(name)) };
        // Without a protocol that reports modifiers, a terminal cannot tell Shift
        // apart for these keys, so Claude Code sees the plain keystroke.
        if (combination.Shift) claude.Add(string.Join("+", modifiers.Append(name)));

        var chord = new List<string>();
        if (combination.Control) chord.Add("Ctrl");
        if (combination.Alt) chord.Add("Alt");
        if (combination.Shift) chord.Add("Shift");
        chord.Add(isSpace ? "Spacebar" : combination.Key);

        // PSReadLine reads Ctrl+Alt as AltGr and binds Ctrl+Alt+Space as plain Space
        // (seen in 2.0.0 and 2.4.5), which would correct text at every space. That
        // one chord is never offered to it.
        var altGrSpace = combination.Control && combination.Alt && isSpace;
        return new TerminalKey(
            sequences, null, platform == TerminalPlatform.Macos && combination.Alt, altGrSpace ? null : string.Join("+", chord), claude);
    }

    /// <summary>The sequences in the notation <c>bindkey</c> (zsh) or <c>bind</c> (Bash) reads.</summary>
    public IReadOnlyList<string> Notation(bool zsh) => Sequences.Select(bytes =>
    {
        var text = new StringBuilder();
        foreach (var value in bytes)
        {
            text.Append(value switch
            {
                0x1B => "\\e",
                0x00 => zsh ? "^@" : "\\C-@",
                >= 0x01 and <= 0x1A => zsh ? "^" + (char)(value + 0x40) : "\\C-" + (char)(value + 0x60),
                >= 0x1C and <= 0x1F => (zsh ? "^" : "\\C-") + (char)(value + 0x40),
                (>= 0x30 and <= 0x39) or (>= 0x41 and <= 0x5A) or (>= 0x61 and <= 0x7A) => ((char)value).ToString(),
                _ => "\\x" + value.ToString("x2"),
            });
        }
        return text.ToString();
    }).ToList();

    /// <summary>
    /// Parses a shortcut written as <c>Ctrl+Alt+Space</c> (Windows and Linux settings).
    /// Key names follow the settings files: <c>Space</c>, a letter, a digit
    /// (<c>D1</c> on Windows), or a punctuation name.
    /// </summary>
    public static KeyCombination? Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        bool control = false, alt = false, shift = false, command = false;
        string? key = null;
        foreach (var raw in text.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            switch (raw.ToLowerInvariant())
            {
                case "ctrl" or "control": control = true; break;
                case "alt" or "mod1": alt = true; break;
                case "shift": shift = true; break;
                case "win" or "windows" or "super" or "mod4": command = true; break;
                case "space" or "spacebar": key = "space"; break;
                case "oemclosebrackets" or "oem6" or "bracketright": key = "]"; break;
                case "oemopenbrackets" or "oem4" or "bracketleft": key = "["; break;
                case var name when name.Length == 1: key = name; break;
                case var name when name.Length == 2 && name[0] == 'd' && char.IsAsciiDigit(name[1]): key = name[1].ToString(); break;
                default: key = raw.ToLowerInvariant(); break;
            }
        }
        return key is null ? null : new KeyCombination(control, alt, shift, command, key);
    }
}

/// <summary>
/// How the one shortcut is shared with terminal windows on Windows and Linux.
/// A registered global shortcut is consumed before the window in front sees it,
/// so a terminal can only receive the combination while Baddel is not holding it.
/// With pass-through active, Baddel releases the shortcut whenever a terminal
/// window is in front and takes it back when another window is.
/// </summary>
public static class TerminalSharing
{
    /// <summary>The marker a shell or Claude Code integration leaves when it first asks for its key.</summary>
    public const string SeenMarker = "terminal-integration";

    public static bool IntegrationSeen(string settingsDirectory) => File.Exists(Path.Combine(settingsDirectory, SeenMarker));

    public static void MarkSeen(string settingsDirectory)
    {
        try
        {
            Directory.CreateDirectory(settingsDirectory);
            var marker = Path.Combine(settingsDirectory, SeenMarker);
            if (!File.Exists(marker)) File.WriteAllText(marker, "A Baddel terminal integration asked for the shortcut.\n");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
        }
    }

    /// <param name="mode"><c>automatic</c> (default), <c>on</c> or <c>off</c>.</param>
    public static bool IsActive(string? mode, bool integrationSeen, TerminalKey? key) =>
        key is { IsDeliverable: true } && (mode?.ToLowerInvariant()) switch
        {
            "on" => true,
            "off" => false,
            _ => integrationSeen,
        };

    public static string ReasonText(string? reason) => reason switch
    {
        "usesCommandKey" => "Terminals do not pass on combinations that use the Windows or Super key.",
        "reservedInTerminals" => "That combination already has a fixed meaning in every terminal.",
        "needsControlOrAlt" => "A terminal needs Ctrl or Alt in the combination.",
        _ => "A terminal sends nothing a program could recognise for that key.",
    };

    /// <summary>One place that says what is active.</summary>
    public static List<string> Summary(string shortcut, TerminalKey? key, string? mode, bool integrationSeen, string shell)
    {
        var lines = new List<string> { $"Shortcut: {shortcut} (set in Baddel's settings; used everywhere)" };
        if (key is not { IsDeliverable: true })
        {
            lines.Add($"In a terminal: not available. {ReasonText(key?.Reason)} The shell integration falls back to Ctrl+T, and Claude Code to Ctrl+G.");
            return lines;
        }
        var sharing = (mode?.ToLowerInvariant()) switch
        {
            "on" => "on",
            "off" => "off (the shortcut is not passed to terminal windows)",
            _ => integrationSeen
                ? "on (automatic: a terminal integration is installed)"
                : "waiting (automatic: starts when a shell or Claude Code integration first asks for the key)",
        };
        lines.Add($"Passed to terminal windows: {sharing}");
        if (shell == "PowerShell" && key.PsReadLineChord is null)
        {
            lines.Add("PowerShell: uses Ctrl+T. PSReadLine reads Ctrl+Alt+Space as Space (AltGr), so it cannot be given this shortcut. "
                + "A shortcut such as Ctrl+Shift+Space works in both.");
            lines.Add($"Claude Code receives it as {string.Join(" or ", key.ClaudeKeystrokes)}.");
        }
        else
        {
            lines.Add($"{shell} and Claude Code receive it as {string.Join(" or ", key.ClaudeKeystrokes)}.");
        }
        return lines;
    }

    /// <summary>The entry a user adds to Claude Code's <c>keybindings.json</c>. Baddel never writes that file.</summary>
    public static List<string> ClaudeSnippet(TerminalKey key)
    {
        var lines = new List<string>
        {
            "# Add this to the \"bindings\" list in ~/.claude/keybindings.json. Ctrl+G keeps working.",
            "{", "  \"bindings\": [", "    {", "      \"context\": \"Chat\",", "      \"bindings\": {",
            string.Join(",\n", key.ClaudeKeystrokes.Select(k => $"        \"{k}\": \"chat:externalEditor\"")),
            "      }", "    }", "  ]", "}",
        };
        return lines;
    }

    /// <summary>
    /// <c>baddel --terminal-key zsh|bash|pwsh|claude|status</c>. A shell or Claude Code
    /// asking for its key is how Baddel learns that a terminal integration is
    /// installed, which is what automatic pass-through waits for.
    /// </summary>
    public static int RunCommand(
        string? target, string shortcut, TerminalPlatform platform, string? mode, string settingsDirectory, string shell,
        TextWriter output, TextWriter error)
    {
        var key = TerminalKey.Parse(shortcut) is { } combination ? TerminalKey.Resolve(combination, platform) : null;
        switch (target ?? "status")
        {
            case "zsh" or "bash":
                MarkSeen(settingsDirectory);
                if (key is not { IsDeliverable: true }) { output.Write($"no {key?.Reason ?? "unknown"}\n"); return 1; }
                output.Write("ok\n" + string.Join("\n", key.Notation(zsh: target == "zsh")) + "\n");
                return 0;
            case "pwsh":
                if (key?.PsReadLineChord is not { } chord)
                {
                    output.Write($"no {key?.Reason ?? "ctrlAltSpaceIsAltGrSpace"}\n");
                    return 1;
                }
                MarkSeen(settingsDirectory);
                output.Write($"ok\n{chord}\n");
                return 0;
            case "claude":
                if (key is not { IsDeliverable: true })
                {
                    output.Write($"# {ReasonText(key?.Reason)} Use Ctrl+G in Claude Code, or choose another shortcut in Baddel's settings.\n");
                    return 1;
                }
                MarkSeen(settingsDirectory);
                output.Write(string.Join("\n", ClaudeSnippet(key)) + "\n");
                return 0;
            case "status":
                output.Write(string.Join("\n", Summary(shortcut, key, mode, IntegrationSeen(settingsDirectory), shell)) + "\n");
                return 0;
            default:
                error.WriteLine("baddel: usage: --terminal-key zsh|bash|pwsh|claude|status");
                return 2;
        }
    }
}
