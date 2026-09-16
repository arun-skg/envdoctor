package io.github.arun_skg.envdoctor.utils

/**
 * A small JSON parser producing plain Kotlin values: `JsonObject`
 * (LinkedHashMap), `List<Any?>`, `String`, `Boolean`, `null`, and numbers as
 * `Long` (when integral) or `Double`. Used for config files, package.json,
 * baseline files, and runtime snapshot JSON.
 */
object JsonParser {
    fun parse(text: String): Any? {
        val p = Parser(text)
        val value = p.parseValue()
        p.skipWs()
        if (!p.atEnd()) throw IllegalArgumentException("Unexpected trailing content at offset ${p.pos}")
        return value
    }

    private class Parser(val text: String) {
        var pos: Int = 0

        fun atEnd(): Boolean = pos >= text.length

        fun skipWs() {
            while (pos < text.length && (text[pos] == ' ' || text[pos] == '\t' || text[pos] == '\n' || text[pos] == '\r')) pos++
        }

        fun parseValue(): Any? {
            skipWs()
            if (atEnd()) throw IllegalArgumentException("Unexpected end of JSON")
            return when (val c = text[pos]) {
                '{' -> parseObject()
                '[' -> parseArray()
                '"' -> parseString()
                't' -> { expect("true"); true }
                'f' -> { expect("false"); false }
                'n' -> { expect("null"); null }
                else -> parseNumber()
            }
        }

        private fun expect(literal: String) {
            if (!text.regionMatches(pos, literal, 0, literal.length)) {
                throw IllegalArgumentException("Invalid JSON literal at offset $pos")
            }
            pos += literal.length
        }

        private fun parseObject(): JsonObject {
            pos++ // '{'
            val obj = JsonObject()
            skipWs()
            if (pos < text.length && text[pos] == '}') {
                pos++
                return obj
            }
            while (true) {
                skipWs()
                val key = parseString()
                skipWs()
                if (pos >= text.length || text[pos] != ':') throw IllegalArgumentException("Expected ':' at offset $pos")
                pos++
                obj[key] = parseValue()
                skipWs()
                when {
                    pos < text.length && text[pos] == ',' -> pos++
                    pos < text.length && text[pos] == '}' -> { pos++; return obj }
                    else -> throw IllegalArgumentException("Expected ',' or '}' at offset $pos")
                }
            }
        }

        private fun parseArray(): List<Any?> {
            pos++ // '['
            val list = mutableListOf<Any?>()
            skipWs()
            if (pos < text.length && text[pos] == ']') {
                pos++
                return list
            }
            while (true) {
                list.add(parseValue())
                skipWs()
                when {
                    pos < text.length && text[pos] == ',' -> pos++
                    pos < text.length && text[pos] == ']' -> { pos++; return list }
                    else -> throw IllegalArgumentException("Expected ',' or ']' at offset $pos")
                }
            }
        }

        private fun parseString(): String {
            if (pos >= text.length || text[pos] != '"') throw IllegalArgumentException("Expected string at offset $pos")
            pos++
            val sb = StringBuilder()
            while (true) {
                if (pos >= text.length) throw IllegalArgumentException("Unterminated string")
                when (val c = text[pos++]) {
                    '"' -> return sb.toString()
                    '\\' -> {
                        if (pos >= text.length) throw IllegalArgumentException("Unterminated escape")
                        when (val e = text[pos++]) {
                            '"' -> sb.append('"')
                            '\\' -> sb.append('\\')
                            '/' -> sb.append('/')
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'u' -> {
                                if (pos + 4 > text.length) throw IllegalArgumentException("Bad \\u escape")
                                sb.append(text.substring(pos, pos + 4).toInt(16).toChar())
                                pos += 4
                            }
                            else -> throw IllegalArgumentException("Bad escape '\\$e'")
                        }
                    }
                    else -> sb.append(c)
                }
            }
        }

        private fun parseNumber(): Any {
            val start = pos
            if (pos < text.length && (text[pos] == '-' || text[pos] == '+')) pos++
            while (pos < text.length && (text[pos].isDigit() || text[pos] == '.' || text[pos] == 'e' || text[pos] == 'E' || text[pos] == '-' || text[pos] == '+')) pos++
            val s = text.substring(start, pos)
            if (s.isEmpty()) throw IllegalArgumentException("Invalid JSON value at offset $start")
            return s.toLongOrNull() ?: s.toDoubleOrNull()
                ?: throw IllegalArgumentException("Invalid number '$s' at offset $start")
        }
    }
}
