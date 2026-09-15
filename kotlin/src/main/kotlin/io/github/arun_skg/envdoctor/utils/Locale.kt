package io.github.arun_skg.envdoctor.utils

/**
 * A comparator matching JavaScript's `String.prototype.localeCompare` for the
 * character set used in environment-variable names (`[A-Za-z0-9_]`).
 *
 * The TypeScript reference sorts generated output with `localeCompare`, which
 * is a Unicode collation (punctuation < digits < letters, case-insensitive
 * with a lowercase-before-uppercase tiebreak) — not byte order.
 */
object Locale {
    private fun primary(c: Char): Int = when {
        c in '0'..'9' -> 1000 + c.code
        c.isAsciiLetter() -> 2000 + c.uppercaseChar().code
        else -> c.code
    }

    private fun caseWeight(c: Char): Int = if (c in 'a'..'z') 0 else 1

    private fun Char.isAsciiLetter(): Boolean = this in 'a'..'z' || this in 'A'..'Z'

    /** Compare two strings the way JS `a.localeCompare(b)` does for env-var names. */
    fun localeCompare(a: String, b: String): Int {
        val len = minOf(a.length, b.length)
        // Level 1: primary weights across all positions.
        for (i in 0 until len) {
            val cmp = primary(a[i]) - primary(b[i])
            if (cmp != 0) return cmp
        }
        val lenCmp = a.length - b.length
        if (lenCmp != 0) return lenCmp

        // Level 2: case (only reached when primaries are all equal).
        for (i in 0 until len) {
            val cmp = caseWeight(a[i]) - caseWeight(b[i])
            if (cmp != 0) return cmp
        }
        return 0
    }

    fun localeSort(values: MutableList<String>) {
        values.sortWith(::localeCompare)
    }
}
