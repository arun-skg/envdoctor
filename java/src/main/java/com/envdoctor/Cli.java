package com.envdoctor;

import java.nio.file.Path;
import java.util.List;

/** Command-line entry point for the native Java envdoctor. */
public final class Cli {

    private Cli() {}

    public static void main(String[] args) {
        System.exit(run(args));
    }

    public static int run(String[] args) {
        String dir = ".";
        boolean strict = false;
        int start = (args.length > 0 && args[0].equals("scan")) ? 1 : 0;
        for (int i = start; i < args.length; i++) {
            String a = args[i];
            if ((a.equals("-d") || a.equals("--dir")) && i + 1 < args.length) {
                dir = args[++i];
            } else if (a.startsWith("--dir=")) {
                dir = a.substring("--dir=".length());
            } else if (a.equals("--strict")) {
                strict = true;
            }
        }

        List<Scanner.Finding> findings = Scanner.scan(Path.of(dir).toAbsolutePath().normalize());
        List<Scanner.Finding> errors = findings.stream().filter(f -> f.severity().equals("error")).toList();
        List<Scanner.Finding> warnings = findings.stream().filter(f -> f.severity().equals("warning")).toList();

        System.out.println("ENVIRONMENT AUDIT");
        System.out.println("=".repeat(40));
        if (findings.isEmpty()) {
            System.out.println("\nNo issues found.");
            return 0;
        }
        if (!errors.isEmpty()) {
            System.out.println("\nErrors");
            for (Scanner.Finding f : errors) {
                System.out.printf("  x %s %s:%d  %s%n", f.name(), f.file(), f.line(), f.message());
            }
        }
        if (!warnings.isEmpty()) {
            System.out.println("\nWarnings");
            for (Scanner.Finding f : warnings) {
                System.out.printf("  ! %s %s:%d  %s%n", f.name(), f.file(), f.line(), f.message());
            }
        }
        System.out.printf("%nSummary: %d error(s), %d warning(s)%n", errors.size(), warnings.size());

        return (!errors.isEmpty() || (strict && !warnings.isEmpty())) ? 1 : 0;
    }
}
