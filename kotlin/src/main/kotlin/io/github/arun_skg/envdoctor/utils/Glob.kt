package io.github.arun_skg.envdoctor.utils

import java.util.regex.Pattern

/**
 * A tiny glob-to-regex converter for matching variable names and file paths
 * against config patterns (`ignoreVariables: ["AWS_*"]`, environment
 * overrides, etc.). Supports `*` (within a segment), `**`, and `?`.
 */
object Glob {
    private val cache = HashMap<String, Pattern>()

    @Synchronized
    private fun globToPattern(pattern: String): Pattern {
        val cached = cache[pattern]
        if (cached != null) return cached
        val sb = StringBuilder(pattern.length * 2)
        sb.append('^')
        var i = 0
        while (i < pattern.length) {
            val c = pattern[i]
            when (c) {
                '*' -> {
                    if (i + 1 < pattern.length && pattern[i + 1] == '*') {
                        sb.append(".*")
                        i += 2
                    } else {
                        sb.append("[^/]*")
                        i += 1
                    }
                }
                '?' -> {
                    sb.append("[^/]")
                    i += 1
                }
                else -> {
                    if (".+?^\${}()|[]\\".indexOf(c) >= 0) sb.append('\\')
                    sb.append(c)
                    i += 1
                }
            }
        }
        sb.append('$')
        val compiled = Pattern.compile(sb.toString())
        cache[pattern] = compiled
        return compiled
    }

    fun matchesGlob(pattern: String, value: String): Boolean =
        globToPattern(pattern).matcher(value).matches()

    fun matchesAnyGlob(patterns: List<String>, value: String): Boolean =
        patterns.any { matchesGlob(it, value) }
}
