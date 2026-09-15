package io.github.arun_skg.envdoctor.utils

import java.util.regex.Pattern

/**
 * Translate a path glob (with `**`, `*`, `?`, and `{a,b}` braces) to a regex
 * matched against a root-relative, forward-slash path.
 */
object PathGlob {
    private val cache = HashMap<String, Pattern>()

    @Synchronized
    fun toRegex(pattern: String): Pattern {
        val cached = cache[pattern]
        if (cached != null) return cached
        val converted = convert(pattern)
        val compiled = Pattern.compile(converted)
        cache[pattern] = compiled
        return compiled
    }

    fun matches(pattern: String, path: String): Boolean = toRegex(pattern).matcher(path).matches()

    private fun convert(pattern: String): String {
        val sb = StringBuilder("^")
        var i = 0
        while (i < pattern.length) {
            when (val c = pattern[i]) {
                '*' -> {
                    if (i + 1 < pattern.length && pattern[i + 1] == '*') {
                        // `**/`: zero or more whole segments; bare `**`: anything.
                        if (i + 2 < pattern.length && pattern[i + 2] == '/') {
                            sb.append("(?:.*/)?")
                            i += 3
                        } else {
                            sb.append(".*")
                            i += 2
                        }
                    } else {
                        sb.append("[^/]*")
                        i += 1
                    }
                }
                '?' -> {
                    sb.append("[^/]")
                    i += 1
                }
                '{' -> {
                    val close = findBraceEnd(pattern, i)
                    if (close < 0) {
                        sb.append("\\{")
                        i += 1
                    } else {
                        val inner = pattern.substring(i + 1, close)
                        val options = inner.split(',').joinToString("|") { Pattern.quote(it) }
                        sb.append("(?:").append(options).append(')')
                        i = close + 1
                    }
                }
                else -> {
                    sb.append(Pattern.quote(c.toString()))
                    i += 1
                }
            }
        }
        sb.append('$')
        return sb.toString()
    }

    private fun findBraceEnd(pattern: String, start: Int): Int {
        for (i in start + 1 until pattern.length) {
            if (pattern[i] == '}') return i
        }
        return -1
    }
}
