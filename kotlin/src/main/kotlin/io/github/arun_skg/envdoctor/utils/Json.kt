package io.github.arun_skg.envdoctor.utils

/**
 * An insertion-ordered JSON object, matching the semantics of the reference's
 * ordered maps (ES2015 object insertion order / serde_json Map).
 */
class JsonObject : LinkedHashMap<String, Any?>()

/**
 * A minimal JSON writer producing the exact byte shape shared by
 * `JSON.stringify(x, null, 2)`: two-space indentation, `": "` key separator,
 * `{}`/`[]` for empty containers, and control-character escaping with
 * lowercase hex.
 */
object Json {
    fun pretty(value: Any?): String {
        val sb = StringBuilder()
        write(sb, value, 0, pretty = true)
        return sb.toString()
    }

    fun compact(value: Any?): String {
        val sb = StringBuilder()
        write(sb, value, 0, pretty = false)
        return sb.toString()
    }

    private fun write(sb: StringBuilder, value: Any?, depth: Int, pretty: Boolean) {
        when (value) {
            null -> sb.append("null")
            is Boolean -> sb.append(if (value) "true" else "false")
            is String -> writeString(sb, value)
            is Int -> sb.append(value.toString())
            is Long -> sb.append(value.toString())
            is Double -> sb.append(jsNumber(value))
            is JsonObject -> writeObject(sb, value.entries.map { it.key to it.value }, depth, pretty)
            is Map<*, *> ->
                writeObject(sb, value.entries.map { (k, v) -> (k.toString() to v) }, depth, pretty)
            is List<*> -> writeArray(sb, value, depth, pretty)
            is Array<*> -> writeArray(sb, value.asList(), depth, pretty)
            else -> throw IllegalArgumentException("Unsupported JSON value type: ${value.javaClass}")
        }
    }

    private fun writeObject(sb: StringBuilder, entries: List<Pair<String, Any?>>, depth: Int, pretty: Boolean) {
        if (entries.isEmpty()) {
            sb.append("{}")
            return
        }
        sb.append('{')
        for (i in entries.indices) {
            if (pretty) {
                sb.append('\n')
                indent(sb, depth + 1)
            }
            writeString(sb, entries[i].first)
            sb.append(if (pretty) ": " else ":")
            write(sb, entries[i].second, depth + 1, pretty)
            if (i < entries.size - 1) sb.append(',')
        }
        if (pretty) {
            sb.append('\n')
            indent(sb, depth)
        }
        sb.append('}')
    }

    private fun writeArray(sb: StringBuilder, items: List<*>, depth: Int, pretty: Boolean) {
        if (items.isEmpty()) {
            sb.append("[]")
            return
        }
        sb.append('[')
        for (i in items.indices) {
            if (pretty) {
                sb.append('\n')
                indent(sb, depth + 1)
            }
            write(sb, items[i], depth + 1, pretty)
            if (i < items.size - 1) sb.append(',')
        }
        if (pretty) {
            sb.append('\n')
            indent(sb, depth)
        }
        sb.append(']')
    }

    private fun indent(sb: StringBuilder, depth: Int) {
        for (i in 0 until depth) sb.append("  ")
    }

    private fun writeString(sb: StringBuilder, s: String) {
        sb.append('"')
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\b' -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else ->
                    if (c < ' ') sb.append("\\u").append(c.code.toString(16).padStart(4, '0'))
                    else sb.append(c)
            }
        }
        sb.append('"')
    }

    /** JS number-to-string for the integral doubles YAML/JSON can produce. */
    fun jsNumber(d: Double): String {
        if (d == d.toLong().toDouble() && kotlin.math.abs(d) < 1e15) return d.toLong().toString()
        return d.toString()
    }
}
