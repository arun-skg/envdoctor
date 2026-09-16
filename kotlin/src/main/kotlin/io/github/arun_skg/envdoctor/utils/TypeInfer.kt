package io.github.arun_skg.envdoctor.utils

import io.github.arun_skg.envdoctor.models.VariableType

/**
 * Infers the basic type of a variable value. Ordering matters: a value like
 * "1" is an integer, "1.5" is a float, "true" is a boolean, and a URL wins
 * over generic string. Anything unparseable or empty is "string" or "unknown".
 */
object TypeInfer {
    private val integerRe = Regex("^-?[0-9]+$")
    private val floatRe = Regex("^-?[0-9]+\\.[0-9]+([eE][+-]?[0-9]+)?$")
    private val booleanRe = Regex("^(true|false|TRUE|FALSE)$")
    private val urlRe = Regex("^https?://\\S+$", RegexOption.IGNORE_CASE)

    fun inferType(value: String?): VariableType {
        if (value == null) return VariableType.UNKNOWN
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return VariableType.UNKNOWN
        if (integerRe.matches(trimmed)) return VariableType.INTEGER
        if (floatRe.matches(trimmed)) return VariableType.FLOAT
        if (booleanRe.matches(trimmed)) return VariableType.BOOLEAN
        if (urlRe.matches(trimmed)) return VariableType.URL
        if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
            try {
                JsonParser.parse(trimmed)
                return VariableType.JSON
            } catch (_: Exception) {
                // fall through to string
            }
        }
        return VariableType.STRING
    }
}
