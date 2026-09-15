package io.github.arun_skg.envdoctor.utils

/**
 * A small hand-rolled TOML parser covering the subset envdoctor's config
 * uses: comments, bare/quoted keys, `key = value` pairs with basic strings
 * (single-line, escapes), integers, booleans, arrays (possibly spanning
 * lines, possibly of inline tables), inline tables, and standard table
 * headers (`[table]`, `[table.sub]`).
 *
 * Produces plain values: `JsonObject` (LinkedHashMap), `List<Any?>`, `String`,
 * `Boolean`, and numbers as `Long`.
 */
object TomlParser {
    fun parse(text: String): JsonObject = Parser(text).parse()

    private class Parser(val text: String) {
        private var i = 0
        private val n = text.length

        private val root = JsonObject()
        private var current: JsonObject = root

        private fun error(msg: String): Nothing = throw IllegalArgumentException("TOML: $msg near offset $i")

        private fun skipWs(includeNewlines: Boolean) {
            while (i < n) {
                val c = text[i]
                if (c == ' ' || c == '\t' || c == '\r' || (includeNewlines && c == '\n')) i++
                else if (c == '#') {
                    while (i < n && text[i] != '\n') i++
                } else break
            }
        }

        private fun skipInlineWs() {
            while (i < n && (text[i] == ' ' || text[i] == '\t' || text[i] == '\r')) i++
        }

        private fun parseBasicString(): String {
            if (text[i] != '"') error("expected string")
            i++
            val sb = StringBuilder()
            while (true) {
                if (i >= n) error("unterminated string")
                when (val c = text[i++]) {
                    '"' -> return sb.toString()
                    '\\' -> {
                        if (i >= n) error("unterminated escape")
                        when (val e = text[i++]) {
                            '"' -> sb.append('"')
                            '\\' -> sb.append('\\')
                            'n' -> sb.append('\n')
                            't' -> sb.append('\t')
                            'r' -> sb.append('\r')
                            'b' -> sb.append('\b')
                            'u' -> {
                                if (i + 4 > n) error("bad \\u escape")
                                sb.append(text.substring(i, i + 4).toInt(16).toChar())
                                i += 4
                            }
                            'U' -> {
                                if (i + 8 > n) error("bad \\U escape")
                                sb.append(text.substring(i, i + 8).toInt(16).toChar())
                                i += 8
                            }
                            else -> error("unknown escape '\\$e'")
                        }
                    }
                    '\n' -> error("newline in string")
                    else -> sb.append(c)
                }
            }
        }

        private fun parseLiteralString(): String {
            if (text[i] != '\'') error("expected literal string")
            i++
            val sb = StringBuilder()
            while (true) {
                if (i >= n) error("unterminated string")
                val c = text[i++]
                if (c == '\'') return sb.toString()
                if (c == '\n') error("newline in string")
                sb.append(c)
            }
        }

        private fun parseKey(): String {
            skipInlineWs()
            return when {
                i < n && text[i] == '"' -> parseBasicString()
                i < n && text[i] == '\'' -> parseLiteralString()
                else -> {
                    val start = i
                    while (i < n && (text[i].isLetterOrDigit() || text[i] == '_' || text[i] == '-')) i++
                    if (i == start) error("expected key")
                    text.substring(start, i)
                }
            }
        }

        private fun parseArray(): List<Any?> {
            i++ // consume '['
            val list = mutableListOf<Any?>()
            while (true) {
                skipWs(includeNewlines = true)
                if (i < n && text[i] == ']') {
                    i++
                    return list
                }
                if (i >= n) error("unterminated array")
                list.add(parseValue())
                skipWs(includeNewlines = true)
                when {
                    i < n && text[i] == ',' -> i++
                    i < n && text[i] == ']' -> { i++; return list }
                    else -> error("expected ',' or ']' in array")
                }
            }
        }

        private fun parseInlineTable(): JsonObject {
            i++ // consume '{'
            val obj = JsonObject()
            skipWs(includeNewlines = false)
            if (i < n && text[i] == '}') {
                i++
                return obj
            }
            while (true) {
                skipWs(includeNewlines = false)
                val key = parseKey()
                skipInlineWs()
                if (i >= n || text[i] != '=') error("expected '=' in inline table")
                i++
                skipInlineWs()
                obj[key] = parseValue()
                skipWs(includeNewlines = false)
                when {
                    i < n && text[i] == ',' -> i++
                    i < n && text[i] == '}' -> { i++; return obj }
                    else -> error("expected ',' or '}' in inline table")
                }
            }
        }

        private fun parseValue(): Any? {
            skipInlineWs()
            if (i >= n) error("expected value")
            return when (val c = text[i]) {
                '"' -> parseBasicString()
                '\'' -> parseLiteralString()
                '[' -> parseArray()
                '{' -> parseInlineTable()
                't', 'f' -> {
                    if (text.startsWith("true", i)) { i += 4; true }
                    else if (text.startsWith("false", i)) { i += 5; false }
                    else error("invalid value")
                }
                else -> {
                    val start = i
                    while (i < n && text[i] != ',' && text[i] != ']' && text[i] != '}' &&
                        text[i] != '\n' && text[i] != '#'
                    ) i++
                    val token = text.substring(start, i).trim()
                    if (token.isEmpty()) error("expected value")
                    token.replace("_", "").toLongOrNull() ?: token
                }
            }
        }

        fun parse(): JsonObject {
            while (i < n) {
                skipWs(includeNewlines = true)
                if (i >= n) break
                if (text[i] == '[') {
                    // Table header (standard tables only).
                    i++
                    if (i < n && text[i] == '[') error("array-of-tables headers are not supported")
                    val path = mutableListOf<String>()
                    while (true) {
                        skipWs(includeNewlines = false)
                        path.add(parseKey())
                        skipWs(includeNewlines = false)
                        when {
                            i < n && text[i] == '.' -> i++
                            i < n && text[i] == ']' -> { i++; break }
                            else -> error("expected '.' or ']' in table header")
                        }
                    }
                    current = root
                    for (part in path) {
                        @Suppress("UNCHECKED_CAST")
                        current = current.getOrPut(part) { JsonObject() } as? JsonObject
                            ?: error("key '$part' is not a table")
                    }
                } else {
                    val key = parseKey()
                    skipInlineWs()
                    if (i >= n || text[i] != '=') error("expected '=' after key '$key'")
                    i++
                    val value = parseValue()
                    current[key] = value
                }
            }
            return root
        }
    }
}
