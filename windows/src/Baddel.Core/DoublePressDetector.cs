namespace Baddel.Core;

public enum PressAction
{
    None,
    Armed,
    Single,
    Double,
    SingleThenArmed,
}

/// <summary>
/// Decides between a single and a double shortcut press without touching text
/// until the decision is made. Mirrors <c>DoublePressDetector.swift</c>.
/// </summary>
public sealed class DoublePressDetector(int windowMs = 300)
{
    private int? pendingSince;
    private bool released = true;

    public int WindowMs { get; } = windowMs;

    /// <summary>Identifies the timer that belongs to the current pending press.</summary>
    public int Generation { get; private set; }

    public PressAction Press(int timeMs, bool isRepeat)
    {
        // A press without a release in between is a held key.
        if (isRepeat || !released) return PressAction.None;
        released = false;
        if (pendingSince is int first)
        {
            if (timeMs - first <= WindowMs)
            {
                pendingSince = null;
                Generation++;
                return PressAction.Double;
            }
            pendingSince = timeMs;
            Generation++;
            return PressAction.SingleThenArmed;
        }
        pendingSince = timeMs;
        Generation++;
        return PressAction.Armed;
    }

    public void Release() => released = true;

    public PressAction Timeout(int generation)
    {
        if (pendingSince is null || generation != Generation) return PressAction.None;
        pendingSince = null;
        return PressAction.Single;
    }
}
