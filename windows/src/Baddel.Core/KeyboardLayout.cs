using System.Text.Json;

namespace Baddel.Core;

public enum Script
{
    Latin,
    Arabic,
}

public static class ScriptExtensions
{
    public static Script Opposite(this Script script) => script == Script.Latin ? Script.Arabic : Script.Latin;

    public static Script Parse(string value) => value == "arabic" ? Script.Arabic : Script.Latin;
}

/// <summary>One physical key: W3C code name and its unshifted and shifted output.</summary>
public sealed record LayoutKey(string Code, string Base, string Shift);

/// <summary>
/// A keyboard layout loaded from <c>shared/layouts/*.json</c>, the same data the
/// macOS implementation uses. Keys keep their file order so reverse lookups are
/// deterministic on both platforms.
/// </summary>
public sealed class KeyboardLayout
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public required Script Script { get; init; }
    public required IReadOnlyDictionary<string, IReadOnlyList<string>> PlatformIds { get; init; }
    public required IReadOnlyList<LayoutKey> Keys { get; init; }

    public static KeyboardLayout Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var platformIds = new Dictionary<string, IReadOnlyList<string>>();
        foreach (var platform in root.GetProperty("platformIds").EnumerateObject())
        {
            platformIds[platform.Name] = platform.Value.EnumerateArray().Select(e => e.GetString()!).ToList();
        }
        var keys = root.GetProperty("keys").EnumerateArray()
            .Select(k => new LayoutKey(
                k.GetProperty("code").GetString()!,
                k.GetProperty("base").GetString()!,
                k.GetProperty("shift").GetString()!))
            .ToList();
        return new KeyboardLayout
        {
            Id = root.GetProperty("id").GetString()!,
            Name = root.GetProperty("name").GetString()!,
            Script = ScriptExtensions.Parse(root.GetProperty("script").GetString()!),
            PlatformIds = platformIds,
            Keys = keys,
        };
    }
}

public sealed record LayoutPair(KeyboardLayout Latin, KeyboardLayout Arabic);

public sealed class LayoutStore
{
    public IReadOnlyDictionary<string, KeyboardLayout> Layouts { get; }

    public LayoutStore(string directory)
        : this(Directory.GetFiles(directory, "*.json")
            .OrderBy(path => path, StringComparer.Ordinal)
            .Select(File.ReadAllText))
    {
    }

    public LayoutStore(IEnumerable<KeyboardLayout> layouts)
    {
        Layouts = layouts.ToDictionary(layout => layout.Id);
    }

    /// <summary>Builds a store from layout JSON documents (for example embedded resources).</summary>
    public LayoutStore(IEnumerable<string> documents)
    {
        Layouts = documents.Select(KeyboardLayout.Parse).ToDictionary(layout => layout.Id);
    }

    public KeyboardLayout Get(string id) => Layouts[id];
}
