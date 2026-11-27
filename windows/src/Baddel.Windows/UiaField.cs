using System;
using System.Drawing;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Automation.Text;
using Baddel.Core;

namespace Baddel.Windows;

/// <summary>
/// A focused text element reached through UI Automation. Text and selection come
/// from the Text pattern; writes go through the Value pattern, or, when enabled
/// and the Value pattern is unavailable, through a verified paste.
/// </summary>
public sealed class UiaField : IEditableField, IAnchoredField
{
    private readonly AutomationElement element;
    private readonly ValuePattern? value;
    private readonly TextPattern? text;
    private readonly ClipboardPaster? paster;
    private readonly int[] runtimeId;

    public string ControlTypeName { get; }
    public string LastWriteStrategy { get; private set; } = "none";

    public UiaField(AutomationElement element, ClipboardPaster? paster)
    {
        this.element = element;
        this.paster = paster;
        runtimeId = element.GetRuntimeId();
        ControlTypeName = element.Current.ControlType.ProgrammaticName;
        value = element.TryGetCurrentPattern(ValuePattern.Pattern, out var valuePattern) ? (ValuePattern)valuePattern : null;
        text = element.TryGetCurrentPattern(TextPattern.Pattern, out var textPattern) ? (TextPattern)textPattern : null;
    }

    public bool IsSameField(IEditableField other) =>
        other is UiaField field && Automation.Compare(runtimeId, field.runtimeId);

    public bool IsSecure
    {
        get
        {
            try
            {
                return element.Current.IsPassword;
            }
            catch (Exception)
            {
                // Unknown is treated as secure.
                return true;
            }
        }
    }

    private bool ValueWritable => value is not null && !value.Current.IsReadOnly;

    public bool IsEditableText
    {
        get
        {
            try
            {
                var current = element.Current;
                var type = current.ControlType;
                var isTextControl = type == ControlType.Edit || type == ControlType.Document || type == ControlType.ComboBox;
                if (!isTextControl || !current.IsEnabled || text is null) return false;
                return ValueWritable || (value is null && paster is not null);
            }
            catch (Exception)
            {
                return false;
            }
        }
    }

    public bool HasKeyboardFocus
    {
        get
        {
            try
            {
                var focused = AutomationElement.FocusedElement;
                return focused is not null && Automation.Compare(focused.GetRuntimeId(), runtimeId);
            }
            catch (Exception)
            {
                return false;
            }
        }
    }

    public string ReadText()
    {
        if (IsSecure) throw new RejectionException(Rejection.SecureField);
        try
        {
            if (value is not null) return value.Current.Value ?? string.Empty;
            if (text is null) throw new RejectionException(Rejection.ReadFailed);
            var content = text.DocumentRange.GetText(CorrectionEngine.MaxFieldLength + 1);
            if (content.Length > CorrectionEngine.MaxFieldLength) throw new RejectionException(Rejection.FieldTooLarge);
            return content;
        }
        catch (RejectionException)
        {
            throw;
        }
        catch (Exception)
        {
            throw new RejectionException(Rejection.ReadFailed);
        }
    }

    /// <summary>
    /// The selection as UTF-16 offsets into <see cref="ReadText"/>. The offsets are
    /// derived from the text before the selection and are only returned when that
    /// text and the selected text line up exactly with the field's text.
    /// </summary>
    public Utf16Range ReadSelection()
    {
        if (text is null) throw new RejectionException(Rejection.ReadFailed);
        try
        {
            var selections = text.GetSelection();
            if (selections.Length != 1) throw new RejectionException(Rejection.ReadFailed);
            var selection = selections[0];
            var before = text.DocumentRange.Clone();
            before.MoveEndpointByRange(TextPatternRangeEndpoint.End, selection, TextPatternRangeEndpoint.Start);
            var prefix = before.GetText(-1);
            var selected = selection.GetText(-1);
            var full = ReadText();
            if (prefix.Length + selected.Length > full.Length
                || !full.StartsWith(prefix, StringComparison.Ordinal)
                || string.CompareOrdinal(full, prefix.Length, selected, 0, selected.Length) != 0)
            {
                throw new RejectionException(Rejection.ReadFailed);
            }
            return new Utf16Range(prefix.Length, selected.Length);
        }
        catch (RejectionException)
        {
            throw;
        }
        catch (Exception)
        {
            throw new RejectionException(Rejection.ReadFailed);
        }
    }

    /// <summary>A text range covering exactly <paramref name="range"/>, verified against <paramref name="expected"/>.</summary>
    private TextPatternRange? RangeFor(Utf16Range range, string expected)
    {
        if (text is null) return null;
        try
        {
            var result = text.DocumentRange.Clone();
            result.MoveEndpointByRange(TextPatternRangeEndpoint.End, result, TextPatternRangeEndpoint.Start);
            result.MoveEndpointByUnit(TextPatternRangeEndpoint.End, TextUnit.Character, range.End);
            result.MoveEndpointByUnit(TextPatternRangeEndpoint.Start, TextUnit.Character, range.Location);
            return result.GetText(-1) == expected ? result : null;
        }
        catch (Exception)
        {
            return null;
        }
    }

    public void SetSelection(Utf16Range range)
    {
        try
        {
            var full = ReadText();
            if (!CorrectionPlanner.IsValid(range, full)) return;
            RangeFor(range, full.Substring(range.Location, range.Length))?.Select();
        }
        catch (Exception)
        {
        }
    }

    public void Replace(Utf16Range range, string snapshot, string replacement)
    {
        if (IsSecure) throw new RejectionException(Rejection.SecureField);
        var expected = CorrectionEngine.ValidatedReplacement(range, snapshot, ReadText(), replacement);
        var old = snapshot.Substring(range.Location, range.Length);

        bool Settled(int timeoutMs)
        {
            var deadline = Environment.TickCount64 + timeoutMs;
            while (true)
            {
                var now = SafeRead();
                if (now == expected) return true;
                if (now != snapshot) throw new RejectionException(Rejection.VerificationFailed);
                if (Environment.TickCount64 >= deadline) return false;
                Thread.Sleep(15);
            }
        }

        // The Value pattern replaces the whole text, and controls differ in how they
        // report line breaks afterwards, so it is only used for text without any.
        // Multi-line content needs the paste fallback or is refused untouched.
        var singleLine = snapshot.AsSpan().IndexOfAny('\r', '\n') < 0 && replacement.AsSpan().IndexOfAny('\r', '\n') < 0;
        if (ValueWritable && singleLine)
        {
            try
            {
                value!.SetValue(expected);
            }
            catch (Exception)
            {
                throw new RejectionException(Rejection.WriteFailed);
            }
            try
            {
                if (Settled(300))
                {
                    LastWriteStrategy = "valuePattern";
                    return;
                }
            }
            catch (RejectionException)
            {
                // The control holds something other than what was written: put the
                // snapshot back, and only report a clean refusal if that worked.
                try
                {
                    value!.SetValue(snapshot);
                }
                catch (Exception)
                {
                }
                if (SafeRead() == snapshot) throw new RejectionException(Rejection.WriteFailed);
                throw;
            }
            throw new RejectionException(Rejection.WriteFailed);
        }

        if (paster is not null && RangeFor(range, old) is { } target)
        {
            try
            {
                target.Select();
            }
            catch (Exception)
            {
                throw new RejectionException(Rejection.WriteFailed);
            }
            var pasted = false;
            paster.Paste(
                replacement,
                // Checked right before Ctrl+V is sent: this element must still have
                // keyboard focus and hold the verified selection of unchanged text.
                confirm: () => HasKeyboardFocus && SafeRead() == snapshot && SafeSelection() == range,
                wait: () => pasted = Settled(700));
            if (pasted)
            {
                LastWriteStrategy = "paste";
                return;
            }
        }
        throw new RejectionException(Rejection.WriteFailed);
    }

    private string? SafeRead()
    {
        try
        {
            return ReadText();
        }
        catch (RejectionException)
        {
            return null;
        }
    }

    private Utf16Range? SafeSelection()
    {
        try
        {
            return ReadSelection();
        }
        catch (RejectionException)
        {
            return null;
        }
    }

    public Rectangle? TextAnchor()
    {
        try
        {
            var selections = text?.GetSelection();
            if (selections is null || selections.Length == 0) return null;
            var rectangles = selections[0].GetBoundingRectangles();
            if (rectangles.Length == 0) return null;
            return ToRectangle(rectangles[^1]);
        }
        catch (Exception)
        {
            return null;
        }
    }

    public Rectangle? FieldBounds()
    {
        try
        {
            return ToRectangle(element.Current.BoundingRectangle);
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static Rectangle? ToRectangle(System.Windows.Rect rect)
    {
        if (rect.IsEmpty || double.IsInfinity(rect.Width) || double.IsNaN(rect.X) || rect.Height <= 0) return null;
        return new Rectangle((int)rect.X, (int)rect.Y, Math.Max((int)rect.Width, 1), (int)rect.Height);
    }
}
