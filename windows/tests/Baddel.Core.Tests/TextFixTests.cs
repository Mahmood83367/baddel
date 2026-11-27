using System.Text;
using System.Text.Json;
using Baddel.Core;
using Xunit;

namespace Baddel.Core.Tests;

/// <summary>Runs <c>shared/fixtures/text-fix.json</c>, the same file the Swift test suite runs.</summary>
public class TextFixTests
{
    private static readonly string Shared = SharedFixtureTests.FindShared();
    private static readonly LayoutStore Store = new(Path.Combine(Shared, "layouts"));

    private static LayoutPair Pair(string arabic = "arabic-pc") => new(Store.Get("us-english"), Store.Get(arabic));

    [Fact]
    public void SharedCases()
    {
        var cases = JsonDocument.Parse(File.ReadAllText(Path.Combine(Shared, "fixtures", "text-fix.json"))).RootElement.GetProperty("cases");
        Assert.True(cases.GetArrayLength() > 20);
        foreach (var c in cases.EnumerateArray())
        {
            var name = c.GetProperty("name").GetString()!;
            var selection = c.GetProperty("selection");
            var hint = c.GetProperty("hint");
            var request = new TextFixRequest(c.GetProperty("text").GetString()!, Enum.Parse<TextFixMode>(c.GetProperty("mode").GetString()!, true))
            {
                Unit = Enum.Parse<TextFixUnit>(c.GetProperty("unit").GetString()!, true),
                Cursor = c.GetProperty("cursor").ValueKind == JsonValueKind.Number ? c.GetProperty("cursor").GetInt32() : null,
                Selection = selection.ValueKind == JsonValueKind.Array ? new Utf16Range(selection[0].GetInt32(), selection[1].GetInt32()) : null,
                Hint = hint.ValueKind == JsonValueKind.String ? ScriptExtensions.Parse(hint.GetString()!) : null,
                KeepsClaudePlaceholders = c.GetProperty("claude").GetBoolean(),
            };
            var result = TextFix.Run(request, new CorrectionPlanner(Pair(c.GetProperty("arabicLayout").GetString()!)));
            var expect = c.GetProperty("expect");
            if (expect.TryGetProperty("reject", out var reject))
            {
                Assert.True(result.Output is null, name);
                Assert.Equal(reject.GetString(), TextFixCommand.Code(result.Rejection!.Value));
            }
            else
            {
                Assert.True(result.Output is not null, name);
                Assert.Equal(expect.GetProperty("text").GetString(), result.Output!.Text);
                Assert.True(expect.GetProperty("cursor").GetInt32() == result.Output.Cursor, $"{name}: cursor {result.Output.Cursor}");
            }
        }
    }

    private static (int Exit, string Out, string Err) Command(string input, params string[] args)
    {
        using var stdin = new MemoryStream(Encoding.UTF8.GetBytes(input));
        using var stdout = new MemoryStream();
        var stderr = new StringWriter();
        var exit = TextFixCommand.Run(args, () => Pair(), () => null, stdin, stdout, stderr);
        return (exit, Encoding.UTF8.GetString(stdout.ToArray()), stderr.ToString());
    }

    [Fact]
    public void CommandAnswersWithStatusLineAndBuffer()
    {
        Assert.Equal((0, "ok 10\necho عليكم", ""), Command("echo ugd;l", "--fix-text", "--unit", "scalars", "--cursor", "10"));
        Assert.Equal((0, "ok 11\nعليكم عليكم", ""), Command("ugd;l ugd;l", "--fix-text", "--mode", "line"));
        Assert.Equal((1, "no noWord\n", ""), Command("  ", "--fix-text"));
        Assert.Equal(2, Command("x", "--fix-text", "--mode", "paragraph").Exit);
        Assert.Equal(2, Command("x", "--fix-text", "--cursor").Exit);
        Assert.Equal(2, Command("x", "--fix-draft").Exit);
    }

    [Fact]
    public void DraftFileIsRewrittenOnlyWhenCorrected()
    {
        var directory = Directory.CreateTempSubdirectory("baddel-draft-test");
        try
        {
            var draft = Path.Combine(directory.FullName, "claude-prompt-test.md");
            File.WriteAllText(draft, "ugd;l [Image #1]\n");
            Assert.Equal((0, "", "baddel: draft corrected" + Environment.NewLine), Command("", "--fix-draft", draft));
            Assert.Equal("عليكم [Image #1]\n", File.ReadAllText(draft));

            File.WriteAllText(draft, "[Image #1]");
            var stamp = File.GetLastWriteTimeUtc(draft);
            Assert.Equal(1, Command("", "--fix-draft", draft).Exit);
            Assert.Equal("[Image #1]", File.ReadAllText(draft));
            Assert.Equal(stamp, File.GetLastWriteTimeUtc(draft));

            // Any other file is refused unless asked for, so a global EDITOR cannot rewrite it.
            var other = Path.Combine(directory.FullName, "COMMIT_EDITMSG");
            File.WriteAllText(other, "ugd;l");
            var refused = Command("", "--fix-draft", other);
            Assert.Equal(1, refused.Exit);
            Assert.Contains("notAClaudeDraft", refused.Err);
            Assert.Equal("ugd;l", File.ReadAllText(other));
            Assert.Equal(0, Command("", "--fix-draft", "--any-file", other).Exit);
            Assert.Equal("عليكم", File.ReadAllText(other));

            // Invalid UTF-8 is left alone.
            File.WriteAllBytes(draft, new byte[] { 0x75, 0xFF, 0x67 });
            Assert.Equal(1, Command("", "--fix-draft", draft).Exit);
            Assert.Equal(new byte[] { 0x75, 0xFF, 0x67 }, File.ReadAllBytes(draft));
        }
        finally
        {
            directory.Delete(recursive: true);
        }
    }
}
