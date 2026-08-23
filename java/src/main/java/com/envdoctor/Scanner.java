package com.envdoctor;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

/**
 * Core scanner: reconcile {@code System.getenv("X")} usage in Java source
 * against {@code .env} definitions. Local-first — no network, values never
 * printed.
 */
public final class Scanner {

    private static final Pattern USAGE =
            Pattern.compile("\\bSystem\\.getenv\\(\\s*\"([A-Za-z_]\\w*)\"");
    private static final Pattern LINE_COMMENT = Pattern.compile("//[^\\n]*");
    private static final Pattern BLOCK_COMMENT = Pattern.compile("(?s)/\\*.*?\\*/");
    private static final Pattern ENV_LINE =
            Pattern.compile("^\\s*(?:export\\s+)?([A-Za-z_]\\w*)\\s*=(.*)$", Pattern.DOTALL);
    private static final Pattern WEAK_VALUE = Pattern.compile(
            "^(changeme|change_me|placeholder|x{3,}|todo|secret|password|passwd|test"
                    + "|example|sample|dummy|your[_-].*|<.*>|\\$\\{.*\\})$",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern INTEGER = Pattern.compile("^-?\\d+$");
    private static final Pattern FLOAT = Pattern.compile("^-?\\d+\\.\\d+$");
    private static final Pattern BOOLEAN = Pattern.compile("^(?:true|false)$", Pattern.CASE_INSENSITIVE);
    private static final Pattern URL = Pattern.compile("^https?://");

    private Scanner() {}

    /** One occurrence of a variable inside a single dotenv file. */
    public record Occurrence(int line, String value) {}

    /** One reported issue. */
    public record Finding(String rule, String severity, String name, String message,
                          String file, int line) {}

    private static String blank(String s) {
        StringBuilder b = new StringBuilder(s.length());
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            b.append(c == '\n' ? '\n' : ' ');
        }
        return b.toString();
    }

    private static String stripNoise(String code) {
        code = replaceAll(BLOCK_COMMENT, code);
        code = replaceAll(LINE_COMMENT, code);
        return code;
    }

    private static String replaceAll(Pattern p, String code) {
        Matcher m = p.matcher(code);
        StringBuilder out = new StringBuilder();
        while (m.find()) {
            m.appendReplacement(out, Matcher.quoteReplacement(blank(m.group())));
        }
        m.appendTail(out);
        return out.toString();
    }

    /** Map of variable name to first origin for env usage in Java source. */
    public static Map<String, int[]> scanSource(String content) {
        String text = stripNoise(content);
        Map<String, int[]> used = new LinkedHashMap<>();
        Matcher m = USAGE.matcher(text);
        while (m.find()) {
            String name = m.group(1);
            if (used.containsKey(name)) {
                continue;
            }
            int line = (int) text.substring(0, m.start()).chars().filter(c -> c == '\n').count() + 1;
            used.put(name, new int[] {line});
        }
        return used;
    }

    private static final String[] PUBLIC_PREFIXES = {
        "NEXT_PUBLIC_", "VITE_", "REACT_APP_", "EXPO_PUBLIC_",
        "GATSBY_", "NUXT_PUBLIC_", "VUE_APP_", "PUBLIC_"
    };
    private static final Pattern SECRET_NAME = Pattern.compile(
            "SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|API_?KEY|ACCESS_?KEY|AUTH",
            Pattern.CASE_INSENSITIVE);

    private static boolean isPublicSecret(String name) {
        boolean hasPrefix = false;
        for (String p : PUBLIC_PREFIXES) {
            if (name.startsWith(p)) {
                hasPrefix = true;
                break;
            }
        }
        return hasPrefix && SECRET_NAME.matcher(name).find();
    }

    /**
     * Collect ALL occurrences per key within a single dotenv file, in order.
     * Each occurrence carries its line and value (text right of the first
     * {@code =}, trimmed, with one matching surrounding quote pair stripped).
     * Values are used ONLY for detection and are NEVER emitted in output.
     */
    public static Map<String, List<Occurrence>> parseEnv(String content) {
        Map<String, List<Occurrence>> defined = new LinkedHashMap<>();
        String[] lines = content.split("\n", -1);
        for (int i = 0; i < lines.length; i++) {
            String trimmed = lines[i].strip();
            if (trimmed.isEmpty() || trimmed.startsWith("#")) {
                continue;
            }
            Matcher m = ENV_LINE.matcher(lines[i]);
            if (m.find()) {
                String value = m.group(2).strip();
                if (value.length() >= 2) {
                    char a = value.charAt(0);
                    char b = value.charAt(value.length() - 1);
                    if ((a == '"' && b == '"') || (a == '\'' && b == '\'')) {
                        value = value.substring(1, value.length() - 1);
                    }
                }
                defined.computeIfAbsent(m.group(1), k -> new ArrayList<>())
                        .add(new Occurrence(i + 1, value));
            }
        }
        return defined;
    }

    /** Derive an env label from a .env filename; {@code null} for *.example. */
    public static String envLabel(String name) {
        if (name.endsWith(".example")) {
            return null;
        }
        if (name.equals(".env")) {
            return "default";
        }
        if (!name.startsWith(".env.")) {
            return null;
        }
        String x = name.substring(".env.".length());
        if (!x.equals("local") && x.endsWith(".local")) {
            x = x.substring(0, x.length() - ".local".length());
        }
        return x;
    }

    /** Infer a coarse type from a value string. */
    public static String inferType(String v) {
        if (v.isEmpty()) {
            return "empty";
        }
        if (INTEGER.matcher(v).matches()) {
            return "integer";
        }
        if (FLOAT.matcher(v).matches()) {
            return "float";
        }
        if (BOOLEAN.matcher(v).matches()) {
            return "boolean";
        }
        if (URL.matcher(v).find()) {
            return "url";
        }
        if ((v.startsWith("{") || v.startsWith("[")) && isJson(v)) {
            return "json";
        }
        return "string";
    }

    private static boolean isJson(String v) {
        // Minimal, dependency-free structural JSON validation.
        return parseJson(v, new int[] {0}) && true;
    }

    private static boolean parseJson(String s, int[] pos) {
        int[] p = pos;
        int n = s.length();
        skipWs(s, p);
        if (p[0] >= n) {
            return false;
        }
        boolean ok = parseValue(s, p);
        if (!ok) {
            return false;
        }
        skipWs(s, p);
        return p[0] == n;
    }

    private static boolean parseValue(String s, int[] p) {
        skipWs(s, p);
        if (p[0] >= s.length()) {
            return false;
        }
        char c = s.charAt(p[0]);
        switch (c) {
            case '{': return parseObject(s, p);
            case '[': return parseArray(s, p);
            case '"': return parseString(s, p);
            default:
                if (c == '-' || (c >= '0' && c <= '9')) {
                    return parseNumber(s, p);
                }
                if (s.startsWith("true", p[0])) { p[0] += 4; return true; }
                if (s.startsWith("false", p[0])) { p[0] += 5; return true; }
                if (s.startsWith("null", p[0])) { p[0] += 4; return true; }
                return false;
        }
    }

    private static boolean parseObject(String s, int[] p) {
        p[0]++; // {
        skipWs(s, p);
        if (p[0] < s.length() && s.charAt(p[0]) == '}') { p[0]++; return true; }
        while (true) {
            skipWs(s, p);
            if (p[0] >= s.length() || s.charAt(p[0]) != '"' || !parseString(s, p)) {
                return false;
            }
            skipWs(s, p);
            if (p[0] >= s.length() || s.charAt(p[0]) != ':') {
                return false;
            }
            p[0]++;
            if (!parseValue(s, p)) {
                return false;
            }
            skipWs(s, p);
            if (p[0] >= s.length()) {
                return false;
            }
            char c = s.charAt(p[0]);
            if (c == ',') { p[0]++; continue; }
            if (c == '}') { p[0]++; return true; }
            return false;
        }
    }

    private static boolean parseArray(String s, int[] p) {
        p[0]++; // [
        skipWs(s, p);
        if (p[0] < s.length() && s.charAt(p[0]) == ']') { p[0]++; return true; }
        while (true) {
            if (!parseValue(s, p)) {
                return false;
            }
            skipWs(s, p);
            if (p[0] >= s.length()) {
                return false;
            }
            char c = s.charAt(p[0]);
            if (c == ',') { p[0]++; continue; }
            if (c == ']') { p[0]++; return true; }
            return false;
        }
    }

    private static boolean parseString(String s, int[] p) {
        if (p[0] >= s.length() || s.charAt(p[0]) != '"') {
            return false;
        }
        p[0]++;
        while (p[0] < s.length()) {
            char c = s.charAt(p[0]++);
            if (c == '"') {
                return true;
            }
            if (c == '\\') {
                if (p[0] >= s.length()) {
                    return false;
                }
                char e = s.charAt(p[0]++);
                if (e == 'u') {
                    if (p[0] + 4 > s.length()) {
                        return false;
                    }
                    p[0] += 4;
                }
            }
        }
        return false;
    }

    private static boolean parseNumber(String s, int[] p) {
        int start = p[0];
        if (p[0] < s.length() && s.charAt(p[0]) == '-') {
            p[0]++;
        }
        while (p[0] < s.length() && "0123456789.eE+-".indexOf(s.charAt(p[0])) >= 0) {
            p[0]++;
        }
        if (p[0] == start) {
            return false;
        }
        try {
            Double.parseDouble(s.substring(start, p[0]));
            return true;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    private static void skipWs(String s, int[] p) {
        while (p[0] < s.length()) {
            char c = s.charAt(p[0]);
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                p[0]++;
            } else {
                break;
            }
        }
    }

    /** Compatibility group for a non-empty inferred type. */
    public static String typeGroup(String t) {
        return (t.equals("integer") || t.equals("float")) ? "numeric" : t;
    }

    private static boolean isWeakSecret(String v) {
        return v.isEmpty() || v.length() < 8 || WEAK_VALUE.matcher(v).matches();
    }

    /** Levenshtein edit distance between two strings. */
    public static int levenshtein(String a, String b) {
        int[] d = new int[b.length() + 1];
        for (int j = 0; j <= b.length(); j++) {
            d[j] = j;
        }
        for (int i = 1; i <= a.length(); i++) {
            int prev = d[0];
            d[0] = i;
            for (int j = 1; j <= b.length(); j++) {
                int tmp = d[j];
                int cost = a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1;
                d[j] = Math.min(Math.min(d[j] + 1, d[j - 1] + 1), prev + cost);
                prev = tmp;
            }
        }
        return d[b.length()];
    }

    private static String typoSuggestion(String u, TreeSet<String> defined) {
        String best = null;
        int bestDist = Integer.MAX_VALUE;
        for (String d : defined) {
            if (d.equals(u)) {
                continue;
            }
            int minLen = Math.min(u.length(), d.length());
            int thresh = minLen <= 4 ? 1 : 2;
            int dist = levenshtein(u, d);
            if (dist > thresh) {
                continue;
            }
            if (dist < bestDist) {
                bestDist = dist;
                best = d;
            }
        }
        return best;
    }

    /** Reconcile {@code .env} definitions against {@code .java} usage under root. */
    public static List<Finding> scan(Path root) {
        Map<String, String> definedFile = new LinkedHashMap<>();
        Map<String, Integer> definedLine = new LinkedHashMap<>();
        Map<String, String> definedValue = new LinkedHashMap<>();
        Map<String, String> usedFile = new LinkedHashMap<>();
        Map<String, Integer> usedLine = new LinkedHashMap<>();
        List<Finding> duplicates = new ArrayList<>();
        // var -> (label -> first value seen in that label)
        Map<String, Map<String, String>> labelsByVar = new LinkedHashMap<>();
        TreeSet<String> allLabels = new TreeSet<>();

        try (Stream<Path> walk = Files.walk(root)) {
            walk.filter(Files::isRegularFile)
                .filter(Scanner::notIgnored)
                .sorted()
                .forEach(path -> {
                    String name = path.getFileName().toString();
                    String label = envLabel(name);
                    boolean isEnv = label != null
                            && (name.equals(".env") || name.startsWith(".env."));
                    boolean isJava = name.endsWith(".java");
                    if (!isEnv && !isJava) {
                        return;
                    }
                    String content = read(path);
                    String rel = root.relativize(path).toString();
                    if (isEnv) {
                        allLabels.add(label);
                        parseEnv(content).forEach((k, occ) -> {
                            // First occurrence counts as the definition.
                            definedFile.putIfAbsent(k, rel);
                            definedLine.putIfAbsent(k, occ.get(0).line());
                            definedValue.putIfAbsent(k, occ.get(0).value());
                            labelsByVar.computeIfAbsent(k, x -> new LinkedHashMap<>())
                                    .putIfAbsent(label, occ.get(0).value());
                            if (occ.size() >= 2) {
                                String joined = occ.stream().map(o -> String.valueOf(o.line()))
                                        .collect(java.util.stream.Collectors.joining(", "));
                                duplicates.add(new Finding("duplicates", "error", k,
                                        "defined " + occ.size()
                                                + " times in the same file (lines " + joined + ")",
                                        rel, occ.get(0).line()));
                            }
                        });
                    } else {
                        scanSource(content).forEach((k, ln) -> {
                            usedFile.putIfAbsent(k, rel);
                            usedLine.putIfAbsent(k, ln[0]);
                        });
                    }
                });
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }

        TreeSet<String> definedNames = new TreeSet<>(definedFile.keySet());

        // errors: undefined-in-source
        List<Finding> undefined = new ArrayList<>();
        for (String name : new TreeSet<>(usedFile.keySet())) {
            if (!definedFile.containsKey(name)) {
                undefined.add(new Finding("undefined-in-source", "error", name,
                        "used in source code but not defined in any environment file",
                        usedFile.get(name), usedLine.get(name)));
            }
        }

        // errors: duplicates (sorted by name)
        duplicates.sort((a, b) -> a.name().compareTo(b.name()));

        // errors: public-prefix
        List<Finding> publicPrefix = new ArrayList<>();
        for (String name : definedNames) {
            if (isPublicSecret(name)) {
                publicPrefix.add(new Finding("public-prefix", "error", name,
                        "secret-looking variable is exposed to client bundles via a public prefix",
                        definedFile.get(name), definedLine.get(name)));
            }
        }

        // errors: type-mismatch
        List<Finding> typeMismatch = new ArrayList<>();
        for (Map.Entry<String, Map<String, String>> e
                : new TreeMap<>(labelsByVar).entrySet()) {
            Map<String, String> vals = e.getValue();
            if (vals.size() < 2) {
                continue;
            }
            TreeSet<String> groups = new TreeSet<>();
            for (String v : vals.values()) {
                String t = inferType(v);
                if (!t.equals("empty")) {
                    groups.add(typeGroup(t));
                }
            }
            if (groups.size() >= 2) {
                String k = e.getKey();
                typeMismatch.add(new Finding("type-mismatch", "error", k,
                        "inferred type differs across environments",
                        definedFile.get(k), definedLine.get(k)));
            }
        }

        // warnings: unused
        List<Finding> unused = new ArrayList<>();
        for (String name : definedNames) {
            if (!usedFile.containsKey(name)) {
                unused.add(new Finding("unused", "warning", name,
                        "defined but never referenced in source",
                        definedFile.get(name), definedLine.get(name)));
            }
        }

        // warnings: environment-diff
        List<Finding> environmentDiff = new ArrayList<>();
        if (allLabels.size() >= 2) {
            for (Map.Entry<String, Map<String, String>> e
                    : new TreeMap<>(labelsByVar).entrySet()) {
                TreeSet<String> present = new TreeSet<>(e.getValue().keySet());
                TreeSet<String> absent = new TreeSet<>(allLabels);
                absent.removeAll(present);
                if (present.isEmpty() || absent.isEmpty()) {
                    continue;
                }
                String k = e.getKey();
                environmentDiff.add(new Finding("environment-diff", "warning", k,
                        "defined in " + String.join(", ", present)
                                + " but missing in " + String.join(", ", absent),
                        definedFile.get(k), definedLine.get(k)));
            }
        }

        // warnings: weak-secret
        List<Finding> weakSecret = new ArrayList<>();
        for (String name : definedNames) {
            if (SECRET_NAME.matcher(name).find() && isWeakSecret(definedValue.get(name))) {
                weakSecret.add(new Finding("weak-secret", "warning", name,
                        "secret-looking variable has a weak or placeholder value",
                        definedFile.get(name), definedLine.get(name)));
            }
        }

        // warnings: typo
        List<Finding> typo = new ArrayList<>();
        for (String name : new TreeSet<>(usedFile.keySet())) {
            if (definedFile.containsKey(name)) {
                continue;
            }
            String d = typoSuggestion(name, definedNames);
            if (d != null) {
                typo.add(new Finding("typo", "warning", name,
                        "\"" + name + "\" is not defined; did you mean \"" + d + "\"?",
                        usedFile.get(name), usedLine.get(name)));
            }
        }

        List<Finding> findings = new ArrayList<>();
        findings.addAll(undefined);
        findings.addAll(duplicates);
        findings.addAll(publicPrefix);
        findings.addAll(typeMismatch);
        findings.addAll(unused);
        findings.addAll(environmentDiff);
        findings.addAll(weakSecret);
        findings.addAll(typo);
        return findings;
    }

    /** Map each environment label to the set of variable names defined in it. */
    public static Map<String, java.util.Set<String>> definedByLabel(Path root) {
        Map<String, java.util.Set<String>> labels = new LinkedHashMap<>();
        try (Stream<Path> walk = Files.walk(root)) {
            walk.filter(Files::isRegularFile)
                .filter(Scanner::notIgnored)
                .sorted()
                .forEach(path -> {
                    String name = path.getFileName().toString();
                    String label = envLabel(name);
                    boolean isEnv = label != null
                            && (name.equals(".env") || name.startsWith(".env."));
                    if (!isEnv) {
                        return;
                    }
                    java.util.Set<String> set =
                            labels.computeIfAbsent(label, k -> new java.util.TreeSet<>());
                    set.addAll(parseEnv(read(path)).keySet());
                });
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return labels;
    }

    /** Result of comparing two environment labels. */
    public record Diff(List<String> onlyInA, List<String> onlyInB, List<String> common) {}

    public static Diff diffLabels(Path root, String a, String b) {
        Map<String, java.util.Set<String>> labels = definedByLabel(root);
        java.util.Set<String> da = labels.getOrDefault(a, java.util.Set.of());
        java.util.Set<String> db = labels.getOrDefault(b, java.util.Set.of());
        List<String> onlyA = new ArrayList<>();
        List<String> common = new ArrayList<>();
        for (String k : new java.util.TreeSet<>(da)) {
            (db.contains(k) ? common : onlyA).add(k);
        }
        List<String> onlyB = new ArrayList<>();
        for (String k : new java.util.TreeSet<>(db)) {
            if (!da.contains(k)) {
                onlyB.add(k);
            }
        }
        return new Diff(onlyA, onlyB, common);
    }

    /**
     * Append keys present in {@code from} but missing from {@code to} as
     * {@code KEY=} placeholders. Values are never copied.
     */
    public static List<String> syncLabels(Path root, String from, String to, boolean dryRun) {
        Map<String, java.util.Set<String>> labels = definedByLabel(root);
        java.util.Set<String> df = labels.getOrDefault(from, java.util.Set.of());
        java.util.Set<String> dt = labels.getOrDefault(to, java.util.Set.of());
        List<String> missing = new ArrayList<>();
        for (String k : new java.util.TreeSet<>(df)) {
            if (!dt.contains(k)) {
                missing.add(k);
            }
        }
        if (!missing.isEmpty() && !dryRun) {
            Path target = root.resolve(to.equals("default") ? ".env" : ".env." + to);
            try {
                String existing = Files.exists(target) ? Files.readString(target) : "";
                StringBuilder sb = new StringBuilder();
                if (!existing.isEmpty() && !existing.endsWith("\n")) {
                    sb.append("\n");
                }
                for (String k : missing) {
                    sb.append(k).append("=\n");
                }
                Files.writeString(target, sb.toString(),
                        java.nio.file.StandardOpenOption.CREATE, java.nio.file.StandardOpenOption.APPEND);
            } catch (IOException e) {
                throw new UncheckedIOException(e);
            }
        }
        return missing;
    }

    private static boolean notIgnored(Path path) {
        for (Path part : path) {
            String s = part.toString();
            if (s.equals(".git") || s.equals("target") || s.equals("node_modules")) {
                return false;
            }
        }
        return true;
    }

    private static String read(Path path) {
        try {
            return Files.readString(path);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
