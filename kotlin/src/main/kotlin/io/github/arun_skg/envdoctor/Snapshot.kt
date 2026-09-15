package io.github.arun_skg.envdoctor

import io.github.arun_skg.envdoctor.utils.Json
import io.github.arun_skg.envdoctor.utils.JsonObject
import io.github.arun_skg.envdoctor.utils.JsonParser
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import java.util.Base64
import java.util.concurrent.TimeUnit
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/**
 * Runtime snapshots: capture this machine's live runtime (tool versions,
 * `$PATH` order, OS, non-secret env var NAMES) so two machines can be diffed.
 *
 * The envdoctor invariant holds: **values are never captured.** Only variable
 * names are recorded, and secret-looking names are dropped entirely.
 *
 * Snapshot tokens are wire-compatible with the reference implementation:
 * `envd1:` + base64url(gzip(json)).
 */
object Snapshot {

    /** Bumped whenever the snapshot shape changes; snapshot-diff refuses newer tokens. */
    const val SNAPSHOT_SCHEMA = 1

    private const val TOKEN_PREFIX = "envd1:"

    data class ToolVersion(val tool: String, val version: String, val resolvedFrom: String)

    data class GlobalPackage(val name: String, val version: String)

    data class OsInfo(val platform: String, val arch: String, val release: String)

    data class RuntimeSnapshot(
        val schema: Int,
        val capturedAt: String,
        val os: OsInfo,
        val tools: List<ToolVersion>,
        val path: List<String>,
        val globals: Map<String, List<GlobalPackage>>,
        val envFlagNames: List<String>,
    )

    // --- Capture ------------------------------------------------------------

    /** First dotted version-looking token in a tool's output. */
    private val VERSION_RE = Regex("""(\d+\.\d+(?:\.\d+)?)""")

    /** Tools probed by default. */
    private val TOOL_PROBES: List<Pair<String, List<String>>> = listOf(
        "node" to listOf("-v"),
        "python3" to listOf("--version"),
        "python" to listOf("--version"),
        "go" to listOf("version"),
        "rustc" to listOf("-V"),
        "java" to listOf("-version"),
        "ruby" to listOf("-v"),
        "php" to listOf("-v"),
        "perl" to listOf("-v"),
        "cc" to listOf("--version"),
        "git" to listOf("--version"),
    )

    private val isWindows: Boolean =
        System.getProperty("os.name", "").lowercase().startsWith("windows")

    /** Collapse a leading $HOME to "~" so snapshots don't leak usernames. */
    fun collapseHome(p: String): String {
        val home = System.getProperty("user.home") ?: return p
        if (home.isEmpty()) return p
        if (p == home || p.startsWith(home + File.separator)) {
            return "~" + p.substring(home.length)
        }
        return p
    }

    /** Ordered, de-duplicated `$PATH` entries with $HOME collapsed. */
    fun collectPath(pathEnv: String = System.getenv("PATH") ?: ""): List<String> {
        val seen = LinkedHashSet<String>()
        for (raw in pathEnv.split(File.pathSeparator)) {
            if (raw.isEmpty()) continue
            seen.add(collapseHome(raw))
        }
        return seen.toList()
    }

    /** Non-secret env var NAMES only. Secret-looking names are dropped, not masked. */
    fun collectEnvFlagNames(env: Map<String, String> = System.getenv()): List<String> =
        env.keys.filter { !Scanner.isSecretName(it) }.sorted()

    private fun runProbe(command: List<String>, timeoutMs: Long): String? = try {
        val pb = ProcessBuilder(command).redirectErrorStream(true)
        val proc = pb.start()
        if (!proc.waitFor(timeoutMs, TimeUnit.MILLISECONDS)) {
            proc.destroyForcibly()
            null
        } else {
            proc.inputStream.readBytes().toString(Charsets.UTF_8)
        }
    } catch (e: Exception) {
        null
    }

    /** Probe one CLI's version; null when the tool isn't installed or misbehaves. */
    fun probeVersion(tool: String, args: List<String>): String? {
        val out = runProbe(listOf(tool) + args, 4000) ?: return null
        return VERSION_RE.find(out)?.groupValues?.get(1)
    }

    /** Locate which PATH directory a command resolves from, $HOME collapsed. */
    fun resolveFrom(tool: String): String {
        val finder = if (isWindows) "where" else "which"
        val out = runProbe(listOf(finder, tool), 4000) ?: return ""
        val first = out.lines().firstOrNull { it.isNotBlank() }?.trim() ?: return ""
        return collapseHome(File(first).parent ?: "")
    }

    /** Probe every known tool; only installed ones appear, sorted by tool id. */
    fun collectTools(): List<ToolVersion> =
        TOOL_PROBES.mapNotNull { (tool, args) ->
            val version = probeVersion(tool, args) ?: return@mapNotNull null
            ToolVersion(tool, version, resolveFrom(tool))
        }.sortedBy { it.tool }

    /** Global package inventory, opt-in (--globals) because it is slow. */
    @Suppress("UNCHECKED_CAST")
    fun collectGlobals(): Map<String, List<GlobalPackage>> {
        val out = runProbe(listOf("npm", "ls", "-g", "--depth=0", "--json"), 15000) ?: return emptyMap()
        return try {
            val parsed = JsonParser.parse(out) as? Map<String, Any?> ?: return emptyMap()
            val deps = parsed["dependencies"] as? Map<String, Any?> ?: return emptyMap()
            val pkgs = deps.mapNotNull { (name, meta) ->
                val version = (meta as? Map<String, Any?>)?.get("version") as? String ?: ""
                GlobalPackage(name, version)
            }.sortedBy { it.name }
            if (pkgs.isEmpty()) emptyMap() else mapOf("npm" to pkgs)
        } catch (e: Exception) {
            emptyMap()
        }
    }

    /** Node-style platform string ("darwin", "linux", "win32", ...). */
    fun osPlatform(): String {
        val name = System.getProperty("os.name", "").lowercase()
        return when {
            name.startsWith("windows") -> "win32"
            name.contains("mac") || name.contains("darwin") -> "darwin"
            name.contains("linux") -> "linux"
            name.contains("freebsd") -> "freebsd"
            name.contains("sunos") || name.contains("solaris") -> "sunos"
            name.contains("aix") -> "aix"
            else -> name.replace(" ", "")
        }
    }

    /** Node-style arch string ("x64", "arm64", "ia32", ...). */
    fun osArch(): String = when (System.getProperty("os.arch", "").lowercase()) {
        "amd64", "x86_64" -> "x64"
        "x86", "i386", "i486", "i586", "i686" -> "ia32"
        "aarch64" -> "arm64"
        else -> System.getProperty("os.arch", "").lowercase()
    }

    /** Capture this machine's live runtime. Never records any value. */
    fun capture(globals: Boolean = false): RuntimeSnapshot = RuntimeSnapshot(
        schema = SNAPSHOT_SCHEMA,
        capturedAt = Instant.now().toString(),
        os = OsInfo(osPlatform(), osArch(), System.getProperty("os.version", "")),
        tools = collectTools(),
        path = collectPath(),
        globals = if (globals) collectGlobals() else emptyMap(),
        envFlagNames = collectEnvFlagNames(),
    )

    // --- Serialization -------------------------------------------------------

    fun toJson(s: RuntimeSnapshot): JsonObject {
        val os = JsonObject()
        os["platform"] = s.os.platform
        os["arch"] = s.os.arch
        os["release"] = s.os.release
        val tools = s.tools.map { t ->
            val o = JsonObject()
            o["tool"] = t.tool
            o["version"] = t.version
            o["resolvedFrom"] = t.resolvedFrom
            o
        }
        val globals = JsonObject()
        for ((eco, pkgs) in s.globals) {
            globals[eco] = pkgs.map { p ->
                val o = JsonObject()
                o["name"] = p.name
                o["version"] = p.version
                o
            }
        }
        val root = JsonObject()
        root["schema"] = s.schema
        root["capturedAt"] = s.capturedAt
        root["os"] = os
        root["tools"] = tools
        root["path"] = s.path
        root["globals"] = globals
        root["envFlagNames"] = s.envFlagNames
        return root
    }

    @Suppress("UNCHECKED_CAST")
    fun fromJson(value: Any?): RuntimeSnapshot {
        val map = value as? Map<String, Any?> ?: throw IllegalArgumentException("Not a runtime snapshot.")
        val schema = (map["schema"] as? Number)?.toInt()
            ?: throw IllegalArgumentException("Not a runtime snapshot.")
        val toolsRaw = map["tools"] as? List<Any?>
            ?: throw IllegalArgumentException("Not a runtime snapshot.")
        if (schema > SNAPSHOT_SCHEMA) {
            throw IllegalArgumentException(
                "Snapshot schema v$schema is newer than this envdoctor (v$SNAPSHOT_SCHEMA). Upgrade to compare it.",
            )
        }
        val osMap = map["os"] as? Map<String, Any?> ?: emptyMap()
        val tools = toolsRaw.mapNotNull { t ->
            val m = t as? Map<String, Any?> ?: return@mapNotNull null
            ToolVersion(
                m["tool"] as? String ?: "",
                m["version"] as? String ?: "",
                m["resolvedFrom"] as? String ?: "",
            )
        }
        val globalsRaw = map["globals"] as? Map<String, Any?> ?: emptyMap()
        val globals = LinkedHashMap<String, List<GlobalPackage>>()
        for ((eco, pkgs) in globalsRaw) {
            val list = (pkgs as? List<Any?>)?.mapNotNull { p ->
                val m = p as? Map<String, Any?> ?: return@mapNotNull null
                GlobalPackage(m["name"] as? String ?: "", m["version"] as? String ?: "")
            } ?: emptyList()
            globals[eco] = list
        }
        return RuntimeSnapshot(
            schema = schema,
            capturedAt = map["capturedAt"] as? String ?: "",
            os = OsInfo(
                osMap["platform"] as? String ?: "",
                osMap["arch"] as? String ?: "",
                osMap["release"] as? String ?: "",
            ),
            tools = tools,
            path = (map["path"] as? List<Any?>)?.mapNotNull { it as? String } ?: emptyList(),
            globals = globals,
            envFlagNames = (map["envFlagNames"] as? List<Any?>)?.mapNotNull { it as? String } ?: emptyList(),
        )
    }

    /** Encode a snapshot into a single-line, paste-safe token. */
    fun encodeToken(snapshot: RuntimeSnapshot): String {
        val json = Json.compact(toJson(snapshot)).toByteArray(Charsets.UTF_8)
        val bos = ByteArrayOutputStream()
        GZIPOutputStream(bos).use { it.write(json) }
        return TOKEN_PREFIX + Base64.getUrlEncoder().withoutPadding().encodeToString(bos.toByteArray())
    }

    /** Decode a token back into a snapshot. Throws on malformed or too-new input. */
    fun decodeToken(token: String): RuntimeSnapshot {
        val trimmed = token.trim()
        if (!trimmed.startsWith(TOKEN_PREFIX)) {
            throw IllegalArgumentException("Not an envdoctor snapshot token (missing envd1: prefix).")
        }
        try {
            val buf = Base64.getUrlDecoder().decode(trimmed.substring(TOKEN_PREFIX.length))
            val json = GZIPInputStream(ByteArrayInputStream(buf)).readBytes().toString(Charsets.UTF_8)
            return fromJson(JsonParser.parse(json))
        } catch (e: IllegalArgumentException) {
            if (e.message?.startsWith("Snapshot schema") == true ||
                e.message?.startsWith("Not a runtime snapshot") == true
            ) {
                throw e
            }
            throw IllegalArgumentException("Corrupt snapshot token: could not decode.")
        } catch (e: Exception) {
            throw IllegalArgumentException("Corrupt snapshot token: could not decode.")
        }
    }

    /** Parse raw JSON (from a --output file) into a validated snapshot. */
    fun parseSnapshotJson(text: String): RuntimeSnapshot = try {
        fromJson(JsonParser.parse(text))
    } catch (e: IllegalArgumentException) {
        if (e.message?.startsWith("Snapshot schema") == true ||
            e.message?.startsWith("Not a runtime snapshot") == true
        ) {
            throw e
        }
        throw IllegalArgumentException("Invalid snapshot JSON.")
    } catch (e: Exception) {
        throw IllegalArgumentException("Invalid snapshot JSON.")
    }

    // --- Compare -------------------------------------------------------------

    enum class Status { same, different, onlyA, onlyB }

    data class ToolDiff(val name: String, val status: Status, val a: String?, val b: String?)

    data class GlobalDiff(
        val ecosystem: String,
        val name: String,
        val status: Status,
        val a: String?,
        val b: String?,
    )

    data class RuntimeDiff(
        val osStatus: Status,
        val osA: String,
        val osB: String,
        val tools: List<ToolDiff>,
        val pathReordered: Boolean,
        val pathOnlyA: List<String>,
        val pathOnlyB: List<String>,
        val globals: List<GlobalDiff>,
        val envFlagOnlyA: List<String>,
        val envFlagOnlyB: List<String>,
        val equivalent: Boolean,
    )

    private fun statusFor(a: String?, b: String?): Status = when {
        a != null && b != null -> if (a == b) Status.same else Status.different
        a != null -> Status.onlyA
        else -> Status.onlyB
    }

    private fun onlyIn(a: List<String>, b: List<String>): List<String> {
        val set = b.toSet()
        return a.filter { it !in set }
    }

    /** Pure comparison of two runtime snapshots. `capturedAt` is ignored. */
    fun compare(a: RuntimeSnapshot, b: RuntimeSnapshot): RuntimeDiff {
        val av = a.tools.associate { it.tool to it.version }
        val bv = b.tools.associate { it.tool to it.version }
        val tools = (av.keys + bv.keys).sorted().map { name ->
            ToolDiff(name, statusFor(av[name], bv[name]), av[name], bv[name])
        }

        val pathOnlyA = onlyIn(a.path, b.path)
        val pathOnlyB = onlyIn(b.path, a.path)
        val pathReordered = pathOnlyA.isEmpty() && pathOnlyB.isEmpty() && a.path != b.path

        val globals = mutableListOf<GlobalDiff>()
        for (eco in (a.globals.keys + b.globals.keys).sorted()) {
            val ga = (a.globals[eco] ?: emptyList()).associate { it.name to it.version }
            val gb = (b.globals[eco] ?: emptyList()).associate { it.name to it.version }
            for (name in (ga.keys + gb.keys)) {
                val status = statusFor(ga[name], gb[name])
                if (status == Status.same) continue
                globals.add(GlobalDiff(eco, name, status, ga[name], gb[name]))
            }
        }
        globals.sortBy { it.name }

        val envFlagOnlyA = onlyIn(a.envFlagNames, b.envFlagNames)
        val envFlagOnlyB = onlyIn(b.envFlagNames, a.envFlagNames)

        val osSame = a.os == b.os
        fun fmtOs(s: RuntimeSnapshot) = "${s.os.platform}/${s.os.arch} ${s.os.release}"

        val equivalent = tools.all { it.status == Status.same } &&
            !pathReordered && pathOnlyA.isEmpty() && pathOnlyB.isEmpty() && globals.isEmpty()

        return RuntimeDiff(
            osStatus = if (osSame) Status.same else Status.different,
            osA = fmtOs(a),
            osB = fmtOs(b),
            tools = tools,
            pathReordered = pathReordered,
            pathOnlyA = pathOnlyA,
            pathOnlyB = pathOnlyB,
            globals = globals,
            envFlagOnlyA = envFlagOnlyA,
            envFlagOnlyB = envFlagOnlyB,
            equivalent = equivalent,
        )
    }

    /** Serialize a diff for `--json` output (keys match the reference). */
    fun diffToJson(d: RuntimeDiff): JsonObject {
        val os = JsonObject()
        os["status"] = d.osStatus.name
        os["a"] = d.osA
        os["b"] = d.osB
        val tools = d.tools.map { t ->
            val o = JsonObject()
            o["name"] = t.name
            o["status"] = t.status.name
            if (t.a != null) o["a"] = t.a
            if (t.b != null) o["b"] = t.b
            o
        }
        val globals = d.globals.map { g ->
            val o = JsonObject()
            o["ecosystem"] = g.ecosystem
            o["name"] = g.name
            o["status"] = g.status.name
            if (g.a != null) o["a"] = g.a
            if (g.b != null) o["b"] = g.b
            o
        }
        val root = JsonObject()
        root["exitCode"] = if (d.equivalent) 0 else 1
        root["os"] = os
        root["tools"] = tools
        root["pathReordered"] = d.pathReordered
        root["pathOnlyA"] = d.pathOnlyA
        root["pathOnlyB"] = d.pathOnlyB
        root["globals"] = globals
        root["envFlagOnlyA"] = d.envFlagOnlyA
        root["envFlagOnlyB"] = d.envFlagOnlyB
        root["equivalent"] = d.equivalent
        return root
    }
}
