using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using Baddel.Core;
using Baddel.Windows;
using Xunit;

namespace Baddel.Windows.Tests;

public class WindowsSupportTests
{
    [Fact]
    public void EmbeddedLayoutsLoadAndConvert()
    {
        var store = EmbeddedLayouts.Load();
        Assert.Contains("us-english", store.Layouts.Keys);
        Assert.Contains("arabic-windows-101", store.Layouts.Keys);
        Assert.Contains("arabic-windows-102", store.Layouts.Keys);
        var pair = EmbeddedLayouts.Pair(store, null);
        Assert.Equal("arabic-windows-101", pair.Arabic.Id);
        Assert.Equal("عليكم", new LayoutConverter(pair.Latin, pair.Arabic).Convert("ugd;l"));
        Assert.Equal("hello", new LayoutConverter(pair.Arabic, pair.Latin).Convert("اثممخ"));
        // An unknown or non-Arabic choice falls back to Arabic (101).
        Assert.Equal("arabic-windows-101", EmbeddedLayouts.Pair(store, "us-english").Arabic.Id);
        Assert.Equal("arabic-windows-102", EmbeddedLayouts.Pair(store, "arabic-windows-102").Arabic.Id);
    }

    [Fact]
    public void WindowsLayoutDataMatchesTheLayoutTablesOfThisSystem()
    {
        var store = EmbeddedLayouts.Load();
        var compared = 0;
        foreach (var id in new[] { "us-english", "arabic-windows-101", "arabic-windows-102" })
        {
            var layout = store.Get(id);
            var dumped = LayoutDumper.Dump(layout.PlatformIds["windows"][0]);
            Assert.NotNull(dumped);
            Assert.Equal(
                layout.Keys.Select(k => $"{k.Code}|{k.Base}|{k.Shift}"),
                dumped!.Select(k => $"{k.Code}|{k.Base}|{k.Shift}"));
            compared++;

            // Where Windows can also translate the layout live, both methods must agree.
            var translated = LayoutDumper.DumpByTranslation(layout.PlatformIds["windows"][0]);
            if (translated is not null)
            {
                Assert.Equal(dumped.Select(k => $"{k.Code}|{k.Base}|{k.Shift}"), translated.Select(k => $"{k.Code}|{k.Base}|{k.Shift}"));
            }
        }
        Assert.Equal(3, compared);
    }

    [Fact]
    public void ArabicVariantsAreSeparateData()
    {
        var store = EmbeddedLayouts.Load();
        var first = store.Get("arabic-windows-101").Keys.Select(k => $"{k.Code}|{k.Base}|{k.Shift}").ToArray();
        var second = store.Get("arabic-windows-102").Keys.Select(k => $"{k.Code}|{k.Base}|{k.Shift}").ToArray();
        Assert.NotEqual(first, second);
        // The selected variant decides the conversion.
        foreach (var id in new[] { "arabic-windows-101", "arabic-windows-102" })
        {
            var pair = EmbeddedLayouts.Pair(store, id);
            var there = new LayoutConverter(pair.Latin, pair.Arabic);
            var back = new LayoutConverter(pair.Arabic, pair.Latin);
            foreach (var key in pair.Latin.Keys)
            {
                var converted = there.Convert(key.Base);
                if (converted != key.Base) Assert.Equal(key.Base, back.Convert(converted));
            }
        }
    }

    [Theory]
    [InlineData("Ctrl+Alt+Space", HotKeyModifiers.Control | HotKeyModifiers.Alt, Keys.Space)]
    [InlineData("ctrl + shift + F9", HotKeyModifiers.Control | HotKeyModifiers.Shift, Keys.F9)]
    [InlineData("Win+Alt+B", HotKeyModifiers.Win | HotKeyModifiers.Alt, Keys.B)]
    public void HotKeyParses(string text, HotKeyModifiers modifiers, Keys key)
    {
        Assert.True(HotKey.TryParse(text, out var parsed));
        Assert.Equal(new HotKey(modifiers, key), parsed);
        Assert.True(HotKey.TryParse(parsed.ToString(), out var again));
        Assert.Equal(parsed, again);
    }

    [Theory]
    [InlineData("")]
    [InlineData("Space")]
    [InlineData("Shift+A")]
    [InlineData("Ctrl+Alt")]
    [InlineData("Ctrl+Nope")]
    [InlineData("Ctrl+A+B")]
    public void HotKeyRejectsUnusableCombinations(string text)
    {
        Assert.False(HotKey.TryParse(text, out _));
    }

    [Fact]
    public void HotKeyFromKeyEvent()
    {
        Assert.Equal(
            new HotKey(HotKeyModifiers.Control | HotKeyModifiers.Alt, Keys.Space),
            HotKey.FromKeyEvent(Keys.Control | Keys.Alt | Keys.Space));
        Assert.False(HotKey.FromKeyEvent(Keys.Control | Keys.ControlKey).IsValid);
        Assert.False(HotKey.FromKeyEvent(Keys.Shift | Keys.A).IsValid);
        Assert.Equal("Ctrl+Alt+Space", HotKey.Default.ToString());
    }

    [Fact]
    public void SettingsRoundTripAndDefaults()
    {
        var settings = new AppSettings { Shortcut = "Ctrl+Shift+F9", DoublePressMs = 5000, PasteFallback = true };
        var parsed = AppSettings.Parse(settings.Serialize());
        Assert.Equal(new HotKey(HotKeyModifiers.Control | HotKeyModifiers.Shift, Keys.F9), parsed.HotKey);
        Assert.Equal(600, parsed.ClampedDoublePressMs);
        Assert.True(parsed.PasteFallback);

        var broken = AppSettings.Parse("{ not json");
        Assert.Equal(HotKey.Default, broken.HotKey);
        Assert.Equal(300, broken.ClampedDoublePressMs);
        Assert.True(broken.SwitchLayout);
        Assert.False(broken.PasteFallback);
        Assert.Equal(HotKey.Default, new AppSettings { Shortcut = "garbage" }.HotKey);
    }

    [Fact]
    public void PopupSitsBelowTheAnchorAndStaysOnScreen()
    {
        var work = new Rectangle(0, 0, 1920, 1040);
        var popup = new Size(160, 36);
        Assert.Equal(new Point(400, 326), PopupPlacement.Compute(popup, new Rectangle(400, 300, 60, 20), work));
        // No room below: above the anchor.
        Assert.Equal(new Point(400, 1000 - 36 - 6), PopupPlacement.Compute(popup, new Rectangle(400, 1000, 60, 30), work));
        // Clamped at the right edge.
        Assert.Equal(1920 - 160 - 4, PopupPlacement.Compute(popup, new Rectangle(1900, 300, 10, 20), work).X);
        // No coordinates, or coordinates off this screen: lower middle.
        var fallback = new Point((1920 - 160) / 2, 1040 - 36 - 96);
        Assert.Equal(fallback, PopupPlacement.Compute(popup, null, work));
        Assert.Equal(fallback, PopupPlacement.Compute(popup, new Rectangle(5000, 5000, 10, 10), work));
    }

    [Theory]
    [InlineData("Edit", true)]
    [InlineData("WindowsForms10.EDIT.app.0.141b42a_r6_ad1", true)]
    [InlineData("Button", false)]
    [InlineData("RICHEDIT50W", false)]
    public void EditClassDetection(string className, bool expected)
    {
        Assert.Equal(expected, Win32EditField.IsEditClass(className));
    }

    [Fact]
    public void RichEditClassDetection()
    {
        Assert.True(Win32EditField.IsRichEditClass("RICHEDIT50W"));
        Assert.True(Win32EditField.IsRichEditClass("WindowsForms10.RichEdit20W.app.0.1"));
        Assert.True(Win32EditField.IsRichEditClass("RichEditD2DPT"));
        Assert.False(Win32EditField.IsRichEditClass("Edit"));
    }

    [Fact]
    public void LayoutScriptFromInputLocale()
    {
        Assert.Equal(Script.Latin, InputLanguageSwitcher.ScriptOf(new IntPtr(0x04090409)));
        Assert.Equal(Script.Arabic, InputLanguageSwitcher.ScriptOf(new IntPtr(0x04010801)));
        Assert.Null(InputLanguageSwitcher.ScriptOf(new IntPtr(0x040C040C)));
    }
}
