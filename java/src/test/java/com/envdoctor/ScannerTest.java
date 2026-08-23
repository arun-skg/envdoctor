package com.envdoctor;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class ScannerTest {

    @Test
    void detectsUsageAndIgnoresComments() {
        String src = """
            public class Config {
              // System.getenv("COMMENTED")
              String db = System.getenv("DB_URL");
              /* System.getenv("BLOCK_IGNORED") */
              String port = System.getenv("PORT");
            }
            """;
        Set<String> names = new TreeSet<>(Scanner.scanSource(src).keySet());
        assertEquals(Set.of("DB_URL", "PORT"), names);
        assertFalse(names.contains("COMMENTED"));
        assertFalse(names.contains("BLOCK_IGNORED"));
    }

    @Test
    void reconcilesMissingAndUnused(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve(".env"), "DB_URL=x\nUNUSED_KEY=1\n");
        Files.writeString(dir.resolve("App.java"),
                "class App { void m(){ System.getenv(\"DB_URL\"); System.getenv(\"NEW_FLAG\"); } }");

        List<Scanner.Finding> findings = Scanner.scan(dir);
        Set<String> errors = new TreeSet<>();
        Set<String> warnings = new TreeSet<>();
        for (Scanner.Finding f : findings) {
            (f.severity().equals("error") ? errors : warnings).add(f.name());
        }
        assertTrue(errors.contains("NEW_FLAG"));
        assertTrue(warnings.contains("UNUSED_KEY"));
        assertFalse(errors.contains("DB_URL"));
        assertFalse(warnings.contains("DB_URL"));
    }

    @Test
    void detectsDuplicatesAndPublicPrefix(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve(".env"),
                "DUP_KEY=1\nSINGLE_KEY=2\nDUP_KEY=3\n"
                        + "NEXT_PUBLIC_API_KEY=x\nPUBLIC_URL=y\nAPI_KEY=z\nPUBLIC_KEY=k\n");
        Files.writeString(dir.resolve("App.java"),
                "class App { void m(){ System.getenv(\"DUP_KEY\"); System.getenv(\"SINGLE_KEY\");"
                        + " System.getenv(\"NEXT_PUBLIC_API_KEY\"); System.getenv(\"PUBLIC_URL\");"
                        + " System.getenv(\"API_KEY\"); System.getenv(\"PUBLIC_KEY\"); } }");

        List<Scanner.Finding> findings = Scanner.scan(dir);
        Set<String> duplicates = new TreeSet<>();
        Set<String> publicPrefix = new TreeSet<>();
        String dupMessage = "";
        for (Scanner.Finding f : findings) {
            if (f.rule().equals("duplicates")) {
                duplicates.add(f.name());
                assertEquals("error", f.severity());
                if (f.name().equals("DUP_KEY")) {
                    dupMessage = f.message();
                }
            }
            if (f.rule().equals("public-prefix")) {
                publicPrefix.add(f.name());
                assertEquals("error", f.severity());
            }
        }
        assertTrue(duplicates.contains("DUP_KEY"));
        assertEquals("defined 2 times in the same file (lines 1, 3)", dupMessage);
        assertFalse(duplicates.contains("SINGLE_KEY"));

        assertTrue(publicPrefix.contains("NEXT_PUBLIC_API_KEY"));
        assertFalse(publicPrefix.contains("PUBLIC_URL"));
        assertFalse(publicPrefix.contains("API_KEY"));
        assertFalse(publicPrefix.contains("PUBLIC_KEY"));
    }

    @Test
    void duplicatedButUsedKeyNotReportedUnused(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve(".env"), "DUP_KEY=1\nDUP_KEY=2\n");
        Files.writeString(dir.resolve("App.java"),
                "class App { void m(){ System.getenv(\"DUP_KEY\"); } }");

        List<Scanner.Finding> findings = Scanner.scan(dir);
        boolean unused = findings.stream()
                .anyMatch(f -> f.rule().equals("unused") && f.name().equals("DUP_KEY"));
        boolean undefined = findings.stream()
                .anyMatch(f -> f.rule().equals("undefined-in-source") && f.name().equals("DUP_KEY"));
        assertFalse(unused);
        assertFalse(undefined);
    }

    private static Scanner.Finding find(List<Scanner.Finding> fs, String rule, String name) {
        return fs.stream().filter(f -> f.rule().equals(rule) && f.name().equals(name))
                .findFirst().orElse(null);
    }

    @Test
    void envLabelDerivation() {
        assertEquals("default", Scanner.envLabel(".env"));
        assertEquals("local", Scanner.envLabel(".env.local"));
        assertEquals("production", Scanner.envLabel(".env.production"));
        assertEquals("production", Scanner.envLabel(".env.production.local"));
        assertNull(Scanner.envLabel(".env.example"));
    }

    @Test
    void detectsWeakSecretAndTypoWithoutLeakingValues(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve(".env"),
                "API_KEY=changeme\nSTRONG_TOKEN=a7Kf93ZqL0\nDATABASE_URL=postgres://localhost\n");
        Files.writeString(dir.resolve("App.java"),
                "class App { void m(){ System.getenv(\"API_KEY\"); System.getenv(\"STRONG_TOKEN\");"
                        + " System.getenv(\"DATABASE_URL\"); System.getenv(\"DATBASE_URL\"); } }");

        List<Scanner.Finding> f = Scanner.scan(dir);
        Scanner.Finding weak = find(f, "weak-secret", "API_KEY");
        assertNotNull(weak);
        assertEquals("warning", weak.severity());
        assertNull(find(f, "weak-secret", "STRONG_TOKEN"));

        Scanner.Finding typo = find(f, "typo", "DATBASE_URL");
        assertNotNull(typo);
        assertEquals("\"DATBASE_URL\" is not defined; did you mean \"DATABASE_URL\"?", typo.message());
        assertNotNull(find(f, "undefined-in-source", "DATBASE_URL"));

        for (Scanner.Finding x : f) {
            assertFalse(x.message().contains("changeme"));
            assertFalse(x.message().contains("postgres"));
            assertFalse(x.message().contains("a7Kf93ZqL0"));
        }
    }

    @Test
    void detectsTypeMismatchAndEnvironmentDiff(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve(".env"), "PORT=8080\nONLY_DEFAULT=1\n");
        Files.writeString(dir.resolve(".env.production"), "PORT=high\n");
        Files.writeString(dir.resolve("App.java"),
                "class App { void m(){ System.getenv(\"PORT\"); System.getenv(\"ONLY_DEFAULT\"); } }");

        List<Scanner.Finding> f = Scanner.scan(dir);
        Scanner.Finding tm = find(f, "type-mismatch", "PORT");
        assertNotNull(tm);
        assertEquals("error", tm.severity());

        Scanner.Finding ed = find(f, "environment-diff", "ONLY_DEFAULT");
        assertNotNull(ed);
        assertEquals("defined in default but missing in production", ed.message());
    }

    @Test
    void twoIntegersAcrossEnvsIsNotMismatch(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve(".env"), "PORT=8080\n");
        Files.writeString(dir.resolve(".env.production"), "PORT=9090\n");
        Files.writeString(dir.resolve("App.java"),
                "class App { void m(){ System.getenv(\"PORT\"); } }");

        List<Scanner.Finding> f = Scanner.scan(dir);
        assertNull(find(f, "type-mismatch", "PORT"));
    }

    @Test
    void jsonShapeHasExactKeysAndNoValues(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve(".env"), "API_KEY=changeme\nPORT=8080\n");
        Files.writeString(dir.resolve(".env.production"), "PORT=high\n");
        Files.writeString(dir.resolve("App.java"),
                "class App { void m(){ System.getenv(\"API_KEY\"); System.getenv(\"PORT\"); } }");

        String json = Cli.toJson(Scanner.scan(dir));
        assertTrue(json.startsWith("[") && json.endsWith("]"));
        for (String key : List.of("\"rule\":", "\"severity\":", "\"name\":",
                "\"message\":", "\"file\":", "\"line\":")) {
            assertTrue(json.contains(key), "missing key " + key);
        }
        assertFalse(json.contains("changeme"));
        assertFalse(json.contains("8080"));
        assertFalse(json.contains("high"));
    }

    @Test
    void findingsOrderErrorsBeforeWarnings(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve(".env"), "PORT=8080\nUNUSED_KEY=1\n");
        Files.writeString(dir.resolve(".env.production"), "PORT=high\n");
        Files.writeString(dir.resolve("App.java"),
                "class App { void m(){ System.getenv(\"PORT\"); System.getenv(\"MISSING\"); } }");

        List<Scanner.Finding> f = Scanner.scan(dir);
        int lastError = -1;
        int firstWarning = Integer.MAX_VALUE;
        for (int i = 0; i < f.size(); i++) {
            if (f.get(i).severity().equals("error")) {
                lastError = i;
            } else if (firstWarning == Integer.MAX_VALUE) {
                firstWarning = i;
            }
        }
        assertTrue(lastError < firstWarning);
    }

    @Test
    void diffAndSync(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve(".env"), "A=1\nB=2\n");
        Files.writeString(dir.resolve(".env.production"), "A=9\n");

        Scanner.Diff d = Scanner.diffLabels(dir, "default", "production");
        assertEquals(List.of("B"), d.onlyInA());
        assertTrue(d.onlyInB().isEmpty());
        assertEquals(List.of("A"), d.common());

        assertEquals(List.of("B"), Scanner.syncLabels(dir, "default", "production", true));
        assertFalse(Files.readString(dir.resolve(".env.production")).contains("B="));

        assertEquals(List.of("B"), Scanner.syncLabels(dir, "default", "production", false));
        String prod = Files.readString(dir.resolve(".env.production"));
        assertTrue(prod.contains("B=\n") && prod.contains("A=9") && !prod.contains("B=2"));
    }
}
