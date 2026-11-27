using System.Text;
using System.Text.Json;
using Baddel.Core;
using Xunit;

namespace Baddel.Core.Tests;

/// <summary>Runs <c>shared/fixtures/updates.json</c>, which the Swift implementation runs too.</summary>
public class UpdateTests
{
    private static readonly string Fixtures = Path.Combine(SharedFixtureTests.FindShared(), "fixtures");
    private static readonly JsonElement Data = JsonDocument.Parse(File.ReadAllText(Path.Combine(Fixtures, "updates.json"))).RootElement;

    [Fact]
    public void VersionOrdering()
    {
        var texts = Data.GetProperty("versionOrder").EnumerateArray().Select(v => v.GetString()!).ToList();
        var versions = texts.Select(t => SemanticVersion.Parse(t)!).ToList();
        for (var index = 0; index < versions.Count; index++)
        {
            Assert.Equal(texts[index], versions[index].ToString());
            Assert.Equal(0, versions[index].CompareTo(versions[index]));
            for (var later = index + 1; later < versions.Count; later++)
            {
                Assert.True(versions[index].CompareTo(versions[later]) < 0, $"{texts[index]} < {texts[later]}");
                Assert.True(versions[later].CompareTo(versions[index]) > 0, $"{texts[later]} > {texts[index]}");
            }
        }
        foreach (var invalid in Data.GetProperty("invalidVersions").EnumerateArray())
        {
            Assert.True(SemanticVersion.Parse(invalid.GetString()!) is null, invalid.GetString());
        }
        foreach (var pair in Data.GetProperty("equalVersions").EnumerateArray())
        {
            Assert.Equal(SemanticVersion.Parse(pair[0].GetString()!), SemanticVersion.Parse(pair[1].GetString()!));
        }
    }

    [Fact]
    public void ChannelSelection()
    {
        var count = 0;
        foreach (var c in Data.GetProperty("releaseChecks").EnumerateArray())
        {
            var name = c.GetProperty("name").GetString();
            var result = UpdateCheck.Evaluate(
                c.GetProperty("releases").GetRawText(), c.GetProperty("current").GetString()!,
                UpdateCheck.ParseChannel(c.GetProperty("channel").GetString())!.Value);
            Assert.True(result is not null, name);
            var latest = c.GetProperty("latest").ValueKind == JsonValueKind.Null ? null : c.GetProperty("latest").GetString();
            Assert.True(latest == result!.Latest, name);
            Assert.True(c.GetProperty("updateAvailable").GetBoolean() == result.UpdateAvailable, name);
            if (result.ReleasePage is not null) Assert.StartsWith(UpdateCheck.OfficialReleasePrefix, result.ReleasePage);
            count++;
        }
        Assert.True(count > 8);
        Assert.Null(UpdateCheck.Evaluate("not json", "0.1.0", UpdateChannel.Stable));
        Assert.Null(UpdateCheck.Evaluate("[]", "garbage", UpdateChannel.Stable));
        Assert.Null(UpdateCheck.Evaluate("{}", "0.1.0", UpdateChannel.Stable));
    }

    [Fact]
    public void SignedManifest()
    {
        var m = Data.GetProperty("manifest");
        var data = File.ReadAllBytes(Path.Combine(Fixtures, m.GetProperty("file").GetString()!));
        var signature = Convert.FromBase64String(m.GetProperty("signatureBase64").GetString()!);
        var key = Convert.FromBase64String(m.GetProperty("publicKeyBase64").GetString()!);
        var other = Convert.FromBase64String(m.GetProperty("otherPublicKeyBase64").GetString()!);

        var (manifest, failure) = UpdateManifest.Verified(data, signature, new[] { other, key }, UpdateChannel.Preview, "0.2.0");
        Assert.Null(failure);
        Assert.Equal(m.GetProperty("version").GetString(), manifest!.Version);

        // No trusted key, a different key, a changed byte, a damaged signature: all refused.
        Assert.Equal(ManifestFailure.NoTrustedKey, UpdateManifest.Verified(data, signature, Array.Empty<byte[]>(), UpdateChannel.Preview, "0.2.0").Failure);
        Assert.Equal(ManifestFailure.BadSignature, UpdateManifest.Verified(data, signature, new[] { other }, UpdateChannel.Preview, "0.2.0").Failure);
        var tampered = (byte[])data.Clone();
        tampered[tampered.Length / 2] ^= 0x01;
        Assert.Equal(ManifestFailure.BadSignature, UpdateManifest.Verified(tampered, signature, new[] { key }, UpdateChannel.Preview, "0.2.0").Failure);
        var damaged = (byte[])signature.Clone();
        damaged[^1] ^= 0x01;
        Assert.Equal(ManifestFailure.BadSignature, UpdateManifest.Verified(data, damaged, new[] { key }, UpdateChannel.Preview, "0.2.0").Failure);
        Assert.Equal(ManifestFailure.BadSignature, UpdateManifest.Verified(data, Array.Empty<byte>(), new[] { key }, UpdateChannel.Preview, "0.2.0").Failure);
        // Correctly signed, but for another channel or not newer.
        Assert.Equal(ManifestFailure.WrongChannel, UpdateManifest.Verified(data, signature, new[] { key }, UpdateChannel.Stable, "0.2.0").Failure);
        Assert.Equal(ManifestFailure.NotNewer, UpdateManifest.Verified(data, signature, new[] { key }, UpdateChannel.Preview, "10.0.0").Failure);

        var package = manifest.Package("windows", "x64", "10.0.26200");
        Assert.NotNull(package);
        Assert.StartsWith(UpdateCheck.OfficialReleasePrefix + "download/", package!.Url);
        Assert.Null(manifest.Package("macos", "arm64", "12.6"));
        Assert.Null(manifest.Package("linux", "x64", "6.0"));
        Assert.Equal("macos", manifest.Package("macos", "arm64", "14.2")!.Platform);

        var bytes = Encoding.UTF8.GetBytes(m.GetProperty("packageBytesUtf8").GetString()!);
        Assert.True(UpdateManifest.Matches(package, bytes));
        Assert.False(UpdateManifest.Matches(package, Encoding.UTF8.GetBytes("abd")));
        Assert.False(UpdateManifest.Matches(package, Encoding.UTF8.GetBytes("abcd")));
    }

    [Fact]
    public void NoUpdateKeyIsTrustedYet()
    {
        // Until a real update signing key exists, nothing can be installed automatically.
        Assert.Empty(UpdateManifest.TrustedKeys);
        Assert.False(UpdateManifest.AutomaticInstallationPossible);
    }
}

public class LayoutValidatorTests
{
    private static readonly LayoutStore Store = new(Path.Combine(SharedFixtureTests.FindShared(), "layouts"));

    private static KeyboardLayout Layout(string id = "custom-test", Action<List<LayoutKey>>? edit = null)
    {
        var keys = Store.Get("us-english").Keys.ToList();
        edit?.Invoke(keys);
        return new KeyboardLayout
        {
            Id = id, Name = "Test", Script = Script.Latin,
            PlatformIds = new Dictionary<string, IReadOnlyList<string>>(), Keys = keys,
        };
    }

    private static string[] Codes(KeyboardLayout layout) =>
        LayoutValidator.Validate(layout).Select(p => $"{p.Code}:{p.Key ?? "-"}").ToArray();

    [Fact]
    public void EveryBuiltInLayoutIsValid()
    {
        Assert.All(Store.Layouts.Values, layout => Assert.DoesNotContain(LayoutValidator.Validate(layout), p => p.IsError));
        Assert.Equal(47, LayoutValidator.StandardKeyCodes.Count);
        Assert.Equal(LayoutValidator.StandardKeyCodes, Store.Get("us-english").Keys.Select(k => k.Code));
    }

    [Fact]
    public void ProblemsAreReported()
    {
        Assert.Empty(Codes(Layout()));
        Assert.Equal(new[] { "InvalidId:-" }, Codes(Layout("Bad Id")));
        Assert.Equal(new[] { "InvalidId:-" }, Codes(Layout("")));
        Assert.Equal(new[] { "MissingKey:Slash" }, Codes(Layout(edit: k => k.RemoveAt(k.Count - 1))));
        Assert.Equal(new[] { "DuplicateKey:KeyQ", "DuplicateOutput:KeyQ", "DuplicateOutput:KeyQ" }, Codes(Layout(edit: k => k.Add(new LayoutKey("KeyQ", "q", "Q")))));
        Assert.Equal(new[] { "UnknownKey:IntlBackslash" }, Codes(Layout(edit: k => k.Add(new LayoutKey("IntlBackslash", "x", "X")))));
        Assert.Equal(new[] { "EmptyBase:Backquote" }, Codes(Layout(edit: k => k[0] = new LayoutKey("Backquote", "", "~"))));
        Assert.Equal(new[] { "OutputTooLong:Backquote" }, Codes(Layout(edit: k => k[0] = new LayoutKey("Backquote", "abcde", "~"))));
        Assert.Equal(new[] { "InvalidCharacter:Backquote" }, Codes(Layout(edit: k => k[0] = new LayoutKey("Backquote", " ", "~"))));
        Assert.Equal(new[] { "InvalidCharacter:Backquote" }, Codes(Layout(edit: k => k[0] = new LayoutKey("Backquote", "\u0007", "~"))));
        var duplicate = LayoutValidator.Validate(Layout(edit: k => k[0] = new LayoutKey("Backquote", "1", "~")));
        Assert.Equal(new[] { LayoutProblemCode.DuplicateOutput }, duplicate.Select(p => p.Code));
        Assert.False(duplicate[0].IsError);
    }

    [Fact]
    public void CustomLayoutsAreAddedOnlyWhenValidAndNeverReplaceBuiltIns()
    {
        var directory = Path.Combine(Path.GetTempPath(), "baddel-custom-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            void Write(string name, KeyboardLayout layout) => File.WriteAllText(Path.Combine(directory, name), JsonSerializer.Serialize(new
            {
                id = layout.Id, name = layout.Name, script = "latin", platformIds = new Dictionary<string, string[]>(),
                keys = layout.Keys.Select(k => new { code = k.Code, @base = k.Base, shift = k.Shift }),
            }));
            Write("a-good.json", Layout("custom-dvorak-ish"));
            Write("b-not-prefixed.json", Layout("my-layout"));
            Write("c-shadows-built-in.json", Layout("us-english"));
            Write("d-missing-key.json", Layout("custom-broken", k => k.RemoveAt(k.Count - 1)));
            File.WriteAllText(Path.Combine(directory, "e-garbage.json"), "{ not json");
            File.WriteAllText(Path.Combine(directory, "notes.txt"), "ignored");

            var (store, reports) = LayoutValidator.AddCustomLayouts(Store, directory);
            Assert.Equal(new[] { "a-good.json", "b-not-prefixed.json", "c-shadows-built-in.json", "d-missing-key.json", "e-garbage.json" }, reports.Select(r => r.File));
            Assert.Equal(new[] { true, false, false, false, false }, reports.Select(r => r.Accepted));
            Assert.Equal(Store.Layouts.Count + 1, store.Layouts.Count);
            Assert.Empty(store.Get("custom-dvorak-ish").PlatformIds);
            Assert.Same(Store.Get("us-english"), store.Get("us-english"));

            var none = LayoutValidator.AddCustomLayouts(Store, Path.Combine(directory, "missing"));
            Assert.Equal(Store.Layouts.Count, none.Store.Layouts.Count);
            Assert.Empty(none.Reports);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }
}
