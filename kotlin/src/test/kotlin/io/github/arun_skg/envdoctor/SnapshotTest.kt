package io.github.arun_skg.envdoctor

import kotlin.io.path.readText
import java.nio.file.Files
import java.nio.file.Path
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

class SnapshotTest {

    private fun snapshot(
        tools: List<Snapshot.ToolVersion> = listOf(
            Snapshot.ToolVersion("git", "2.44.0", "/usr/bin"),
            Snapshot.ToolVersion("node", "20.11.1", "/usr/local/bin"),
        ),
        path: List<String> = listOf("/usr/local/bin", "/usr/bin", "~/bin"),
        globals: Map<String, List<Snapshot.GlobalPackage>> = emptyMap(),
        envFlagNames: List<String> = listOf("HOME", "LANG", "PATH"),
    ) = Snapshot.RuntimeSnapshot(
        schema = Snapshot.SNAPSHOT_SCHEMA,
        capturedAt = "2024-01-01T00:00:00Z",
        os = Snapshot.OsInfo("darwin", "arm64", "23.3.0"),
        tools = tools,
        path = path,
        globals = globals,
        envFlagNames = envFlagNames,
    )

    @Test
    fun tokenRoundTripPreservesSnapshot() {
        val original = snapshot(globals = mapOf("npm" to listOf(Snapshot.GlobalPackage("typescript", "5.4.0"))))
        val decoded = Snapshot.decodeToken(Snapshot.encodeToken(original))
        assertEquals(original, decoded)
    }

    @Test
    fun decodeRejectsNonToken() {
        val e = assertThrows(IllegalArgumentException::class.java) {
            Snapshot.decodeToken("not-a-token")
        }
        assertTrue(e.message!!.contains("envd1:"))
    }

    @Test
    fun decodeRejectsCorruptToken() {
        val e = assertThrows(IllegalArgumentException::class.java) {
            Snapshot.decodeToken("envd1:####garbage####")
        }
        assertTrue(e.message!!.contains("Corrupt"))
    }

    @Test
    fun decodeRejectsNewerSchema() {
        val newer = snapshot().copy(schema = Snapshot.SNAPSHOT_SCHEMA + 1)
        val json = io.github.arun_skg.envdoctor.utils.Json.compact(Snapshot.toJson(newer))
        val bos = java.io.ByteArrayOutputStream()
        java.util.zip.GZIPOutputStream(bos).use { it.write(json.toByteArray()) }
        val token = "envd1:" + java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bos.toByteArray())
        val e = assertThrows(IllegalArgumentException::class.java) {
            Snapshot.decodeToken(token)
        }
        assertTrue(e.message!!.contains("newer"))
    }

    @Test
    fun identicalSnapshotsAreEquivalent() {
        val diff = Snapshot.compare(snapshot(), snapshot())
        assertTrue(diff.equivalent)
        assertEquals(Snapshot.Status.same, diff.osStatus)
        assertTrue(diff.tools.all { it.status == Snapshot.Status.same })
    }

    @Test
    fun detectsToolVersionDrift() {
        val b = snapshot(
            tools = listOf(
                Snapshot.ToolVersion("git", "2.44.0", "/usr/bin"),
                Snapshot.ToolVersion("node", "22.0.0", "/usr/local/bin"),
            ),
        )
        val diff = Snapshot.compare(snapshot(), b)
        assertFalse(diff.equivalent)
        val node = diff.tools.first { it.name == "node" }
        assertEquals(Snapshot.Status.different, node.status)
        assertEquals("20.11.1", node.a)
        assertEquals("22.0.0", node.b)
    }

    @Test
    fun detectsMissingToolAndPathDrift() {
        val b = snapshot(
            tools = listOf(Snapshot.ToolVersion("git", "2.44.0", "/usr/bin")),
            path = listOf("/usr/bin", "/opt/bin"),
        )
        val diff = Snapshot.compare(snapshot(), b)
        assertFalse(diff.equivalent)
        assertEquals(Snapshot.Status.onlyA, diff.tools.first { it.name == "node" }.status)
        assertEquals(listOf("/usr/local/bin", "~/bin"), diff.pathOnlyA)
        assertEquals(listOf("/opt/bin"), diff.pathOnlyB)
        assertFalse(diff.pathReordered)
    }

    @Test
    fun detectsPathReorderOnly() {
        val b = snapshot(path = listOf("/usr/bin", "/usr/local/bin", "~/bin"))
        val diff = Snapshot.compare(snapshot(), b)
        assertFalse(diff.equivalent)
        assertTrue(diff.pathReordered)
        assertTrue(diff.pathOnlyA.isEmpty() && diff.pathOnlyB.isEmpty())
    }

    @Test
    fun detectsGlobalPackageDrift() {
        val a = snapshot(globals = mapOf("npm" to listOf(Snapshot.GlobalPackage("tsx", "4.0.0"))))
        val b = snapshot(globals = mapOf("npm" to listOf(Snapshot.GlobalPackage("tsx", "5.0.0"))))
        val diff = Snapshot.compare(a, b)
        assertFalse(diff.equivalent)
        val g = diff.globals.first()
        assertEquals("npm", g.ecosystem)
        assertEquals("tsx", g.name)
        assertEquals(Snapshot.Status.different, g.status)
    }

    @Test
    fun secretEnvNamesNeverCaptured() {
        val names = Snapshot.collectEnvFlagNames(
            mapOf(
                "HOME" to "/home/u",
                "AWS_SECRET_ACCESS_KEY" to "leak-me-not",
                "API_TOKEN" to "leak-me-not",
                "EDITOR" to "vim",
            ),
        )
        assertEquals(listOf("EDITOR", "HOME"), names)
    }

    @Test
    fun collapseHomeHidesUsernames() {
        val home = System.getProperty("user.home")
        assertEquals("~/bin", Snapshot.collapseHome("$home/bin"))
        assertEquals("/usr/local/bin", Snapshot.collapseHome("/usr/local/bin"))
    }

    @Test
    fun snapshotDiffViaCliFilesAndTokens(@TempDir dir: Path) {
        val a = snapshot()
        val b = snapshot(path = listOf("/different"))
        val jsonA = io.github.arun_skg.envdoctor.utils.Json.pretty(Snapshot.toJson(a)) + "\n"
        Files.writeString(dir.resolve("a.json"), jsonA)

        // equivalent against itself via file
        assertEquals(0, Cli.runSnapshotDiff(arrayOf("snapshot-diff", "-d", dir.toString(), "a.json", "a.json")))
        // drift via token vs file
        val token = Snapshot.encodeToken(b)
        assertEquals(
            1,
            Cli.runSnapshotDiff(arrayOf("snapshot-diff", "-d", dir.toString(), "a.json", token)),
        )
        // usage error for missing file
        assertEquals(
            2,
            Cli.runSnapshotDiff(arrayOf("snapshot-diff", "-d", dir.toString(), "a.json", "missing.json")),
        )
        // round-trip through parseSnapshotJson
        assertEquals(a, Snapshot.parseSnapshotJson(dir.resolve("a.json").readText()))
    }
}
