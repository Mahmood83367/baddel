using System.Text;

namespace Baddel.Core;

/// <summary>
/// Converts text typed with the source layout into what the same key presses
/// produce with the target layout. Mirrors <c>LayoutConverter.swift</c>:
/// unshifted keys win reverse lookups, multi-character outputs are matched
/// longest-first, an empty shifted output falls back to the unshifted one, and
/// anything the source layout cannot produce passes through unchanged.
/// </summary>
public sealed class LayoutConverter
{
    private readonly Dictionary<string, string> table = new(StringComparer.Ordinal);
    private readonly int maxLength = 1;

    public LayoutConverter(KeyboardLayout source, KeyboardLayout target)
    {
        var targetKeys = new Dictionary<string, LayoutKey>();
        foreach (var key in target.Keys)
        {
            targetKeys.TryAdd(key.Code, key);
        }
        foreach (var shifted in new[] { false, true })
        {
            foreach (var key in source.Keys)
            {
                var output = shifted ? key.Shift : key.Base;
                if (output.Length == 0 || table.ContainsKey(output) || !targetKeys.TryGetValue(key.Code, out var targetKey))
                {
                    continue;
                }
                var replacement = shifted ? targetKey.Shift : targetKey.Base;
                if (replacement.Length == 0)
                {
                    replacement = targetKey.Base;
                }
                if (replacement.Length == 0)
                {
                    continue;
                }
                table[output] = replacement;
                maxLength = Math.Max(maxLength, output.Length);
            }
        }
    }

    public string Convert(string text)
    {
        var result = new StringBuilder(text.Length);
        var index = 0;
        while (index < text.Length)
        {
            var matched = false;
            for (var length = Math.Min(maxLength, text.Length - index); length >= 1; length--)
            {
                if (table.TryGetValue(text.Substring(index, length), out var replacement))
                {
                    result.Append(replacement);
                    index += length;
                    matched = true;
                    break;
                }
            }
            if (!matched)
            {
                result.Append(text[index]);
                index++;
            }
        }
        return result.ToString();
    }
}
