using System;
using System.IO;
using Baddel.Linux;
using Xunit;

namespace Baddel.Linux.Tests;

public class LinuxSupportTests
{
    [Fact]
    public void StartAtLoginWritesOnlyItsOwnFile()
    {
        var directory = Directory.CreateTempSubdirectory("baddel-autostart-test");
        try
        {
            var file = Path.Combine(directory.FullName, "autostart", Autostart.FileName);
            var program = Path.Combine(directory.FullName, "baddel");
            File.WriteAllText(program, "");

            Assert.Equal(Autostart.State.Off, Autostart.Read(file));
            Assert.Null(Autostart.Disable(file));
            Assert.False(File.Exists(file));

            Assert.Null(Autostart.Enable(program, file));
            Assert.Equal(Autostart.State.On, Autostart.Read(file));
            var entry = File.ReadAllText(file);
            Assert.Contains("[Desktop Entry]\nType=Application\n", entry);
            Assert.Contains($"Exec={program}\n", entry);
            Assert.Contains($"TryExec={program}\n", entry);

            // Enabling twice is harmless, and a removed program is reported, not started.
            Assert.Null(Autostart.Enable(program, file));
            File.Delete(program);
            Assert.Equal(Autostart.State.Stale, Autostart.Read(file));
            Assert.Null(Autostart.Disable(file));
            Assert.False(File.Exists(file));

            // A file somebody else put there is neither replaced nor removed.
            File.WriteAllText(file, "[Desktop Entry]\nType=Application\nExec=/usr/bin/true\n");
            Assert.Equal(Autostart.State.Foreign, Autostart.Read(file));
            Assert.Equal("anotherFileIsInTheWay", Autostart.Enable(program, file));
            Assert.Equal("notBaddelsFile", Autostart.Disable(file));
            Assert.Equal("[Desktop Entry]\nType=Application\nExec=/usr/bin/true\n", File.ReadAllText(file));

            // A path with a space is quoted for Exec and left plain for TryExec.
            Assert.Contains("Exec=\"/opt/my apps/baddel\"\nTryExec=/opt/my apps/baddel\n", Autostart.Entry("/opt/my apps/baddel"));
        }
        finally
        {
            directory.Delete(recursive: true);
        }
    }

    /// <summary>
    /// libatspi sends inserted text on as a C string. Without a terminating NUL the
    /// application also receives whatever follows the array in memory. A .NET byte
    /// array is padded with zero bytes up to a multiple of eight, so only text whose
    /// UTF-8 length is a multiple of eight was exposed: every four-letter Arabic
    /// word, for one.
    /// </summary>
    [Fact]
    public void TextForNativeCallsEndsWithOneNul()
    {
        foreach (var text in new[] { "اريد", "اروح", "عليكم", "hello", "اريد اروح", "😀👍🏽", "cafe\u0301", "a\u200fb", "line\nline" })
        {
            var bytes = NativeText.NulTerminatedUtf8(text)!;
            var utf8 = System.Text.Encoding.UTF8.GetBytes(text);
            Assert.Equal(utf8.Length + 1, bytes.Length);
            Assert.Equal(0, bytes[^1]);
            Assert.Equal(utf8, bytes[..^1]);
            Assert.DoesNotContain((byte)0, utf8);
        }
        // The reported words are exactly the exposed case.
        Assert.Equal(8, System.Text.Encoding.UTF8.GetByteCount("اريد"));
        Assert.Equal(8, System.Text.Encoding.UTF8.GetByteCount("اروح"));
        // Text that cannot be a C string, or has no UTF-8 form, is refused instead of being cut or altered.
        Assert.Null(NativeText.NulTerminatedUtf8("a\0b"));
        Assert.Null(NativeText.NulTerminatedUtf8("a\ud83d"));
        Assert.Null(NativeText.NulTerminatedUtf8("\udc00b"));
    }

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
