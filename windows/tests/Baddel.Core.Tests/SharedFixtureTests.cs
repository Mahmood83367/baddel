using System.Text.Json;
using Baddel.Core;
using Xunit;

namespace Baddel.Core.Tests;

/// <summary>
/// Runs the fixtures in <c>shared/fixtures/cases.json</c>, the same file the
/// Swift test suite runs.
/// </summary>
public class SharedFixtureTests
{
    private static readonly string Shared = FindShared();
    private static readonly LayoutStore Store = new(Path.Combine(Shared, "layouts"));
    private static readonly JsonElement Cases =
        JsonDocument.Parse(File.ReadAllText(Path.Combine(Shared, "fixtures", "cases.json"))).RootElement;

    internal static string FindShared()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine(directory.FullName, "shared");
            if (File.Exists(Path.Combine(candidate, "fixtures", "cases.json"))) return candidate;
            directory = directory.Parent;
        }
        throw new DirectoryNotFoundException("shared/fixtures/cases.json not found");
    }

    private static string CamelCase(Enum value)
    {
        var name = value.ToString();
        return char.ToLowerInvariant(name[0]) + name[1..];
    }

    private static Script? ParseHint(JsonElement element) =>
        element.ValueKind == JsonValueKind.String ? ScriptExtensions.Parse(element.GetString()!) : null;

    [Fact]
    public void LayoutsLoad()
    {
        Assert.Equal(new[] { "arabic-mac", "arabic-pc", "arabic-windows-101", "arabic-windows-102", "uk-english-mac", "uk-english-windows", "us-english" }, Store.Layouts.Keys.OrderBy(k => k, StringComparer.Ordinal).ToArray());
        Assert.All(Store.Layouts.Values, layout => Assert.Equal(47, layout.Keys.Count));
    }

    [Fact]
    public void Conversions()
    {
        var count = 0;
        foreach (var c in Cases.GetProperty("conversions").EnumerateArray())
        {
            var converter = new LayoutConverter(
                Store.Get(c.GetProperty("from").GetString()!), Store.Get(c.GetProperty("to").GetString()!));
            Assert.True(
                c.GetProperty("output").GetString() == converter.Convert(c.GetProperty("input").GetString()!),
                c.GetProperty("name").GetString());
            count++;
        }
        Assert.True(count > 20);
    }

    [Fact]
    public void Plans()
    {
        var count = 0;
        foreach (var c in Cases.GetProperty("plans").EnumerateArray())
        {
            var name = c.GetProperty("name").GetString();
            var planner = new CorrectionPlanner(
                new LayoutPair(Store.Get("us-english"), Store.Get(c.GetProperty("arabicLayout").GetString()!)));
            var t = c.GetProperty("target");
            var target = t.GetProperty("type").GetString() switch
            {
                "lastWord" => CorrectionTarget.ForLastWord(t.GetProperty("caret").GetInt32()),
                "selection" => CorrectionTarget.ForSelection(
                    new Utf16Range(t.GetProperty("location").GetInt32(), t.GetProperty("length").GetInt32())),
                _ => CorrectionTarget.ForWholeField(),
            };
            var result = planner.Plan(c.GetProperty("text").GetString()!, target, ParseHint(c.GetProperty("hint")));
            var expect = c.GetProperty("expect");
            if (expect.TryGetProperty("reject", out var reject))
            {
                Assert.True(result.Plan is null, name);
                Assert.True(reject.GetString() == CamelCase(result.Rejection!.Value), name);
            }
            else
            {
                Assert.True(result.Plan is not null, name);
                var plan = result.Plan!;
                Assert.True(expect.GetProperty("location").GetInt32() == plan.Range.Location, name);
                Assert.True(expect.GetProperty("length").GetInt32() == plan.Range.Length, name);
                Assert.True(expect.GetProperty("replacement").GetString() == plan.Replacement, name);
                Assert.True(ScriptExtensions.Parse(expect.GetProperty("sourceScript").GetString()!) == plan.SourceScript, name);
            }
            count++;
        }
        Assert.True(count > 30);
    }

    [Fact]
    public void DoublePress()
    {
        var count = 0;
        foreach (var c in Cases.GetProperty("doublePress").EnumerateArray())
        {
            var detector = new DoublePressDetector(c.GetProperty("windowMs").GetInt32());
            var actions = new List<string>();
            foreach (var e in c.GetProperty("events").EnumerateArray())
            {
                switch (e.GetProperty("type").GetString())
                {
                    case "press":
                        actions.Add(CamelCase(detector.Press(e.GetProperty("t").GetInt32(), false)));
                        break;
                    case "repeat":
                        actions.Add(CamelCase(detector.Press(e.GetProperty("t").GetInt32(), true)));
                        break;
                    case "release":
                        detector.Release();
                        actions.Add("none");
                        break;
                    case "timeout":
                        actions.Add(CamelCase(detector.Timeout(detector.Generation)));
                        break;
                    case "staleTimeout":
                        actions.Add(CamelCase(detector.Timeout(detector.Generation - 1)));
                        break;
                }
            }
            var expected = c.GetProperty("expect").EnumerateArray().Select(a => a.GetString()!).ToList();
            Assert.True(expected.SequenceEqual(actions), c.GetProperty("name").GetString());
            count++;
        }
        Assert.True(count > 5);
    }
}
