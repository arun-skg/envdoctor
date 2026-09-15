package io.github.arun_skg.envdoctor

import io.github.arun_skg.envdoctor.utils.Json
import io.github.arun_skg.envdoctor.utils.JsonObject
import io.github.arun_skg.envdoctor.utils.Out
import java.io.IOException
import java.io.UncheckedIOException
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.exists

/** Command-line entry point for the native Kotlin envdoctor. */
object Cli {

    const val VERSION = "0.1.2"

    @JvmStatic
    fun run(args: Array<String>): Int {
        if (args.isNotEmpty()) {
            when (args[0]) {
                "diff" -> return runDiff(args)
                "sync" -> return runSync(args)
                "init" -> return runInit(args)
                "fix" -> return runFix(args)
                "snapshot" -> return runSnapshot(args)
                "snapshot-diff" -> return runSnapshotDiff(args)
                "--version", "-v" -> {
                    Out.println("envdoctor $VERSION (kotlin)")
                    return 0
                }
                "--help", "-h", "help" -> {
                    printHelp()
                    return 0
                }
            }
        }
        return runScan(args)
    }

    private fun printHelp() {
        Out.println(
            """
            envdoctor — local-first consistency checker for environment variables.

            Usage:
              envdoctor [scan] [-d DIR] [--strict] [--no-color] [--json]
              envdoctor diff <a> <b> [-d DIR] [--json]
              envdoctor sync <from> <to> [-d DIR] [--dry-run] [--json]
              envdoctor init [-d DIR] [--force]
              envdoctor fix [-d DIR]
              envdoctor snapshot [--output FILE] [--token] [--json] [--globals]
              envdoctor snapshot-diff <a> <b> [--json]
              envdoctor --version

            Values are never printed. Exit code is non-zero when errors are found.
            """.trimIndent(),
        )
    }

    // --- shared arg parsing ---------------------------------------------------

    private data class Sub(
        val pos: List<String>,
        val dir: String,
        val dryRun: Boolean,
        val json: Boolean,
        val strict: Boolean = false,
        val noColor: Boolean = false,
        val force: Boolean = false,
        val output: String? = null,
        val token: Boolean = false,
        val globals: Boolean = false,
    )

    private fun parseArgs(args: Array<String>, start: Int): Sub {
        val pos = mutableListOf<String>()
        var dir = "."
        var dry = false
        var json = false
        var strict = false
        var noColor = false
        var force = false
        var output: String? = null
        var token = false
        var globals = false
        var i = start
        while (i < args.size) {
            val a = args[i]
            when {
                (a == "-d" || a == "--dir") && i + 1 < args.size -> dir = args[++i]
                a.startsWith("--dir=") -> dir = a.removePrefix("--dir=")
                a == "--dry-run" -> dry = true
                a == "--json" -> json = true
                a == "--strict" -> strict = true
                a == "--no-color" -> noColor = true
                a == "--force" -> force = true
                (a == "-o" || a == "--output") && i + 1 < args.size -> output = args[++i]
                a.startsWith("--output=") -> output = a.removePrefix("--output=")
                a == "--token" -> token = true
                a == "--globals" -> globals = true
                else -> pos.add(a)
            }
            i++
        }
        return Sub(pos, dir, dry, json, strict, noColor, force, output, token, globals)
    }

    private fun root(dir: String): Path =
        Path.of(dir).toAbsolutePath().normalize()

    // --- scan -------------------------------------------------------------------

    private val RED = "[31m"
    private val YELLOW = "[33m"
    private val DIM = "[2m"
    private val RESET = "[0m"

    private fun color(text: String, code: String, useColor: Boolean): String =
        if (useColor) "$code$text$RESET" else text

    /** Serialize findings as a compact JSON array; values are never included. */
    fun findingsToJson(findings: List<Scanner.Finding>): String {
        val items = findings.map { f ->
            val o = JsonObject()
            o["rule"] = f.rule
            o["severity"] = f.severity
            o["name"] = f.name
            o["message"] = f.message
            o["file"] = f.file
            o["line"] = f.line
            o
        }
        return Json.compact(items)
    }

    fun runScan(args: Array<String>): Int {
        val start = if (args.isNotEmpty() && args[0] == "scan") 1 else 0
        val s = parseArgs(args, start)
        val root = root(s.dir)
        val findings = Scanner.scan(root)
        val errors = findings.filter { it.severity == "error" }
        val warnings = findings.filter { it.severity == "warning" }

        if (s.json) {
            Out.println(findingsToJson(findings))
            return if (errors.isNotEmpty() || (s.strict && warnings.isNotEmpty())) 1 else 0
        }

        val useColor = !s.noColor && System.console() != null
        Out.println("ENVIRONMENT AUDIT")
        Out.println("=".repeat(40))
        if (findings.isEmpty()) {
            Out.println("")
            Out.println("No issues found.")
            return 0
        }
        if (errors.isNotEmpty()) {
            Out.println("")
            Out.println(color("Errors", RED, useColor))
            for (f in errors) {
                Out.println("  x ${f.name}${loc(f, useColor)}  ${f.message}")
            }
        }
        if (warnings.isNotEmpty()) {
            Out.println("")
            Out.println(color("Warnings", YELLOW, useColor))
            for (f in warnings) {
                Out.println("  ! ${f.name}${loc(f, useColor)}  ${f.message}")
            }
        }
        Out.println("")
        Out.println("Summary: ${errors.size} error(s), ${warnings.size} warning(s)")
        return if (errors.isNotEmpty() || (s.strict && warnings.isNotEmpty())) 1 else 0
    }

    private fun loc(f: Scanner.Finding, useColor: Boolean = false): String =
        if (f.file == null || f.line == null) "" else " " + color("${f.file}:${f.line}", DIM, useColor)

    // --- diff / sync -----------------------------------------------------------

    private fun jsonStringArray(xs: List<String>): String = Json.compact(xs)

    fun runDiff(args: Array<String>): Int {
        val s = parseArgs(args, 1)
        val a = s.pos.getOrElse(0) { "" }
        val b = s.pos.getOrElse(1) { "" }
        val d = Scanner.diffLabels(root(s.dir), a, b)
        if (s.json) {
            val o = JsonObject()
            o["a"] = a
            o["b"] = b
            o["onlyInA"] = d.onlyInA
            o["onlyInB"] = d.onlyInB
            o["common"] = d.common
            Out.println(Json.compact(o))
            return 0
        }
        Out.println("ENVIRONMENT DIFF: $a vs $b")
        Out.println("=".repeat(40))
        if (d.onlyInA.isNotEmpty()) {
            Out.println("Only in $a:")
            for (k in d.onlyInA) Out.println("  + $k")
        }
        if (d.onlyInB.isNotEmpty()) {
            Out.println("Only in $b:")
            for (k in d.onlyInB) Out.println("  + $k")
        }
        Out.println("Common: ${d.common.size} variable(s)")
        return 0
    }

    fun runSync(args: Array<String>): Int {
        val s = parseArgs(args, 1)
        val from = s.pos.getOrElse(0) { "" }
        val to = s.pos.getOrElse(1) { "" }
        val added = Scanner.syncLabels(root(s.dir), from, to, s.dryRun)
        if (s.json) {
            val o = JsonObject()
            o["from"] = from
            o["to"] = to
            o["added"] = added
            o["dryRun"] = s.dryRun
            Out.println(Json.compact(o))
            return 0
        }
        if (added.isEmpty()) {
            Out.println("Already in sync.")
            return 0
        }
        val verb = if (s.dryRun) "Would sync" else "Synced"
        Out.println("$verb ${added.size} variable(s) from $from to $to:")
        for (k in added) Out.println("  + $k")
        return 0
    }

    // --- init / fix ------------------------------------------------------------

    private val GENERATED_FILES = listOf(".env.example", "ENVIRONMENT.md")

    fun runInit(args: Array<String>): Int {
        val s = parseArgs(args, 1)
        val root = root(s.dir)
        val docs = Scanner.generate(root)
        val files = listOf(".env.example" to docs.first, "ENVIRONMENT.md" to docs.second)
        for ((name, content) in files) {
            val target = root.resolve(name)
            when {
                s.force -> {
                    writeFile(target, content)
                    Out.println("wrote $name")
                }
                target.exists() -> Out.println("skipped $name (exists)")
                else -> {
                    writeFile(target, content)
                    Out.println("created $name")
                }
            }
        }
        return 0
    }

    fun runFix(args: Array<String>): Int {
        val s = parseArgs(args, 1)
        val root = root(s.dir)
        val docs = Scanner.generate(root)
        val files = listOf(".env.example" to docs.first, "ENVIRONMENT.md" to docs.second)
        for ((name, content) in files) {
            writeFile(root.resolve(name), content)
            Out.println("wrote $name")
        }
        return 0
    }

    private fun writeFile(target: Path, content: String) {
        try {
            Files.writeString(target, content)
        } catch (e: IOException) {
            throw UncheckedIOException(e)
        }
    }

    // --- snapshot ----------------------------------------------------------------

    fun runSnapshot(args: Array<String>): Int {
        val s = parseArgs(args, 1)
        val snap = Snapshot.capture(globals = s.globals)

        if (s.output != null) {
            val dest = root(s.dir).resolve(s.output)
            writeFile(dest, Json.pretty(Snapshot.toJson(snap)) + "\n")
            Out.eprintln("✓ Snapshot written to ${s.output}")
        }

        if (s.json) {
            Out.println(Json.pretty(Snapshot.toJson(snap)))
            return 0
        }

        if (s.token) {
            Out.println(Snapshot.encodeToken(snap))
            return 0
        }

        val title = "RUNTIME SNAPSHOT"
        Out.println(title)
        Out.println("=".repeat(title.length * 2))
        Out.println("")
        Out.println("  OS  ${snap.os.platform}/${snap.os.arch} ${snap.os.release}")
        Out.println("")
        Out.println("  Tools")
        if (snap.tools.isEmpty()) {
            Out.println("  none detected")
        } else {
            for (t in snap.tools) {
                Out.println("  ✓ ${t.tool.padEnd(8)} ${t.version}  ${t.resolvedFrom}")
            }
        }
        Out.println("")
        Out.println("  PATH (${snap.path.size} entries)")
        snap.path.take(12).forEachIndexed { i, p ->
            Out.println("  ${(i + 1).toString().padStart(2)}  $p")
        }
        if (snap.path.size > 12) {
            Out.println("  … ${snap.path.size - 12} more")
        }
        if (snap.globals.isNotEmpty()) {
            Out.println("")
            Out.println("  Globals")
            for ((eco, pkgs) in snap.globals) {
                Out.println("  $eco: ${pkgs.size} packages")
            }
        } else if (!s.globals) {
            Out.println("")
            Out.println("  Globals omitted — pass --globals to include the package inventory.")
        }
        Out.println("")
        Out.println("  Share with:  envdoctor snapshot --token   ·   compare with:  envdoctor snapshot-diff <a> <b>")
        return 0
    }

    /** Resolve a positional arg that may be a token string or a file path. */
    private fun loadSnapshot(rootDir: Path, arg: String): Snapshot.RuntimeSnapshot {
        if (arg.trim().startsWith("envd1:")) {
            return Snapshot.decodeToken(arg)
        }
        val file = rootDir.resolve(arg)
        if (!file.exists()) {
            throw IllegalArgumentException("Not a snapshot token, and file not found: $arg")
        }
        return Snapshot.parseSnapshotJson(Files.readString(file))
    }

    fun runSnapshotDiff(args: Array<String>): Int {
        val s = parseArgs(args, 1)
        val aArg = s.pos.getOrElse(0) { "" }
        val bArg = s.pos.getOrElse(1) { "" }
        val a: Snapshot.RuntimeSnapshot
        val b: Snapshot.RuntimeSnapshot
        try {
            a = loadSnapshot(root(s.dir), aArg)
            b = loadSnapshot(root(s.dir), bArg)
        } catch (e: IllegalArgumentException) {
            Out.eprintln("error ${e.message}")
            return 2
        }

        val diff = Snapshot.compare(a, b)

        if (s.json) {
            Out.println(Json.pretty(Snapshot.diffToJson(diff)))
            return if (diff.equivalent) 0 else 1
        }

        val title = "RUNTIME DIFF"
        Out.println(title)
        Out.println("=".repeat(title.length * 2))
        Out.println("")
        Out.println("  A → B")
        Out.println("")
        if (diff.osStatus == Snapshot.Status.same) {
            Out.println("  ✓ OS  ${diff.osA}")
        } else {
            Out.println("  ≠ OS  ${diff.osA} → ${diff.osB}")
        }
        Out.println("")
        Out.println("  Tools")
        for (t in diff.tools) {
            when (t.status) {
                Snapshot.Status.same -> Out.println("  ✓ ${t.name.padEnd(8)} ${t.a ?: ""}")
                Snapshot.Status.different -> Out.println("  ≠ ${t.name.padEnd(8)} ${t.a} → ${t.b}")
                Snapshot.Status.onlyA -> Out.println("  ! ${t.name.padEnd(8)} missing in B (A: ${t.a})")
                Snapshot.Status.onlyB -> Out.println("  ! ${t.name.padEnd(8)} missing in A (B: ${t.b})")
            }
        }
        if (diff.pathReordered || diff.pathOnlyA.isNotEmpty() || diff.pathOnlyB.isNotEmpty()) {
            Out.println("")
            Out.println("  PATH")
            if (diff.pathReordered) Out.println("  ≠ same entries, different order")
            for (p in diff.pathOnlyA) Out.println("  ! only in A: $p")
            for (p in diff.pathOnlyB) Out.println("  ! only in B: $p")
        }
        if (diff.globals.isNotEmpty()) {
            Out.println("")
            Out.println("  Globals")
            for (g in diff.globals) {
                val label = "${g.ecosystem}:${g.name}"
                when (g.status) {
                    Snapshot.Status.different -> Out.println("  ≠ $label  ${g.a} → ${g.b}")
                    Snapshot.Status.onlyA -> Out.println("  ! $label missing in B")
                    Snapshot.Status.onlyB -> Out.println("  ! $label missing in A")
                    Snapshot.Status.same -> Unit
                }
            }
        }
        Out.println("")
        if (diff.equivalent) {
            Out.println("  ✓ runtimes are equivalent")
        } else {
            Out.println("  ✗ runtime drift detected")
        }
        return if (diff.equivalent) 0 else 1
    }
}
