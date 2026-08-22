package com.envdoctor;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
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
}
