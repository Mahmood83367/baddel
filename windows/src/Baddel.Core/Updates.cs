using System.Security.Cryptography;
using System.Text.Json;

namespace Baddel.Core;

/// <summary>A semantic version: <c>MAJOR.MINOR.PATCH</c> with an optional pre-release part.</summary>
public sealed class SemanticVersion : IComparable<SemanticVersion>, IEquatable<SemanticVersion>
{
    public int Major { get; }
    public int Minor { get; }
    public int Patch { get; }
    public IReadOnlyList<string> Prerelease { get; }

    private SemanticVersion(int major, int minor, int patch, IReadOnlyList<string> prerelease)
    {
        Major = major;
        Minor = minor;
        Patch = patch;
        Prerelease = prerelease;
    }

    public bool IsPrerelease => Prerelease.Count > 0;

    /// <summary>Accepts <c>1.2.3</c>, <c>1.2.3-preview.1</c>, and the same with a leading <c>v</c>.</summary>
    public static SemanticVersion? Parse(string text)
    {
        var body = text.StartsWith('v') ? text[1..] : text;
        var plus = body.IndexOf('+');
        if (plus >= 0) body = body[..plus];
        var dash = body.IndexOf('-');
        var numbers = (dash >= 0 ? body[..dash] : body).Split('.');
        if (numbers.Length != 3) return null;
        var parsed = new int[3];
        for (var index = 0; index < 3; index++)
        {
            var part = numbers[index];
            if (part.Length is 0 or > 9 || !part.All(c => c is >= '0' and <= '9')) return null;
            parsed[index] = int.Parse(part, System.Globalization.CultureInfo.InvariantCulture);
        }
        var prerelease = Array.Empty<string>();
        if (dash >= 0)
        {
            prerelease = body[(dash + 1)..].Split('.');
            if (prerelease.Length == 0
                || prerelease.Any(p => p.Length == 0 || !p.All(c => c is (>= '0' and <= '9') or (>= 'a' and <= 'z') or (>= 'A' and <= 'Z') or '-')))
            {
                return null;
            }
        }
        return new SemanticVersion(parsed[0], parsed[1], parsed[2], prerelease);
    }

    public override string ToString() =>
        $"{Major}.{Minor}.{Patch}" + (Prerelease.Count == 0 ? string.Empty : "-" + string.Join('.', Prerelease));

    public int CompareTo(SemanticVersion? other)
    {
        if (other is null) return 1;
        if (Major != other.Major) return Major.CompareTo(other.Major);
        if (Minor != other.Minor) return Minor.CompareTo(other.Minor);
        if (Patch != other.Patch) return Patch.CompareTo(other.Patch);
        // A version with a pre-release part comes before the same version without one.
        if (Prerelease.Count == 0 || other.Prerelease.Count == 0)
        {
            return (Prerelease.Count == 0 ? 1 : 0) - (other.Prerelease.Count == 0 ? 1 : 0);
        }
        for (var index = 0; index < Math.Min(Prerelease.Count, other.Prerelease.Count); index++)
        {
            string x = Prerelease[index], y = other.Prerelease[index];
            if (x == y) continue;
            var xNumber = x.All(char.IsAsciiDigit) && int.TryParse(x, out var i);
            var yNumber = y.All(char.IsAsciiDigit) && int.TryParse(y, out var j);
            if (xNumber && yNumber) return int.Parse(x).CompareTo(int.Parse(y));
            if (xNumber) return -1;
            if (yNumber) return 1;
            return string.CompareOrdinal(x, y) < 0 ? -1 : 1;
        }
        return Prerelease.Count.CompareTo(other.Prerelease.Count);
    }

    public bool Equals(SemanticVersion? other) => other is not null && CompareTo(other) == 0;
    public override bool Equals(object? obj) => Equals(obj as SemanticVersion);
    public override int GetHashCode() => HashCode.Combine(Major, Minor, Patch, string.Join('.', Prerelease));
}

/// <summary>Which releases a user wants to hear about.</summary>
public enum UpdateChannel
{
    /// <summary>Full releases only.</summary>
    Stable,

    /// <summary>Full releases and previews (GitHub "pre-release").</summary>
    Preview,
}

public sealed record UpdateCheckResult(string Current, UpdateChannel Channel, string? Latest, string? ReleasePage, bool UpdateAvailable);

public static class UpdateCheck
{
    /// <summary>Only pages and files of the official repository's releases are accepted.</summary>
    public const string OfficialReleasePrefix = "https://github.com/Mahmood83367/baddel/releases/";
    public const string ReleasesApi = "https://api.github.com/repos/Mahmood83367/baddel/releases?per_page=30";

    public static UpdateChannel? ParseChannel(string? text) => text?.ToLowerInvariant() switch
    {
        "stable" => UpdateChannel.Stable,
        "preview" => UpdateChannel.Preview,
        _ => null,
    };

    /// <summary>
    /// Picks the newest release of a channel from the GitHub releases API response.
    /// Drafts, tags that are not versions, and anything not hosted on the official
    /// releases page are ignored. Returns <c>null</c> if the input cannot be read.
    /// </summary>
    public static UpdateCheckResult? Evaluate(string releasesJson, string current, UpdateChannel channel)
    {
        var currentVersion = SemanticVersion.Parse(current);
        if (currentVersion is null) return null;
        SemanticVersion? newest = null;
        string? page = null;
        try
        {
            using var document = JsonDocument.Parse(releasesJson);
            if (document.RootElement.ValueKind != JsonValueKind.Array) return null;
            foreach (var release in document.RootElement.EnumerateArray())
            {
                if (release.GetProperty("draft").GetBoolean()) continue;
                var url = release.GetProperty("html_url").GetString() ?? string.Empty;
                if (!url.StartsWith(OfficialReleasePrefix, StringComparison.Ordinal)) continue;
                var version = SemanticVersion.Parse(release.GetProperty("tag_name").GetString() ?? string.Empty);
                if (version is null) continue;
                var preview = release.GetProperty("prerelease").GetBoolean() || version.IsPrerelease;
                if (channel == UpdateChannel.Stable && preview) continue;
                if (newest is null || newest.CompareTo(version) < 0)
                {
                    newest = version;
                    page = url;
                }
            }
        }
        catch (Exception exception) when (exception is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            return null;
        }
        return newest is null
            ? new UpdateCheckResult(current, channel, null, null, false)
            : new UpdateCheckResult(current, channel, newest.ToString(), page, currentVersion.CompareTo(newest) < 0);
    }
}

public enum ManifestFailure
{
    NoTrustedKey,
    BadSignature,
    Malformed,
    UnsupportedSchema,
    WrongChannel,
    NotNewer,
    NoPackageForThisSystem,
    UntrustedLocation,
}

public sealed record UpdatePackage(string Platform, string Arch, string MinOS, string Url, string Sha256, long Size);

/// <summary>
/// A signed description of one release, the basis for installing an update.
/// Nothing installs updates yet. This type exists so that the checks an installer
/// must make are written and tested first: a manifest is only accepted with a
/// valid signature from a key compiled into the app, and a package only from the
/// official release assets with a matching SHA-256.
/// </summary>
public sealed class UpdateManifest
{
    public required UpdateChannel Channel { get; init; }
    public required string Version { get; init; }
    public required IReadOnlyList<UpdatePackage> Packages { get; init; }

    /// <summary>
    /// Keys allowed to sign update manifests, as DER SubjectPublicKeyInfo (ECDSA
    /// P-256). Empty: no update signing key has been established, so no manifest
    /// can be trusted and automatic installation is impossible.
    /// </summary>
    public static readonly IReadOnlyList<byte[]> TrustedKeys = Array.Empty<byte[]>();

    public static bool AutomaticInstallationPossible => TrustedKeys.Count > 0;

    /// <summary>
    /// Verifies the signature over the exact manifest bytes, then parses and checks
    /// the manifest. Verification comes first: unsigned or wrongly signed data is
    /// never interpreted.
    /// </summary>
    public static (UpdateManifest? Manifest, ManifestFailure? Failure) Verified(
        byte[] manifest, byte[] signatureDer, IReadOnlyList<byte[]> trustedKeys, UpdateChannel channel, string current)
    {
        if (trustedKeys.Count == 0) return (null, ManifestFailure.NoTrustedKey);
        if (!trustedKeys.Any(key => IsValid(signatureDer, manifest, key))) return (null, ManifestFailure.BadSignature);

        UpdateManifest parsed;
        int schema;
        try
        {
            using var document = JsonDocument.Parse(manifest);
            var root = document.RootElement;
            schema = root.GetProperty("schema").GetInt32();
            var parsedChannel = UpdateCheck.ParseChannel(root.GetProperty("channel").GetString());
            if (parsedChannel is null) return (null, ManifestFailure.Malformed);
            parsed = new UpdateManifest
            {
                Channel = parsedChannel.Value,
                Version = root.GetProperty("version").GetString() ?? string.Empty,
                Packages = root.GetProperty("packages").EnumerateArray().Select(p => new UpdatePackage(
                    p.GetProperty("platform").GetString() ?? string.Empty,
                    p.GetProperty("arch").GetString() ?? string.Empty,
                    p.GetProperty("minOS").GetString() ?? string.Empty,
                    p.GetProperty("url").GetString() ?? string.Empty,
                    p.GetProperty("sha256").GetString() ?? string.Empty,
                    p.GetProperty("size").GetInt64())).ToList(),
            };
        }
        catch (Exception exception) when (exception is JsonException or KeyNotFoundException or InvalidOperationException or FormatException)
        {
            return (null, ManifestFailure.Malformed);
        }
        var version = SemanticVersion.Parse(parsed.Version);
        var currentVersion = SemanticVersion.Parse(current);
        if (version is null || currentVersion is null) return (null, ManifestFailure.Malformed);
        if (schema != 1) return (null, ManifestFailure.UnsupportedSchema);
        if (parsed.Channel != channel) return (null, ManifestFailure.WrongChannel);
        if (currentVersion.CompareTo(version) >= 0) return (null, ManifestFailure.NotNewer);
        foreach (var package in parsed.Packages)
        {
            if (!package.Url.StartsWith(UpdateCheck.OfficialReleasePrefix + "download/", StringComparison.Ordinal)
                || package.Sha256.Length != 64 || !package.Sha256.All(Uri.IsHexDigit) || package.Size <= 0)
            {
                return (null, ManifestFailure.UntrustedLocation);
            }
        }
        return (parsed, null);
    }

    private static bool IsValid(byte[] signatureDer, byte[] data, byte[] publicKeyDer)
    {
        try
        {
            using var key = ECDsa.Create();
            key.ImportSubjectPublicKeyInfo(publicKeyDer, out _);
            return key.VerifyData(data, signatureDer, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);
        }
        catch (CryptographicException)
        {
            return false;
        }
    }

    /// <summary>The package for a system, or <c>null</c> if none fits.</summary>
    public UpdatePackage? Package(string platform, string arch, string osVersion)
    {
        static int[] Parts(string text) => text.Split('.').Select(p => int.TryParse(p, out var n) ? n : 0).ToArray();
        static bool AtLeast(string have, string need)
        {
            int[] a = Parts(have), b = Parts(need);
            for (var index = 0; index < Math.Max(a.Length, b.Length); index++)
            {
                int x = index < a.Length ? a[index] : 0, y = index < b.Length ? b[index] : 0;
                if (x != y) return x > y;
            }
            return true;
        }
        return Packages.FirstOrDefault(p => p.Platform == platform && (p.Arch == arch || p.Arch == "universal") && AtLeast(osVersion, p.MinOS));
    }

    /// <summary>Whether a downloaded file is exactly the package the manifest describes.</summary>
    public static bool Matches(UpdatePackage package, byte[] fileData) =>
        fileData.LongLength == package.Size
        && Convert.ToHexString(SHA256.HashData(fileData)).Equals(package.Sha256, StringComparison.OrdinalIgnoreCase);
}

/// <summary>
/// Asks GitHub which releases of Baddel exist. This is the only network request
/// the apps can make, and it happens only when the user asks for it or has turned
/// on the daily check. It is one anonymous GET of the public release list and
/// sends nothing about the user or their text. Nothing is downloaded or installed.
/// </summary>
public static class UpdateChecker
{
    public static async Task<UpdateCheckResult?> CheckAsync(string current, UpdateChannel channel)
    {
        try
        {
            using var handler = new HttpClientHandler { UseCookies = false, AllowAutoRedirect = false };
            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(15), MaxResponseContentBufferSize = 4 * 1024 * 1024 };
            using var request = new HttpRequestMessage(HttpMethod.Get, UpdateCheck.ReleasesApi);
            request.Headers.TryAddWithoutValidation("Accept", "application/vnd.github+json");
            request.Headers.TryAddWithoutValidation("User-Agent", "Baddel/" + current);
            using var response = await client.SendAsync(request).ConfigureAwait(false);
            if (response.StatusCode != System.Net.HttpStatusCode.OK) return null;
            return UpdateCheck.Evaluate(await response.Content.ReadAsStringAsync().ConfigureAwait(false), current, channel);
        }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException or IOException)
        {
            return null;
        }
    }
}
