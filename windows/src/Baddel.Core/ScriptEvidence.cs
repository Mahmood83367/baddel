namespace Baddel.Core;

/// <summary>Evidence counts; see <c>ScriptEvidence.swift</c> and docs/CORRECTION_RULES.md.</summary>
public struct EvidenceCounts
{
    public int StrongLatin;
    public int StrongArabic;
    public int WeakLatin;
    public int WeakArabic;

    public static EvidenceCounts operator +(EvidenceCounts a, EvidenceCounts b) => new()
    {
        StrongLatin = a.StrongLatin + b.StrongLatin,
        StrongArabic = a.StrongArabic + b.StrongArabic,
        WeakLatin = a.WeakLatin + b.WeakLatin,
        WeakArabic = a.WeakArabic + b.WeakArabic,
    };

    public readonly Script? UniformScript
    {
        get
        {
            if (StrongLatin > 0 || StrongArabic > 0)
            {
                if (StrongArabic == 0) return Script.Latin;
                if (StrongLatin == 0) return Script.Arabic;
                return null;
            }
            if (WeakLatin > 0 && WeakArabic == 0) return Script.Latin;
            if (WeakArabic > 0 && WeakLatin == 0) return Script.Arabic;
            return null;
        }
    }

    public readonly Script? DominantScript
    {
        get
        {
            if (StrongLatin != StrongArabic) return StrongLatin > StrongArabic ? Script.Latin : Script.Arabic;
            if (WeakLatin != WeakArabic) return WeakLatin > WeakArabic ? Script.Latin : Script.Arabic;
            return null;
        }
    }
}

public sealed class ScriptEvidence
{
    private readonly HashSet<char> latinOnly;
    private readonly HashSet<char> arabicOnly;

    public ScriptEvidence(LayoutPair pair)
    {
        static HashSet<char> Units(KeyboardLayout layout)
        {
            var set = new HashSet<char>();
            foreach (var key in layout.Keys)
            {
                set.UnionWith(key.Base);
                set.UnionWith(key.Shift);
            }
            return set;
        }
        var latin = Units(pair.Latin);
        var arabic = Units(pair.Arabic);
        latinOnly = new HashSet<char>(latin.Except(arabic));
        arabicOnly = new HashSet<char>(arabic.Except(latin));
    }

    public static bool IsArabicLetter(char unit) =>
        unit is (>= 'ء' and <= 'ْ') or (>= 'ٮ' and <= 'ۓ')
            or (>= 'ﭐ' and <= '﷿') or (>= 'ﹰ' and <= 'ﻼ');

    public static bool IsLatinLetter(char unit) =>
        unit is (>= 'A' and <= 'Z') or (>= 'a' and <= 'z')
        || (unit >= 'À' && unit <= 'ɏ' && unit != '×' && unit != '÷');

    public EvidenceCounts Count(ReadOnlySpan<char> units)
    {
        var counts = new EvidenceCounts();
        foreach (var unit in units)
        {
            if (IsArabicLetter(unit)) counts.StrongArabic++;
            else if (IsLatinLetter(unit)) counts.StrongLatin++;
            else if (arabicOnly.Contains(unit)) counts.WeakArabic++;
            else if (latinOnly.Contains(unit)) counts.WeakLatin++;
        }
        return counts;
    }
}
