package io.github.arun_skg.envdoctor

import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.readText
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

class ScannerTest {

    private fun find(fs: List<Scanner.Finding>, rule: String, name: String): Scanner.Finding? =
        fs.firstOrNull { it.rule == rule && it.name == name }

    @Test
    fun detectsUsageAndIgnoresComments() {
        val src = """
            class Config {
              // System.getenv("COMMENTED")
              val db = System.getenv("DB_URL")
              /* System.getenv("BLOCK_IGNORED") */
              val port = System.getenv("PORT")
            }
        """.trimIndent()
        val names = Scanner.scanSource(src).keys.toSortedSet()
        assertEquals(sortedSetOf("DB_URL", "PORT"), names)
        assertFalse(names.contains("COMMENTED"))
        assertFalse(names.contains("BLOCK_IGNORED"))
    }

    @Test
    fun scansKotlinAndJavaSources(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "DB_URL=x\nUNUSED_KEY=1\n")
        Files.writeString(
            dir.resolve("App.kt"),
            "class App { fun m() { System.getenv(\"DB_URL\"); System.getenv(\"NEW_FLAG\") } }",
        )

        val findings = Scanner.scan(dir)
        val errors = findings.filter { it.severity == "error" }.map { it.name }.toSet()
        val warnings = findings.filter { it.severity == "warning" }.map { it.name }.toSet()
        assertTrue(errors.contains("NEW_FLAG"))
        assertTrue(warnings.contains("UNUSED_KEY"))
        assertFalse(errors.contains("DB_URL"))
        assertFalse(warnings.contains("DB_URL"))
    }

    @Test
    fun detectsDuplicatesAndPublicPrefix(@TempDir dir: Path) {
        Files.writeString(
            dir.resolve(".env"),
            "DUP_KEY=1\nSINGLE_KEY=2\nDUP_KEY=3\n" +
                "NEXT_PUBLIC_API_KEY=x\nPUBLIC_URL=y\nAPI_KEY=z\nPUBLIC_KEY=k\n",
        )
        Files.writeString(
            dir.resolve("App.kt"),
            "class App { fun m() { System.getenv(\"DUP_KEY\"); System.getenv(\"SINGLE_KEY\");" +
                " System.getenv(\"NEXT_PUBLIC_API_KEY\"); System.getenv(\"PUBLIC_URL\");" +
                " System.getenv(\"API_KEY\"); System.getenv(\"PUBLIC_KEY\"); } }",
        )

        val findings = Scanner.scan(dir)
        val duplicates = findings.filter { it.rule == "duplicates" }
        assertTrue(duplicates.any { it.name == "DUP_KEY" })
        assertEquals(
            "defined 2 times in the same file (lines 1, 3)",
            duplicates.first { it.name == "DUP_KEY" }.message,
        )
        assertFalse(duplicates.any { it.name == "SINGLE_KEY" })

        val publicPrefix = findings.filter { it.rule == "public-prefix" }.map { it.name }.toSet()
        assertTrue(publicPrefix.contains("NEXT_PUBLIC_API_KEY"))
        assertFalse(publicPrefix.contains("PUBLIC_URL"))
        assertFalse(publicPrefix.contains("API_KEY"))
        assertFalse(publicPrefix.contains("PUBLIC_KEY"))
    }

    @Test
    fun duplicatedButUsedKeyNotReportedUnused(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "DUP_KEY=1\nDUP_KEY=2\n")
        Files.writeString(dir.resolve("App.kt"), "class App { fun m() { System.getenv(\"DUP_KEY\"); } }")

        val findings = Scanner.scan(dir)
        assertFalse(findings.any { it.rule == "unused" && it.name == "DUP_KEY" })
        assertFalse(findings.any { it.rule == "undefined-in-source" && it.name == "DUP_KEY" })
    }

    @Test
    fun envLabelDerivation() {
        assertEquals("default", Scanner.envLabel(".env"))
        assertEquals("local", Scanner.envLabel(".env.local"))
        assertEquals("production", Scanner.envLabel(".env.production"))
        assertEquals("production", Scanner.envLabel(".env.production.local"))
        assertNull(Scanner.envLabel(".env.example"))
    }

    @Test
    fun detectsWeakSecretAndTypoWithoutLeakingValues(@TempDir dir: Path) {
        Files.writeString(
            dir.resolve(".env"),
            "API_KEY=changeme\nSTRONG_TOKEN=a7Kf93ZqL0\nDATABASE_URL=postgres://localhost\n",
        )
        Files.writeString(
            dir.resolve("App.kt"),
            "class App { fun m() { System.getenv(\"API_KEY\"); System.getenv(\"STRONG_TOKEN\");" +
                " System.getenv(\"DATABASE_URL\"); System.getenv(\"DATBASE_URL\"); } }",
        )

        val f = Scanner.scan(dir)
        val weak = find(f, "weak-secret", "API_KEY")
        assertNotNull(weak)
        assertEquals("warning", weak!!.severity)
        assertNull(find(f, "weak-secret", "STRONG_TOKEN"))

        val typo = find(f, "typo", "DATBASE_URL")
        assertNotNull(typo)
        assertEquals("\"DATBASE_URL\" is not defined; did you mean \"DATABASE_URL\"?", typo!!.message)
        assertNotNull(find(f, "undefined-in-source", "DATBASE_URL"))

        for (x in f) {
            assertFalse(x.message.contains("changeme"))
            assertFalse(x.message.contains("postgres"))
            assertFalse(x.message.contains("a7Kf93ZqL0"))
        }
    }

    @Test
    fun detectsTypeMismatchAndEnvironmentDiff(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "PORT=8080\nONLY_DEFAULT=1\n")
        Files.writeString(dir.resolve(".env.production"), "PORT=high\n")
        Files.writeString(
            dir.resolve("App.kt"),
            "class App { fun m() { System.getenv(\"PORT\"); System.getenv(\"ONLY_DEFAULT\"); } }",
        )

        val f = Scanner.scan(dir)
        val tm = find(f, "type-mismatch", "PORT")
        assertNotNull(tm)
        assertEquals("error", tm!!.severity)

        val ed = find(f, "environment-diff", "ONLY_DEFAULT")
        assertNotNull(ed)
        assertEquals("defined in default but missing in production", ed!!.message)
    }

    @Test
    fun twoIntegersAcrossEnvsIsNotMismatch(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "PORT=8080\n")
        Files.writeString(dir.resolve(".env.production"), "PORT=9090\n")
        Files.writeString(dir.resolve("App.kt"), "class App { fun m() { System.getenv(\"PORT\"); } }")

        val f = Scanner.scan(dir)
        assertNull(find(f, "type-mismatch", "PORT"))
    }

    @Test
    fun jsonShapeHasExactKeysAndNoValues(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "API_KEY=changeme\nPORT=8080\n")
        Files.writeString(dir.resolve(".env.production"), "PORT=high\n")
        Files.writeString(
            dir.resolve("App.kt"),
            "class App { fun m() { System.getenv(\"API_KEY\"); System.getenv(\"PORT\"); } }",
        )

        val json = Cli.findingsToJson(Scanner.scan(dir))
        assertTrue(json.startsWith("[") && json.endsWith("]"))
        for (key in listOf("\"rule\":", "\"severity\":", "\"name\":", "\"message\":", "\"file\":", "\"line\":")) {
            assertTrue(json.contains(key), "missing key $key")
        }
        assertFalse(json.contains("changeme"))
        assertFalse(json.contains("8080"))
        assertFalse(json.contains("high"))
    }

    @Test
    fun findingsOrderErrorsBeforeWarnings(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "PORT=8080\nUNUSED_KEY=1\n")
        Files.writeString(dir.resolve(".env.production"), "PORT=high\n")
        Files.writeString(
            dir.resolve("App.kt"),
            "class App { fun m() { System.getenv(\"PORT\"); System.getenv(\"MISSING\"); } }",
        )

        val f = Scanner.scan(dir)
        val lastError = f.indexOfLast { it.severity == "error" }
        val firstWarning = f.indexOfFirst { it.severity == "warning" }
        assertTrue(lastError >= 0 && firstWarning >= 0)
        assertTrue(lastError < firstWarning)
    }

    @Test
    fun scansComposeActionsAndKubernetes(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "DB_URL=postgres://localhost\n")
        Files.writeString(
            dir.resolve("docker-compose.yml"),
            "services:\n  app:\n    environment:\n" +
                "      - SECRET=\${COMPOSE_SECRET}\n      - URL=\${DB_URL}\n" +
                "      - LIT=\$\$NOT_A_VAR\n",
        )
        val wf = dir.resolve(".github").resolve("workflows")
        Files.createDirectories(wf)
        Files.writeString(
            wf.resolve("ci.yml"),
            "jobs:\n  deploy:\n    steps:\n" +
                "      - run: deploy --key \${{ secrets.DEPLOY_KEY }} --region \${{ vars.REGION }}\n",
        )

        val f = Scanner.scan(dir)
        val secret = find(f, "undefined-in-source", "COMPOSE_SECRET")
        assertNotNull(secret)
        assertEquals("referenced but not defined in any environment file", secret!!.message)
        assertNotNull(find(f, "undefined-in-source", "DEPLOY_KEY"))
        assertNotNull(find(f, "undefined-in-source", "REGION"))
        assertNull(find(f, "undefined-in-source", "NOT_A_VAR"))
        assertNull(find(f, "unused", "DB_URL"))
        for (x in f) {
            assertFalse(x.message.contains("postgres"))
        }
    }

    @Test
    fun scansKubernetesManifest(@TempDir dir: Path) {
        Files.writeString(
            dir.resolve("deploy.yaml"),
            "apiVersion: apps/v1\nkind: Deployment\nspec:\n  value: \${K8S_VAR}\n",
        )

        val f = Scanner.scan(dir)
        assertNotNull(find(f, "undefined-in-source", "K8S_VAR"))
    }

    @Test
    fun envdoctorignoreSuppressesVariables(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "DB_URL=x\nUNUSED_KEY=1\nLEGACY_TOKEN=short\n")
        Files.writeString(dir.resolve(".envdoctorignore"), "# never report legacy vars\nLEGACY_*\nUNUSED_KEY\n")
        Files.writeString(dir.resolve("App.kt"), "class App { fun m() { System.getenv(\"DB_URL\"); } }")

        val f = Scanner.scan(dir)
        assertTrue(f.none { it.name == "UNUSED_KEY" })
        assertTrue(f.none { it.name == "LEGACY_TOKEN" })
        assertTrue(f.none { it.name == "DB_URL" })
    }

    @Test
    fun generatesInitAndFix(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "DB_URL=secretvalue\n")
        Files.writeString(dir.resolve("App.kt"), "class App { fun m() { System.getenv(\"PORT\"); } }")

        val (exampleContent, mdContent) = Scanner.generate(dir)
        assertEquals(
            "# Generated by envdoctor. Fill in values; do not commit secrets.\nDB_URL=\nPORT=\n",
            exampleContent,
        )
        assertTrue(mdContent.contains("| DB_URL | yes | no |"))
        assertTrue(mdContent.contains("| PORT | no | yes |"))
        assertFalse(exampleContent.contains("secretvalue"))
        assertFalse(mdContent.contains("secretvalue"))

        val example = dir.resolve(".env.example")
        val doc = dir.resolve("ENVIRONMENT.md")

        // init creates both files
        assertEquals(0, Cli.runInit(arrayOf("init", "-d", dir.toString())))
        assertTrue(Files.exists(example) && Files.exists(doc))
        assertEquals(exampleContent, example.readText())

        // init again without --force skips (does not overwrite tampered content)
        Files.writeString(example, "TAMPER\n")
        assertEquals(0, Cli.runInit(arrayOf("init", "-d", dir.toString())))
        assertEquals("TAMPER\n", example.readText())

        // init --force rewrites
        assertEquals(0, Cli.runInit(arrayOf("init", "-d", dir.toString(), "--force")))
        assertEquals(exampleContent, example.readText())

        // fix always rewrites
        Files.writeString(example, "TAMPER\n")
        assertEquals(0, Cli.runFix(arrayOf("fix", "-d", dir.toString())))
        assertEquals(exampleContent, example.readText())
        assertTrue(doc.readText().contains("| DB_URL | yes | no |"))
    }

    @Test
    fun diffAndSync(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "A=1\nB=2\n")
        Files.writeString(dir.resolve(".env.production"), "A=9\n")

        val d = Scanner.diffLabels(dir, "default", "production")
        assertEquals(listOf("B"), d.onlyInA)
        assertTrue(d.onlyInB.isEmpty())
        assertEquals(listOf("A"), d.common)

        assertEquals(listOf("B"), Scanner.syncLabels(dir, "default", "production", true))
        assertFalse(dir.resolve(".env.production").readText().contains("B="))

        assertEquals(listOf("B"), Scanner.syncLabels(dir, "default", "production", false))
        val prod = dir.resolve(".env.production").readText()
        assertTrue(prod.contains("B=\n") && prod.contains("A=9") && !prod.contains("B=2"))
    }

    @Test
    fun schemaValidation(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "PORT=99999\nLEVEL=verbose\nAPI=ftp://x\nGOOD=info\n")
        Files.writeString(
            dir.resolve("envdoctor.schema.json"),
            "{\"PORT\":{\"type\":\"integer\",\"max\":65535},\"LEVEL\":{\"enum\":[\"debug\",\"info\"]}," +
                "\"API\":{\"type\":\"url\"},\"MISSING\":{\"type\":\"string\"},\"GOOD\":{\"enum\":[\"info\",\"warn\"]}}",
        )
        val sf = Scanner.scan(dir)
            .filter { it.rule == "schema-validation" }
            .associate { it.name to it.message }
        assertEquals("value exceeds the maximum", sf["PORT"])
        assertEquals("value is not one of the allowed values", sf["LEVEL"])
        assertEquals("value does not match schema type url", sf["API"])
        assertEquals("required by schema but not defined", sf["MISSING"])
        assertFalse(sf.containsKey("GOOD"))
    }

    @Test
    fun scanExitCodeReflectsFindings(@TempDir dir: Path) {
        Files.writeString(dir.resolve(".env"), "DB_URL=x\n")
        Files.writeString(dir.resolve("App.kt"), "class App { fun m() { System.getenv(\"DB_URL\"); } }")
        assertEquals(0, Cli.runScan(arrayOf("scan", "-d", dir.toString(), "--no-color", "--json")))

        Files.writeString(dir.resolve("App.kt"), "class App { fun m() { System.getenv(\"MISSING_VAR\"); } }")
        assertEquals(1, Cli.runScan(arrayOf("scan", "-d", dir.toString(), "--json")))
    }
}
