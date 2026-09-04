namespace Envdoctor.Utils;

/// A comparator matching JavaScript's `String.prototype.localeCompare` for the
/// character set used in environment-variable names (`[A-Za-z0-9_]`).
///
/// The TypeScript reference sorts generated output with `localeCompare`, which
/// is a Unicode collation (punctuation < digits < letters, case-insensitive
/// with a lowercase-before-uppercase tiebreak) — not byte order.
public static class Locale
{
    private static int Primary(char c)
    {
        if (char.IsAsciiDigit(c))
            return 1000 + c;
        if (char.IsAsciiLetter(c))
            return 2000 + char.ToUpperInvariant(c);
        return c;
    }

    private static int CaseWeight(char c) => char.IsAsciiLetterLower(c) ? 0 : 1;

    /// Compare two strings the way JS `a.localeCompare(b)` does for env-var names.
    public static int LocaleCompare(string a, string b)
    {
        var len = Math.Min(a.Length, b.Length);
        // Level 1: primary weights across all positions.
        for (var i = 0; i < len; i++)
        {
            var cmp = Primary(a[i]).CompareTo(Primary(b[i]));
            if (cmp != 0)
                return cmp;
        }
        var lenCmp = a.Length.CompareTo(b.Length);
        if (lenCmp != 0)
            return lenCmp;

        // Level 2: case (only reached when primaries are all equal).
        for (var i = 0; i < len; i++)
        {
            var cmp = CaseWeight(a[i]).CompareTo(CaseWeight(b[i]));
            if (cmp != 0)
                return cmp;
        }
        return 0;
    }

    public static void LocaleSort(List<string> values) => values.Sort(LocaleCompare);
}
