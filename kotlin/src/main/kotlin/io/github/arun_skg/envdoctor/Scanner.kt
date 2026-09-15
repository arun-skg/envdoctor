package io.github.arun_skg.envdoctor

import io.github.arun_skg.envdoctor.models.VariableType
import io.github.arun_skg.envdoctor.utils.Glob
import io.github.arun_skg.envdoctor.utils.JsonParser
import io.github.arun_skg.envdoctor.utils.TypeInfer
import java.io.IOException
import java.io.UncheckedIOException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.util.TreeMap
import java.util.TreeSet
import kotlin.io.path.exists
import kotlin.io.path.isRegularFile
import kotlin.io.path.name
import kotlin.io.path.readText

/**
 * Core scanner: reconcile `System.getenv("X")` usage in Kotlin/Java source
 * against `.env` definitions. Local-first — no network, values never printed.
 *
 * Native Kotlin port of the 0.1.2 reference, behaviourally aligned with the
 * Java/Python/Go ports.
 */
object Scanner {

    private val USAGE = Regex("""\bSystem\.getenv\(\s*"([A-Za-z_]\w*)"""")
    private val LINE_COMMENT = Regex("""//[^\n]*""")
    private val BLOCK_COMMENT = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
    private val ENV_LINE = Regex("""^\s*(?:export\s+)?([A-Za-z_]\w*)\s*=(.*)$""")
    private val WEAK_VALUE = Regex(
        """^(changeme|change_me|placeholder|x{3,}|todo|secret|password|passwd|test""" +
            """|example|sample|dummy|your[_-].*|<.*>|\$\{.*\})$""",
        RegexOption.IGNORE_CASE,
    )

    private val COMPOSE_NAME = Regex("""^(?:docker-)?compose(?:[.-].*)?\.ya?ml$""", RegexOption.IGNORE_CASE)
    private val YAML_NAME = Regex("""\.ya?ml$""", RegexOption.IGNORE_CASE)
    private val K8S_APIVERSION = Regex("""^apiVersion:""", RegexOption.MULTILINE)
    private val K8S_KIND = Regex("""^kind:""", RegexOption.MULTILINE)
    private val INTERP_BRACE = Regex("""\$\{([A-Za-z_][A-Za-z0-9_]*)""")
    private val INTERP_BARE = Regex("""\$([A-Za-z_][A-Za-z0-9_]*)""")
    private val ACTIONS_CONTEXT = Regex("""\b(?:secrets|vars|env)\.([A-Za-z_][A-Za-z0-9_]*)""")

    private val IGNORED_DIRS = setOf(".git", "target", "node_modules", "vendor", "build")

    /** Source extensions scanned for `System.getenv(...)` usage. */
    private val SOURCE_EXTENSIONS = setOf("kt", "kts", "java")

    /** Public/client-exposed environment prefixes (case-sensitive, exact). */
    val PUBLIC_PREFIXES = listOf(
        "NEXT_PUBLIC_", "VITE_", "REACT_APP_", "EXPO_PUBLIC_",
        "GATSBY_", "NUXT_PUBLIC_", "VUE_APP_", "PUBLIC_",
    )

    /** Secret-looking name pattern (case-insensitive). */
    val SECRET_NAME = Regex(
        """SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|API_?KEY|ACCESS_?KEY|AUTH""",
        RegexOption.IGNORE_CASE,
    )

    /** One occurrence of a variable inside a single dotenv file. */
    data class Occurrence(val line: Int, val value: String)

    /** One reported issue. `file` is root-relative; values are never included. */
    data class Finding(
        val rule: String,
        val severity: String,
        val name: String,
        val message: String,
        val file: String?,
        val line: Int?,
    )

    /** The DEFINED and USED variable-name sets for a project. */
    data class Names(val defined: Set<String>, val used: Set<String>)

    /** Result of comparing two environment labels. */
    data class Diff(val onlyInA: List<String>, val onlyInB: List<String>, val common: List<String>)

    private fun blank(s: String): String = s.map { if (it == '\n') '\n' else ' ' }.joinToString("")

    /** Blank line/block comments while preserving line structure. */
    fun stripNoise(code: String): String {
        var text = BLOCK_COMMENT.replace(code) { blank(it.value) }
        text = LINE_COMMENT.replace(text) { blank(it.value) }
        return text
    }

    /** Map of variable name to first 1-based line for env usage in source. */
    fun scanSource(content: String): Map<String, Int> {
        val text = stripNoise(content)
        val used = LinkedHashMap<String, Int>()
        for (m in USAGE.findAll(text)) {
            val name = m.groupValues[1]
            if (used.containsKey(name)) continue
            used[name] = lineNumberAt(text, m.range.first)
        }
        return used
    }

    private fun lineNumberAt(text: String, offset: Int): Int {
        var line = 1
        var i = 0
        val end = minOf(offset, text.length)
        while (i < end) {
            if (text[i] == '\n') line++
            i++
        }
        return line
    }

    /**
     * Classify an infra file by relative path, basename, and content.
     * Returns "compose", "actions", "k8s", or null.
     */
    fun classifyInfra(rel: String, base: String, content: String): String? {
        val norm = rel.replace('\\', '/')
        if (COMPOSE_NAME.matches(base)) return "compose"
        if ((norm.startsWith(".github/workflows/") || norm.contains("/.github/workflows/")) &&
            YAML_NAME.containsMatchIn(base)
        ) {
            return "actions"
        }
        if (YAML_NAME.containsMatchIn(base) &&
            K8S_APIVERSION.containsMatchIn(content) &&
            K8S_KIND.containsMatchIn(content)
        ) {
            return "k8s"
        }
        return null
    }

    /**
     * Extract used variable names (first-by-offset origin) from an infra file.
     * Dependency-free: escaped `$$` neutralised, then interpolation (plus
     * GitHub Actions contexts) scanned by regex.
     */
    fun scanInfra(content: String, type: String): Map<String, Int> {
        val text = content.replace("$$", "  ") // neutralise escaped $$ (same length)
        val hits = TreeMap<Int, String>()
        val patterns = mutableListOf(INTERP_BRACE, INTERP_BARE)
        if (type == "actions") patterns.add(ACTIONS_CONTEXT)
        for (p in patterns) {
            for (m in p.findAll(text)) {
                hits.putIfAbsent(m.range.first, m.groupValues[1])
            }
        }
        val used = LinkedHashMap<String, Int>()
        for ((offset, name) in hits) {
            if (used.containsKey(name)) continue
            used[name] = lineNumberAt(text, offset)
        }
        return used
    }

    /** True when a name has a public prefix and looks secret. */
    fun isPublicSecret(name: String): Boolean =
        PUBLIC_PREFIXES.any { name.startsWith(it) } && SECRET_NAME.containsMatchIn(name)

    /** True when a name looks secret (value must never be copied or printed). */
    fun isSecretName(name: String): Boolean = SECRET_NAME.containsMatchIn(name)

    /**
     * Collect ALL occurrences per key within a single dotenv file, in order.
     * Values are used ONLY for detection and are NEVER emitted in output.
     */
    fun parseEnv(content: String): Map<String, List<Occurrence>> {
        val defined = LinkedHashMap<String, MutableList<Occurrence>>()
        content.split('\n').forEachIndexed { i, raw ->
            val trimmed = raw.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("#")) return@forEachIndexed
            val m = ENV_LINE.find(raw) ?: return@forEachIndexed
            var value = m.groupValues[2].trim()
            if (value.length >= 2) {
                val a = value.first()
                val b = value.last()
                if ((a == '"' && b == '"') || (a == '\'' && b == '\'')) {
                    value = value.substring(1, value.length - 1)
                }
            }
            defined.getOrPut(m.groupValues[1]) { mutableListOf() }.add(Occurrence(i + 1, value))
        }
        return defined
    }

    /** Derive an env label from a .env filename; null for *.example. */
    fun envLabel(name: String): String? {
        if (name.endsWith(".example")) return null
        if (name == ".env") return "default"
        if (!name.startsWith(".env.")) return null
        var x = name.substring(".env.".length)
        if (x != "local" && x.endsWith(".local")) {
            x = x.substring(0, x.length - ".local".length)
        }
        return x
    }

    /** Infer a coarse type from a value string ("empty" for blank values). */
    fun inferType(v: String): String = when (TypeInfer.inferType(v)) {
        VariableType.UNKNOWN -> "empty"
        VariableType.INTEGER -> "integer"
        VariableType.FLOAT -> "float"
        VariableType.BOOLEAN -> "boolean"
        VariableType.URL -> "url"
        VariableType.JSON -> "json"
        VariableType.STRING -> "string"
    }

    /** Compatibility group for a non-empty inferred type. */
    fun typeGroup(t: String): String = if (t == "integer" || t == "float") "numeric" else t

    private fun isWeakSecret(v: String): Boolean =
        v.isEmpty() || v.length < 8 || WEAK_VALUE.matches(v)

    /** Levenshtein edit distance between two strings. */
    fun levenshtein(a: String, b: String): Int {
        val d = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            var prev = d[0]
            d[0] = i
            for (j in 1..b.length) {
                val tmp = d[j]
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                d[j] = minOf(minOf(d[j] + 1, d[j - 1] + 1), prev + cost)
                prev = tmp
            }
        }
        return d[b.length]
    }

    private fun typoSuggestion(u: String, defined: Collection<String>): String? {
        var best: String? = null
        var bestDist = Int.MAX_VALUE
        for (d in TreeSet(defined)) {
            if (d == u) continue
            val thresh = if (minOf(u.length, d.length) <= 4) 1 else 2
            val dist = levenshtein(u, d)
            if (dist > thresh) continue
            if (dist < bestDist) {
                bestDist = dist
                best = d
            }
        }
        return best
    }

    private fun isEnvFile(name: String): Boolean =
        envLabel(name) != null && (name == ".env" || name.startsWith(".env."))

    private fun isSourceFile(name: String): Boolean {
        val dot = name.lastIndexOf('.')
        if (dot < 0) return false
        return name.substring(dot + 1).lowercase() in SOURCE_EXTENSIONS
    }

    private fun notIgnored(path: Path): Boolean =
        path.none { it.toString() in IGNORED_DIRS }

    /**
     * Variable-name glob patterns from `.envdoctorignore` at the project root
     * (gitignore-style: one glob per line, `#` comments, blank lines skipped).
     * Matching variables are never reported.
     */
    fun ignorePatterns(root: Path): List<String> {
        val file = root.resolve(".envdoctorignore")
        if (!file.exists()) return emptyList()
        return try {
            file.readText().lines()
                .map { it.trim() }
                .filter { it.isNotEmpty() && !it.startsWith("#") }
        } catch (e: IOException) {
            emptyList()
        }
    }

    private fun isIgnoredName(patterns: List<String>, name: String): Boolean =
        patterns.isNotEmpty() && Glob.matchesAnyGlob(patterns, name)

    private data class EnvIndex(
        val definedFile: LinkedHashMap<String, String> = LinkedHashMap(),
        val definedLine: LinkedHashMap<String, Int> = LinkedHashMap(),
        val definedValue: LinkedHashMap<String, String> = LinkedHashMap(),
        val usedFile: LinkedHashMap<String, String> = LinkedHashMap(),
        val usedLine: LinkedHashMap<String, Int> = LinkedHashMap(),
        val duplicates: MutableList<Finding> = mutableListOf(),
        val labelsByVar: LinkedHashMap<String, LinkedHashMap<String, String>> = LinkedHashMap(),
        val allLabels: TreeSet<String> = TreeSet(),
    )

    /** Walk the project once, indexing dotenv definitions and source/infra usage. */
    private fun index(root: Path): EnvIndex {
        val idx = EnvIndex()
        val stream = Files.walk(root)
        try {
            stream.use { walk ->
                walk.filter { it.isRegularFile() }
                    .filter(::notIgnored)
                    .sorted()
                    .forEach { path ->
                        val name = path.name
                        val isEnv = isEnvFile(name)
                        val isSource = isSourceFile(name)
                        val isYaml = YAML_NAME.containsMatchIn(name)
                        if (!isEnv && !isSource && !isYaml) return@forEach
                        val content = read(path)
                        val rel = root.relativize(path).toString()
                        when {
                            isEnv -> {
                                val label = envLabel(name)!!
                                idx.allLabels.add(label)
                                for ((k, occ) in parseEnv(content)) {
                                    idx.definedFile.putIfAbsent(k, rel)
                                    idx.definedLine.putIfAbsent(k, occ[0].line)
                                    idx.definedValue.putIfAbsent(k, occ[0].value)
                                    idx.labelsByVar.getOrPut(k) { LinkedHashMap() }
                                        .putIfAbsent(label, occ[0].value)
                                    if (occ.size >= 2) {
                                        val lines = occ.joinToString(", ") { it.line.toString() }
                                        idx.duplicates.add(
                                            Finding(
                                                "duplicates", "error", k,
                                                "defined ${occ.size} times in the same file (lines $lines)",
                                                rel, occ[0].line,
                                            ),
                                        )
                                    }
                                }
                            }
                            isSource -> {
                                for ((k, ln) in scanSource(content)) {
                                    idx.usedFile.putIfAbsent(k, rel)
                                    idx.usedLine.putIfAbsent(k, ln)
                                }
                            }
                            else -> {
                                val type = classifyInfra(rel, name, content)
                                if (type != null) {
                                    for ((k, ln) in scanInfra(content, type)) {
                                        idx.usedFile.putIfAbsent(k, rel)
                                        idx.usedLine.putIfAbsent(k, ln)
                                    }
                                }
                            }
                        }
                    }
            }
        } catch (e: IOException) {
            throw UncheckedIOException(e)
        }
        return idx
    }

    /** Reconcile `.env` definitions against source usage under [root]. */
    fun scan(root: Path): List<Finding> {
        val idx = index(root)
        val ignore = ignorePatterns(root)
        val definedNames = TreeSet(idx.definedFile.keys)

        // errors: undefined-in-source
        val undefined = TreeSet(idx.usedFile.keys)
            .filter { it !in idx.definedFile }
            .map {
                Finding(
                    "undefined-in-source", "error", it,
                    "referenced but not defined in any environment file",
                    idx.usedFile[it], idx.usedLine[it],
                )
            }

        // errors: duplicates (sorted by name)
        val duplicates = idx.duplicates.sortedBy { it.name }

        // errors: public-prefix
        val publicPrefix = definedNames.filter(::isPublicSecret).map {
            Finding(
                "public-prefix", "error", it,
                "secret-looking variable is exposed to client bundles via a public prefix",
                idx.definedFile[it], idx.definedLine[it],
            )
        }

        // errors: type-mismatch
        val typeMismatch = TreeMap(idx.labelsByVar).mapNotNull { (k, vals) ->
            if (vals.size < 2) return@mapNotNull null
            val groups = vals.values
                .map(::inferType)
                .filter { it != "empty" }
                .map(::typeGroup)
                .toCollection(TreeSet())
            if (groups.size < 2) return@mapNotNull null
            Finding(
                "type-mismatch", "error", k,
                "inferred type differs across environments",
                idx.definedFile[k], idx.definedLine[k],
            )
        }

        // errors: schema-validation
        val schemaValidation = mutableListOf<Finding>()
        val schema = loadSchema(root)
        for (name in TreeSet(schema.keys)) {
            val rule = schema[name] as? Map<*, *> ?: continue
            if (name in idx.definedFile) {
                val msg = schemaFailure(rule, idx.definedValue.getValue(name))
                if (msg != null) {
                    schemaValidation.add(
                        Finding("schema-validation", "error", name, msg, idx.definedFile[name], idx.definedLine[name]),
                    )
                }
            } else if (rule["optional"] != true) {
                schemaValidation.add(
                    Finding("schema-validation", "error", name, "required by schema but not defined", null, null),
                )
            }
        }

        // warnings: unused
        val unused = definedNames.filter { it !in idx.usedFile }.map {
            Finding(
                "unused", "warning", it,
                "defined but never referenced in source",
                idx.definedFile[it], idx.definedLine[it],
            )
        }

        // warnings: environment-diff
        val environmentDiff = mutableListOf<Finding>()
        if (idx.allLabels.size >= 2) {
            for ((k, vals) in TreeMap(idx.labelsByVar)) {
                val present = TreeSet(vals.keys)
                val absent = TreeSet(idx.allLabels).apply { removeAll(present) }
                if (present.isEmpty() || absent.isEmpty()) continue
                environmentDiff.add(
                    Finding(
                        "environment-diff", "warning", k,
                        "defined in ${present.joinToString(", ")} but missing in ${absent.joinToString(", ")}",
                        idx.definedFile[k], idx.definedLine[k],
                    ),
                )
            }
        }

        // warnings: weak-secret
        val weakSecret = definedNames
            .filter { SECRET_NAME.containsMatchIn(it) && isWeakSecret(idx.definedValue.getValue(it)) }
            .map {
                Finding(
                    "weak-secret", "warning", it,
                    "secret-looking variable has a weak or placeholder value",
                    idx.definedFile[it], idx.definedLine[it],
                )
            }

        // warnings: typo
        val typo = TreeSet(idx.usedFile.keys)
            .filter { it !in idx.definedFile }
            .mapNotNull { u ->
                val d = typoSuggestion(u, definedNames) ?: return@mapNotNull null
                Finding(
                    "typo", "warning", u,
                    "\"$u\" is not defined; did you mean \"$d\"?",
                    idx.usedFile[u], idx.usedLine[u],
                )
            }

        val findings = undefined + duplicates + publicPrefix + typeMismatch + schemaValidation +
            unused + environmentDiff + weakSecret + typo
        return findings.filterNot { isIgnoredName(ignore, it.name) }
    }

    /** Compute the DEFINED and USED variable-name sets, same discovery as [scan]. */
    fun collectNames(root: Path): Names {
        val idx = index(root)
        val ignore = ignorePatterns(root)
        val defined = idx.definedFile.keys.filterNot { isIgnoredName(ignore, it) }.toCollection(TreeSet())
        val used = idx.usedFile.keys.filterNot { isIgnoredName(ignore, it) }.toCollection(TreeSet())
        return Names(defined, used)
    }

    /**
     * Render the exact `.env.example` and `ENVIRONMENT.md` contents for a
     * project. Values are NEVER written.
     */
    fun generate(root: Path): Pair<String, String> {
        val names = collectNames(root)
        val all = TreeSet(names.defined).apply { addAll(names.used) }

        val example = buildString {
            append("# Generated by envdoctor. Fill in values; do not commit secrets.\n")
            for (name in all) append(name).append("=\n")
        }
        val md = buildString {
            append("# Environment variables\n\n")
            append("| Variable | Defined | Used |\n")
            append("| --- | --- | --- |\n")
            for (name in all) {
                val d = if (name in names.defined) "yes" else "no"
                val u = if (name in names.used) "yes" else "no"
                append("| ").append(name).append(" | ").append(d).append(" | ").append(u).append(" |\n")
            }
        }
        return example to md
    }

    /** Map each environment label to the set of variable names defined in it. */
    fun definedByLabel(root: Path): Map<String, Set<String>> {
        val labels = LinkedHashMap<String, MutableSet<String>>()
        val stream = Files.walk(root)
        try {
            stream.use { walk ->
                walk.filter { it.isRegularFile() }
                    .filter(::notIgnored)
                    .sorted()
                    .forEach { path ->
                        val name = path.name
                        if (!isEnvFile(name)) return@forEach
                        val label = envLabel(name) ?: return@forEach
                        labels.getOrPut(label) { TreeSet() }.addAll(parseEnv(read(path)).keys)
                    }
            }
        } catch (e: IOException) {
            throw UncheckedIOException(e)
        }
        return labels
    }

    /** Compare the variable names defined in two environment labels. */
    fun diffLabels(root: Path, a: String, b: String): Diff {
        val labels = definedByLabel(root)
        val da = labels[a] ?: emptySet()
        val db = labels[b] ?: emptySet()
        val onlyA = mutableListOf<String>()
        val common = mutableListOf<String>()
        for (k in TreeSet(da)) (if (k in db) common else onlyA).add(k)
        val onlyB = TreeSet(db).filter { it !in da }
        return Diff(onlyA, onlyB, common)
    }

    /**
     * Append keys present in [from] but missing from [to] as `KEY=`
     * placeholders. Values are never copied.
     */
    fun syncLabels(root: Path, from: String, to: String, dryRun: Boolean): List<String> {
        val labels = definedByLabel(root)
        val df = labels[from] ?: emptySet()
        val dt = labels[to] ?: emptySet()
        val missing = TreeSet(df).filter { it !in dt }
        if (missing.isNotEmpty() && !dryRun) {
            val target = root.resolve(if (to == "default") ".env" else ".env.$to")
            try {
                val existing = if (target.exists()) target.readText() else ""
                val sb = StringBuilder()
                if (existing.isNotEmpty() && !existing.endsWith("\n")) sb.append("\n")
                for (k in missing) sb.append(k).append("=\n")
                Files.writeString(
                    target, sb.toString(),
                    StandardOpenOption.CREATE, StandardOpenOption.APPEND,
                )
            } catch (e: IOException) {
                throw UncheckedIOException(e)
            }
        }
        return missing
    }

    /** Load `envdoctor.schema.json` from the project root, or {} if absent/invalid. */
    @Suppress("UNCHECKED_CAST")
    fun loadSchema(root: Path): Map<String, Any?> {
        val p = root.resolve("envdoctor.schema.json")
        if (!p.exists()) return emptyMap()
        return try {
            (JsonParser.parse(p.readText()) as? Map<String, Any?>) ?: emptyMap()
        } catch (e: Exception) {
            emptyMap()
        }
    }

    internal fun schemaTypeOk(v: String, declared: String): Boolean = when (declared) {
        "string" -> true
        "integer" -> Regex("-?\\d+").matches(v)
        "float" -> Regex("-?\\d+(\\.\\d+)?").matches(v)
        "boolean" -> v.equals("true", true) || v.equals("false", true)
        "url" -> v.startsWith("http://") || v.startsWith("https://")
        "json" -> try {
            JsonParser.parse(v)
            true
        } catch (e: Exception) {
            false
        }
        else -> true
    }

    private val NUMERIC = Regex("-?\\d+(\\.\\d+)?")

    /** Return the first schema-check failure message for [value], or null. */
    internal fun schemaFailure(rule: Map<*, *>, value: String): String? {
        val t = rule["type"]
        if (t is String && !schemaTypeOk(value, t)) {
            return "value does not match schema type $t"
        }
        val en = rule["enum"]
        if (en is List<*> && en.none { value == it }) {
            return "value is not one of the allowed values"
        }
        val rx = rule["regex"]
        if (rx is String) {
            try {
                if (!Regex(rx).containsMatchIn(value)) {
                    return "value does not match the required pattern"
                }
            } catch (e: Exception) {
                // invalid pattern: skip
            }
        }
        if (NUMERIC.matches(value)) {
            val num = value.toDouble()
            val mn = rule["min"]
            if (mn is Number && num < mn.toDouble()) return "value is below the minimum"
            val mx = rule["max"]
            if (mx is Number && num > mx.toDouble()) return "value exceeds the maximum"
        }
        return null
    }

    private fun read(path: Path): String = try {
        path.readText()
    } catch (e: IOException) {
        throw UncheckedIOException(e)
    }
}
