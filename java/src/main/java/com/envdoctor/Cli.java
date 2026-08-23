package com.envdoctor;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/** Command-line entry point for the native Java envdoctor. */
public final class Cli {

    private Cli() {}

    public static void main(String[] args) {
        System.exit(run(args));
    }

    public static int run(String[] args) {
        if (args.length > 0 && args[0].equals("diff")) {
            return runDiff(args);
        }
        if (args.length > 0 && args[0].equals("sync")) {
            return runSync(args);
        }
        if (args.length > 0 && args[0].equals("init")) {
            return runInit(args);
        }
        if (args.length > 0 && args[0].equals("fix")) {
            return runFix(args);
        }

        String dir = ".";
        boolean strict = false;
        boolean json = false;
        int start = (args.length > 0 && args[0].equals("scan")) ? 1 : 0;
        for (int i = start; i < args.length; i++) {
            String a = args[i];
            if ((a.equals("-d") || a.equals("--dir")) && i + 1 < args.length) {
                dir = args[++i];
            } else if (a.startsWith("--dir=")) {
                dir = a.substring("--dir=".length());
            } else if (a.equals("--strict")) {
                strict = true;
            } else if (a.equals("--json")) {
                json = true;
            }
        }

        List<Scanner.Finding> findings = Scanner.scan(Path.of(dir).toAbsolutePath().normalize());
        List<Scanner.Finding> errors = findings.stream().filter(f -> f.severity().equals("error")).toList();
        List<Scanner.Finding> warnings = findings.stream().filter(f -> f.severity().equals("warning")).toList();

        if (json) {
            System.out.println(toJson(findings));
            return (!errors.isEmpty() || (strict && !warnings.isEmpty())) ? 1 : 0;
        }

        System.out.println("ENVIRONMENT AUDIT");
        System.out.println("=".repeat(40));
        if (findings.isEmpty()) {
            System.out.println("\nNo issues found.");
            return 0;
        }
        if (!errors.isEmpty()) {
            System.out.println("\nErrors");
            for (Scanner.Finding f : errors) {
                System.out.println("  x " + f.name() + loc(f) + "  " + f.message());
            }
        }
        if (!warnings.isEmpty()) {
            System.out.println("\nWarnings");
            for (Scanner.Finding f : warnings) {
                System.out.println("  ! " + f.name() + loc(f) + "  " + f.message());
            }
        }
        System.out.printf("%nSummary: %d error(s), %d warning(s)%n", errors.size(), warnings.size());

        return (!errors.isEmpty() || (strict && !warnings.isEmpty())) ? 1 : 0;
    }

    private record Sub(List<String> pos, String dir, boolean dryRun, boolean json) {}

    private static Sub parseSub(String[] args) {
        List<String> pos = new ArrayList<>();
        String dir = ".";
        boolean dry = false;
        boolean json = false;
        for (int i = 1; i < args.length; i++) {
            String a = args[i];
            if ((a.equals("-d") || a.equals("--dir")) && i + 1 < args.length) {
                dir = args[++i];
            } else if (a.startsWith("--dir=")) {
                dir = a.substring("--dir=".length());
            } else if (a.equals("--dry-run")) {
                dry = true;
            } else if (a.equals("--json")) {
                json = true;
            } else {
                pos.add(a);
            }
        }
        return new Sub(pos, dir, dry, json);
    }

    private static String loc(Scanner.Finding f) {
        return (f.file() == null || f.line() == null) ? "" : " " + f.file() + ":" + f.line();
    }

    private static String jsonArray(List<String> xs) {
        StringBuilder b = new StringBuilder("[");
        for (int i = 0; i < xs.size(); i++) {
            if (i > 0) {
                b.append(',');
            }
            b.append(quote(xs.get(i)));
        }
        return b.append(']').toString();
    }

    static int runDiff(String[] args) {
        Sub s = parseSub(args);
        String a = s.pos.size() > 0 ? s.pos.get(0) : "";
        String b = s.pos.size() > 1 ? s.pos.get(1) : "";
        Scanner.Diff d = Scanner.diffLabels(Path.of(s.dir).toAbsolutePath().normalize(), a, b);
        if (s.json) {
            System.out.println("{\"a\":" + quote(a) + ",\"b\":" + quote(b)
                    + ",\"onlyInA\":" + jsonArray(d.onlyInA())
                    + ",\"onlyInB\":" + jsonArray(d.onlyInB())
                    + ",\"common\":" + jsonArray(d.common()) + "}");
            return 0;
        }
        System.out.println("ENVIRONMENT DIFF: " + a + " vs " + b);
        System.out.println("=".repeat(40));
        if (!d.onlyInA().isEmpty()) {
            System.out.println("Only in " + a + ":");
            for (String k : d.onlyInA()) {
                System.out.println("  + " + k);
            }
        }
        if (!d.onlyInB().isEmpty()) {
            System.out.println("Only in " + b + ":");
            for (String k : d.onlyInB()) {
                System.out.println("  + " + k);
            }
        }
        System.out.println("Common: " + d.common().size() + " variable(s)");
        return 0;
    }

    static int runSync(String[] args) {
        Sub s = parseSub(args);
        String from = s.pos.size() > 0 ? s.pos.get(0) : "";
        String to = s.pos.size() > 1 ? s.pos.get(1) : "";
        List<String> added = Scanner.syncLabels(Path.of(s.dir).toAbsolutePath().normalize(), from, to, s.dryRun);
        if (s.json) {
            System.out.println("{\"from\":" + quote(from) + ",\"to\":" + quote(to)
                    + ",\"added\":" + jsonArray(added)
                    + ",\"dryRun\":" + (s.dryRun ? "true" : "false") + "}");
            return 0;
        }
        if (added.isEmpty()) {
            System.out.println("Already in sync.");
            return 0;
        }
        String verb = s.dryRun ? "Would sync" : "Synced";
        System.out.printf("%s %d variable(s) from %s to %s:%n", verb, added.size(), from, to);
        for (String k : added) {
            System.out.println("  + " + k);
        }
        return 0;
    }

    private static String generateDir(String[] args) {
        String dir = ".";
        for (int i = 1; i < args.length; i++) {
            String a = args[i];
            if ((a.equals("-d") || a.equals("--dir")) && i + 1 < args.length) {
                dir = args[++i];
            } else if (a.startsWith("--dir=")) {
                dir = a.substring("--dir=".length());
            }
        }
        return dir;
    }

    private static boolean hasForce(String[] args) {
        for (String a : args) {
            if (a.equals("--force")) {
                return true;
            }
        }
        return false;
    }

    static int runInit(String[] args) {
        Path root = Path.of(generateDir(args)).toAbsolutePath().normalize();
        boolean force = hasForce(args);
        String[] out = Scanner.generate(root);
        String[][] files = {{".env.example", out[0]}, {"ENVIRONMENT.md", out[1]}};
        for (String[] f : files) {
            String name = f[0];
            Path target = root.resolve(name);
            if (java.nio.file.Files.exists(target) && !force) {
                System.out.println("skipped " + name + " (exists)");
                continue;
            }
            writeFile(target, f[1]);
            System.out.println((force ? "wrote " : "created ") + name);
        }
        return 0;
    }

    static int runFix(String[] args) {
        Path root = Path.of(generateDir(args)).toAbsolutePath().normalize();
        String[] out = Scanner.generate(root);
        String[][] files = {{".env.example", out[0]}, {"ENVIRONMENT.md", out[1]}};
        for (String[] f : files) {
            writeFile(root.resolve(f[0]), f[1]);
            System.out.println("wrote " + f[0]);
        }
        return 0;
    }

    private static void writeFile(Path target, String content) {
        try {
            java.nio.file.Files.writeString(target, content);
        } catch (java.io.IOException e) {
            throw new java.io.UncheckedIOException(e);
        }
    }

    /** Hand-built JSON array; keys exactly rule, severity, name, message, file, line. */
    public static String toJson(List<Scanner.Finding> findings) {
        StringBuilder sb = new StringBuilder();
        sb.append('[');
        for (int i = 0; i < findings.size(); i++) {
            Scanner.Finding f = findings.get(i);
            if (i > 0) {
                sb.append(',');
            }
            sb.append('{')
              .append("\"rule\":").append(quote(f.rule())).append(',')
              .append("\"severity\":").append(quote(f.severity())).append(',')
              .append("\"name\":").append(quote(f.name())).append(',')
              .append("\"message\":").append(quote(f.message())).append(',')
              .append("\"file\":").append(f.file() == null ? "null" : quote(f.file())).append(',')
              .append("\"line\":").append(f.line() == null ? "null" : f.line().toString())
              .append('}');
        }
        sb.append(']');
        return sb.toString();
    }

    private static String quote(String s) {
        StringBuilder b = new StringBuilder(s.length() + 2);
        b.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        b.append(String.format("\\u%04x", (int) c));
                    } else {
                        b.append(c);
                    }
            }
        }
        b.append('"');
        return b.toString();
    }
}
