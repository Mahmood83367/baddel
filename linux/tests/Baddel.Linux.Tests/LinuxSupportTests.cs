using System;
using System.IO;
using Baddel.Linux;
using Xunit;

namespace Baddel.Linux.Tests;

public class LinuxSupportTests
{
    [Fact]
    public void CharacterOffsetsConvertToUtf16AndBack()
    {
        const string text = "😀 ugd;l";
        Assert.Equal(0, TextOffsets.ToUtf16(text, 0));
        Assert.Equal(2, TextOffsets.ToUtf16(text, 1));
        Assert.Equal(8, TextOffsets.ToUtf16(text, 7));
        Assert.Equal(-1, TextOffsets.ToUtf16(text, 8));
        Assert.Equal(-1, TextOffsets.ToUtf16(text, -1));
        Assert.Equal(7, TextOffsets.ToCharacters(text, 8));
        Assert.Equal(1, TextOffsets.ToCharacters(text, 2));
        // An index inside the emoji's surrogate pair is refused.
        Assert.Equal(-1, TextOffsets.ToCharacters(text, 1));
        Assert.Equal(-1, TextOffsets.ToCharacters(text, 9));
        Assert.Equal(5, TextOffsets.ToUtf16("عليكم", 5));
    }

    [Fact]
    public void SessionGroupsKeepLayoutAndVariantByPosition()
    {
        var groups = XkbGroupSwitcher.Parse("rules:      evdev\nmodel:      pc105\nlayout:     us,ara,ara\nvariant:    ,,digits\n");
        Assert.Equal(new[] { new XkbGroup("us", ""), new XkbGroup("ara", ""), new XkbGroup("ara", "digits") }, groups);
        // No variant line: every group has the default variant.
        Assert.Equal(new[] { new XkbGroup("us", ""), new XkbGroup("ara", "") }, XkbGroupSwitcher.Parse("layout:     us,ara\n"));
        // Fewer variants than layouts.
        Assert.Equal(new[] { new XkbGroup("us", "dvorak"), new XkbGroup("ara", "") }, XkbGroupSwitcher.Parse("layout: us,ara\nvariant: dvorak\n"));
        Assert.Empty(XkbGroupSwitcher.Parse(""));
    }

    [Fact]
    public void VariantsAreManualOrTakenFromTheSession()
    {
        var session = new[] { new XkbGroup("us", ""), new XkbGroup("ara", "digits"), new XkbGroup("ara", "") };

        // Not configured: the variant of the session's first group with that layout.
        var automatic = new LinuxSettings().Resolve(session);
        Assert.Equal(new XkbGroup("us", ""), automatic.Latin);
        Assert.Equal(new XkbGroup("ara", "digits"), automatic.Arabic);

        // Configured: exactly what was asked for, on both sides.
        var manual = new LinuxSettings { LatinXkbVariant = "dvorak", ArabicXkbVariant = "" }.Resolve(session);
        Assert.Equal(new XkbGroup("us", "dvorak"), manual.Latin);
        Assert.Equal(new XkbGroup("ara", ""), manual.Arabic);

        // No session information (for example Wayland): the default variant.
        var none = new LinuxSettings().Resolve(Array.Empty<XkbGroup>());
        Assert.Equal(new XkbGroup("ara", ""), none.Arabic);
    }

    [Fact]
    public void OnlyARealOwnerOnlyDirectoryIsPrivate()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS()) return;
        var root = Path.Combine(Path.GetTempPath(), "baddel-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            const UnixFileMode ownerOnly = UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute;
            var good = Path.Combine(root, "private");
            Directory.CreateDirectory(good, ownerOnly);
            Assert.True(TriggerChannel.IsPrivateDirectory(good));

            var shared = Path.Combine(root, "shared");
            Directory.CreateDirectory(shared);
            File.SetUnixFileMode(shared, ownerOnly | UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
            Assert.False(TriggerChannel.IsPrivateDirectory(shared));

            var worldWritable = Path.Combine(root, "world");
            Directory.CreateDirectory(worldWritable);
            File.SetUnixFileMode(worldWritable, (UnixFileMode)0b111_111_111);
            Assert.False(TriggerChannel.IsPrivateDirectory(worldWritable));

            // A symbolic link is refused even when it points at a private directory.
            var link = Path.Combine(root, "link");
            Directory.CreateSymbolicLink(link, good);
            Assert.False(TriggerChannel.IsPrivateDirectory(link));

            var file = Path.Combine(root, "file");
            File.WriteAllText(file, "");
            Assert.False(TriggerChannel.IsPrivateDirectory(file));
            Assert.False(TriggerChannel.IsPrivateDirectory(Path.Combine(root, "missing")));
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }
}
