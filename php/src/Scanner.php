<?php

declare(strict_types=1);

namespace Envdoctor;

/**
 * Core scanner: reconcile environment access in PHP source against .env
 * definitions. Local-first — no network, values never printed.
 */
final class Scanner
{
    /** @var string[] Each pattern captures the variable name in group 1. */
    private const USAGE_PATTERNS = [
        '/\bgetenv\(\s*["\']([A-Za-z_]\w*)["\']/',
        '/\$_ENV\[\s*["\']([A-Za-z_]\w*)["\']\s*\]/',
        '/\$_SERVER\[\s*["\']([A-Za-z_]\w*)["\']\s*\]/',
    ];

    private const ENV_LINE = '/^\s*(?:export\s+)?([A-Za-z_]\w*)\s*=/';

    /** @var string[] Public/client-bundle prefixes (case-sensitive). */
    private const PUBLIC_PREFIXES = [
        'NEXT_PUBLIC_', 'VITE_', 'REACT_APP_', 'EXPO_PUBLIC_',
        'GATSBY_', 'NUXT_PUBLIC_', 'VUE_APP_', 'PUBLIC_',
    ];

    private const SECRET_RE = '/SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|API_?KEY|ACCESS_?KEY|AUTH/i';

    private const WEAK_VALUE_RE =
        '/^(changeme|change_me|placeholder|x{3,}|todo|secret|password|passwd|test|example|sample|dummy|your[_-].*|<.*>|\$\{.*\})$/i';

    private static function blank(string $s): string
    {
        return preg_replace('/[^\n]/', ' ', $s);
    }

    private static function stripNoise(string $code): string
    {
        // Block comments, then line comments (// and #).
        $code = preg_replace_callback('/\/\*.*?\*\//s', fn($m) => self::blank($m[0]), $code);
        $code = preg_replace_callback('/(?:\/\/|#)[^\n]*/', fn($m) => self::blank($m[0]), $code);

        return $code;
    }

    /** @return array<string, array{file: string, line: int}> */
    public static function scanSource(string $path, string $content): array
    {
        $text = self::stripNoise($content);
        $used = [];
        foreach (self::USAGE_PATTERNS as $pattern) {
            if (preg_match_all($pattern, $text, $matches, PREG_OFFSET_CAPTURE)) {
                foreach ($matches[1] as $m) {
                    $name = $m[0];
                    if (isset($used[$name])) {
                        continue;
                    }
                    $line = substr_count(substr($text, 0, $m[1]), "\n") + 1;
                    $used[$name] = ['file' => $path, 'line' => $line];
                }
            }
        }

        return $used;
    }

    /**
     * Parse the VALUE to the right of the first `=`: trim, then strip one pair
     * of matching surrounding quotes. Values are used ONLY for detection and
     * never appear in any output.
     */
    public static function parseValue(string $raw): string
    {
        $idx = strpos($raw, '=');
        if ($idx === false) {
            return '';
        }
        $value = trim(substr($raw, $idx + 1));
        $len = strlen($value);
        if ($len >= 2) {
            $first = $value[0];
            if (($first === '"' || $first === "'") && $value[$len - 1] === $first) {
                $value = substr($value, 1, $len - 2);
            }
        }

        return $value;
    }

    /**
     * Returns all occurrences per key: name => list of {line, value}, in order.
     *
     * @return array<string, array<int, array{line: int, value: string}>>
     */
    public static function parseEnv(string $content): array
    {
        $defined = [];
        foreach (explode("\n", $content) as $i => $raw) {
            $trimmed = trim($raw);
            if ($trimmed === '' || str_starts_with($trimmed, '#')) {
                continue;
            }
            if (preg_match(self::ENV_LINE, $raw, $m)) {
                $defined[$m[1]][] = ['line' => $i + 1, 'value' => self::parseValue($raw)];
            }
        }

        return $defined;
    }

    /** Derive the environment label from a .env filename. */
    public static function envLabel(string $filename): string
    {
        $base = basename($filename);
        if ($base === '.env') {
            return 'default';
        }
        $label = preg_replace('/^\.env\./', '', $base);
        if (str_ends_with($label, '.local')) {
            $label = substr($label, 0, -strlen('.local'));
        }

        return $label;
    }

    private static function isPublicPrefix(string $name): bool
    {
        $hasPrefix = false;
        foreach (self::PUBLIC_PREFIXES as $p) {
            if (str_starts_with($name, $p)) {
                $hasPrefix = true;
                break;
            }
        }

        return $hasPrefix && preg_match(self::SECRET_RE, $name) === 1;
    }

    /** Infer the coarse type of a value string. */
    public static function inferType(string $value): string
    {
        if ($value === '') {
            return 'empty';
        }
        if (preg_match('/^-?\d+$/', $value)) {
            return 'integer';
        }
        if (preg_match('/^-?\d+\.\d+$/', $value)) {
            return 'float';
        }
        if (preg_match('/^(true|false)$/i', $value)) {
            return 'boolean';
        }
        if (preg_match('#^https?://#', $value)) {
            return 'url';
        }
        if ($value[0] === '{' || $value[0] === '[') {
            json_decode($value);
            if (json_last_error() === JSON_ERROR_NONE) {
                return 'json';
            }
        }

        return 'string';
    }

    /** Compatibility group (integer/float collapse to numeric). */
    private static function typeGroup(string $type): string
    {
        return ($type === 'integer' || $type === 'float') ? 'numeric' : $type;
    }

    private static function isWeakSecret(string $value): bool
    {
        return $value === '' || strlen($value) < 8 || preg_match(self::WEAK_VALUE_RE, $value) === 1;
    }

    private static function levenshteinDistance(string $a, string $b): int
    {
        return levenshtein($a, $b);
    }

    /** @return string[] */
    private static function discoverFiles(string $root, string $suffix, bool $envMode): array
    {
        $out = [];
        $it = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($root, \FilesystemIterator::SKIP_DOTS)
        );
        foreach ($it as $file) {
            $name = $file->getFilename();
            $skip = false;
            foreach (['.git', 'vendor', 'node_modules'] as $bad) {
                if (str_contains($file->getPathname(), DIRECTORY_SEPARATOR . $bad . DIRECTORY_SEPARATOR)) {
                    $skip = true;
                    break;
                }
            }
            if ($skip) {
                continue;
            }
            if ($envMode) {
                $isEnv = $name === '.env' || (str_starts_with($name, '.env.') && !str_ends_with($name, '.example'));
                if ($isEnv) {
                    $out[] = $file->getPathname();
                }
            } elseif (str_ends_with($name, $suffix)) {
                $out[] = $file->getPathname();
            }
        }
        sort($out);

        return $out;
    }

    private const COMPOSE_RE = '/^(docker-)?compose([.-].*)?\.ya?ml$/i';

    /**
     * Walk the project and classify infra YAML files.
     *
     * @return array<int, array{path: string, kind: string}>
     */
    private static function discoverInfraFiles(string $root): array
    {
        $out = [];
        $it = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($root, \FilesystemIterator::SKIP_DOTS)
        );
        foreach ($it as $file) {
            $path = $file->getPathname();
            $skip = false;
            foreach (['.git', 'vendor', 'node_modules', 'target'] as $bad) {
                if (str_contains($path, DIRECTORY_SEPARATOR . $bad . DIRECTORY_SEPARATOR)) {
                    $skip = true;
                    break;
                }
            }
            if ($skip) {
                continue;
            }
            $base = $file->getFilename();
            $isYaml = preg_match('/\.ya?ml$/i', $base) === 1;
            if (preg_match(self::COMPOSE_RE, $base) === 1) {
                $out[] = ['path' => $path, 'kind' => 'compose'];
            } elseif ($isYaml && str_contains($path, DIRECTORY_SEPARATOR . '.github' . DIRECTORY_SEPARATOR . 'workflows' . DIRECTORY_SEPARATOR)) {
                $out[] = ['path' => $path, 'kind' => 'actions'];
            } elseif ($isYaml) {
                $content = (string) file_get_contents($path);
                if (preg_match('/^apiVersion:/m', $content) === 1 && preg_match('/^kind:/m', $content) === 1) {
                    $out[] = ['path' => $path, 'kind' => 'k8s'];
                }
            }
        }
        usort($out, fn($a, $b) => strcmp($a['path'], $b['path']));

        return $out;
    }

    /**
     * Extract used variable NAMES (with origin) from an infra YAML file. First
     * removes escaped `$$` (two spaces, offsets preserved), then scans for
     * interpolation and, for GitHub Actions, the secrets/vars/env contexts.
     *
     * @return array<string, array{file: string, line: int}>
     */
    public static function scanInfra(string $path, string $content, string $kind): array
    {
        $text = str_replace('$$', '  ', $content);
        $patterns = [
            '/\$\{([A-Za-z_][A-Za-z0-9_]*)/',
            '/\$([A-Za-z_][A-Za-z0-9_]*)/',
        ];
        if ($kind === 'actions') {
            $patterns[] = '/\b(?:secrets|vars|env)\.([A-Za-z_][A-Za-z0-9_]*)/';
        }
        $used = [];
        foreach ($patterns as $pattern) {
            if (preg_match_all($pattern, $text, $matches, PREG_OFFSET_CAPTURE)) {
                foreach ($matches[1] as $m) {
                    $name = $m[0];
                    if (isset($used[$name])) {
                        continue;
                    }
                    $line = substr_count(substr($text, 0, $m[1]), "\n") + 1;
                    $used[$name] = ['file' => $path, 'line' => $line];
                }
            }
        }

        return $used;
    }

    /** @return Finding[] */
    /**
     * Map each environment label to the sorted list of variable names in it.
     *
     * @return array<string, string[]>
     */
    public static function definedByLabel(string $root): array
    {
        $root = rtrim($root, DIRECTORY_SEPARATOR);
        $labels = [];
        foreach (self::discoverFiles($root, '', true) as $f) {
            $label = self::envLabel($f);
            $labels[$label] ??= [];
            foreach (array_keys(self::parseEnv((string) file_get_contents($f))) as $name) {
                if (!in_array($name, $labels[$label], true)) {
                    $labels[$label][] = $name;
                }
            }
        }

        return $labels;
    }

    /** @return array{onlyInA: string[], onlyInB: string[], common: string[]} */
    public static function diffLabels(string $root, string $a, string $b): array
    {
        $labels = self::definedByLabel($root);
        $da = $labels[$a] ?? [];
        $db = $labels[$b] ?? [];
        $sort = static function (array $x): array {
            sort($x);
            return array_values($x);
        };

        return [
            'onlyInA' => $sort(array_diff($da, $db)),
            'onlyInB' => $sort(array_diff($db, $da)),
            'common' => $sort(array_intersect($da, $db)),
        ];
    }

    /**
     * Append keys present in `from` but missing from `to` as `KEY=` placeholders.
     * Values are never copied.
     *
     * @return string[]
     */
    public static function syncLabels(string $root, string $from, string $to, bool $dryRun = false): array
    {
        $root = rtrim($root, DIRECTORY_SEPARATOR);
        $labels = self::definedByLabel($root);
        $missing = array_values(array_diff($labels[$from] ?? [], $labels[$to] ?? []));
        sort($missing);
        if ($missing && !$dryRun) {
            $target = $root . DIRECTORY_SEPARATOR . ($to === 'default' ? '.env' : ".env.$to");
            $existing = is_file($target) ? (string) file_get_contents($target) : '';
            $prefix = ($existing === '' || str_ends_with($existing, "\n")) ? '' : "\n";
            $append = $prefix . implode('', array_map(static fn($k) => "$k=\n", $missing));
            file_put_contents($target, $append, FILE_APPEND);
        }

        return $missing;
    }

    /**
     * Collect the DEFINED (from .env*) and USED (source + infra) name sets.
     *
     * @return array{0: array<string, bool>, 1: array<string, bool>}
     */
    public static function collectNames(string $root): array
    {
        $root = rtrim($root, DIRECTORY_SEPARATOR);
        $defined = [];
        foreach (self::discoverFiles($root, '', true) as $f) {
            foreach (array_keys(self::parseEnv((string) file_get_contents($f))) as $name) {
                $defined[$name] = true;
            }
        }
        $used = [];
        foreach (self::discoverFiles($root, '.php', false) as $f) {
            foreach (self::scanSource(self::rel($root, $f), (string) file_get_contents($f)) as $k => $v) {
                $used[$k] = true;
            }
        }
        foreach (self::discoverInfraFiles($root) as $infra) {
            $rel = self::rel($root, $infra['path']);
            foreach (self::scanInfra($rel, (string) file_get_contents($infra['path']), $infra['kind']) as $k => $v) {
                $used[$k] = true;
            }
        }

        return [$defined, $used];
    }

    /**
     * Exact `.env.example` content: header, then `NAME=` per (defined ∪ used),
     * sorted ascending. Values are never written.
     */
    public static function envExampleContent(string $root): string
    {
        [$defined, $used] = self::collectNames($root);
        $names = array_keys($defined + $used);
        sort($names, SORT_STRING);
        $out = "# Generated by envdoctor. Fill in values; do not commit secrets.\n";
        foreach ($names as $n) {
            $out .= "$n=\n";
        }

        return $out;
    }

    /** Exact `ENVIRONMENT.md` content: a Defined/Used table per variable. */
    public static function environmentDocContent(string $root): string
    {
        [$defined, $used] = self::collectNames($root);
        $names = array_keys($defined + $used);
        sort($names, SORT_STRING);
        $lines = ['# Environment variables', '', '| Variable | Defined | Used |', '| --- | --- | --- |'];
        foreach ($names as $n) {
            $d = isset($defined[$n]) ? 'yes' : 'no';
            $u = isset($used[$n]) ? 'yes' : 'no';
            $lines[] = "| $n | $d | $u |";
        }

        return implode("\n", $lines) . "\n";
    }

    public static function scan(string $root): array
    {
        $root = rtrim($root, DIRECTORY_SEPARATOR);
        $defined = [];        // name => {file, line} (first definition wins)
        $definedValue = [];   // name => value at first definition
        $labelsOf = [];       // name => [label => value] (first value per label)
        $projectLabels = [];
        $dupFindings = [];

        foreach (self::discoverFiles($root, '', true) as $f) {
            $rel = self::rel($root, $f);
            $label = self::envLabel($f);
            if (!in_array($label, $projectLabels, true)) {
                $projectLabels[] = $label;
            }
            foreach (self::parseEnv((string) file_get_contents($f)) as $k => $defs) {
                if (count($defs) >= 2) {
                    $lines = array_map(fn($o) => $o['line'], $defs);
                    $dupFindings[] = new Finding(
                        'duplicates',
                        'error',
                        $k,
                        'defined ' . count($defs) . ' times in the same file (lines '
                            . implode(', ', $lines) . ')',
                        ['file' => $rel, 'line' => $defs[0]['line']]
                    );
                }
                // First occurrence (first file wins) counts as the definition.
                if (!isset($defined[$k])) {
                    $defined[$k] = ['file' => $rel, 'line' => $defs[0]['line']];
                    $definedValue[$k] = $defs[0]['value'];
                }
                if (!isset($labelsOf[$k][$label])) {
                    $labelsOf[$k][$label] = $defs[0]['value'];
                }
            }
        }

        $used = [];
        foreach (self::discoverFiles($root, '.php', false) as $f) {
            foreach (self::scanSource(self::rel($root, $f), (string) file_get_contents($f)) as $k => $v) {
                $used[$k] ??= $v;
            }
        }
        // Infra sources (Docker Compose / GitHub Actions / Kubernetes) contribute
        // additional used names; first origin wins.
        foreach (self::discoverInfraFiles($root) as $infra) {
            $rel = self::rel($root, $infra['path']);
            foreach (self::scanInfra($rel, (string) file_get_contents($infra['path']), $infra['kind']) as $k => $v) {
                $used[$k] ??= $v;
            }
        }

        $errors = [];
        $warnings = [];

        // --- errors: undefined-in-source ---
        $usedNames = array_keys($used);
        sort($usedNames);
        foreach ($usedNames as $name) {
            if (!isset($defined[$name])) {
                $errors[] = new Finding(
                    'undefined-in-source',
                    'error',
                    $name,
                    'referenced but not defined in any environment file',
                    $used[$name]
                );
            }
        }

        // --- errors: duplicates ---
        usort($dupFindings, fn($a, $b) => strcmp($a->name, $b->name));
        foreach ($dupFindings as $finding) {
            $errors[] = $finding;
        }

        $definedNames = array_keys($defined);
        sort($definedNames);

        // --- errors: public-prefix ---
        foreach ($definedNames as $name) {
            if (self::isPublicPrefix($name)) {
                $errors[] = new Finding(
                    'public-prefix',
                    'error',
                    $name,
                    'secret-looking variable is exposed to client bundles via a public prefix',
                    $defined[$name]
                );
            }
        }

        // --- errors: type-mismatch ---
        foreach ($definedNames as $name) {
            $labels = $labelsOf[$name] ?? [];
            if (count($labels) < 2) {
                continue;
            }
            $groups = [];
            foreach ($labels as $value) {
                $type = self::inferType($value);
                if ($type === 'empty') {
                    continue;
                }
                $group = self::typeGroup($type);
                if (!in_array($group, $groups, true)) {
                    $groups[] = $group;
                }
            }
            if (count($groups) >= 2) {
                $errors[] = new Finding(
                    'type-mismatch',
                    'error',
                    $name,
                    'inferred type differs across environments',
                    $defined[$name]
                );
            }
        }

        // --- errors: schema-validation ---
        $schema = self::loadSchema($root);
        $schemaNames = array_keys($schema);
        sort($schemaNames);
        foreach ($schemaNames as $name) {
            $rule = $schema[$name];
            if (!is_array($rule)) {
                continue;
            }
            if (isset($defined[$name])) {
                $msg = self::schemaFailure($rule, $definedValue[$name]);
                if ($msg !== null) {
                    $errors[] = new Finding('schema-validation', 'error', $name, $msg, $defined[$name]);
                }
            } elseif (empty($rule['optional'])) {
                $errors[] = new Finding('schema-validation', 'error', $name,
                    'required by schema but not defined', null);
            }
        }

        // --- warnings: unused ---
        foreach ($definedNames as $name) {
            if (!isset($used[$name])) {
                $warnings[] = new Finding(
                    'unused',
                    'warning',
                    $name,
                    'defined but never referenced in source',
                    $defined[$name]
                );
            }
        }

        // --- warnings: environment-diff ---
        if (count($projectLabels) >= 2) {
            foreach ($definedNames as $name) {
                $present = array_keys($labelsOf[$name] ?? []);
                sort($present);
                $absent = array_values(array_diff($projectLabels, $present));
                sort($absent);
                if (count($present) === 0 || count($absent) === 0) {
                    continue;
                }
                $warnings[] = new Finding(
                    'environment-diff',
                    'warning',
                    $name,
                    'defined in ' . implode(', ', $present) . ' but missing in ' . implode(', ', $absent),
                    $defined[$name]
                );
            }
        }

        // --- warnings: weak-secret ---
        foreach ($definedNames as $name) {
            if (preg_match(self::SECRET_RE, $name) !== 1) {
                continue;
            }
            if (!self::isWeakSecret((string) ($definedValue[$name] ?? ''))) {
                continue;
            }
            $warnings[] = new Finding(
                'weak-secret',
                'warning',
                $name,
                'secret-looking variable has a weak or placeholder value',
                $defined[$name]
            );
        }

        // --- warnings: typo ---
        foreach ($usedNames as $u) {
            if (isset($defined[$u])) {
                continue;
            }
            $best = null;
            $bestDist = null;
            foreach ($definedNames as $d) {
                if ($d === $u) {
                    continue;
                }
                $limit = min(strlen($u), strlen($d)) <= 4 ? 1 : 2;
                $dist = self::levenshteinDistance($u, $d);
                if ($dist > $limit) {
                    continue;
                }
                if ($best === null || $dist < $bestDist || ($dist === $bestDist && strcmp($d, $best) < 0)) {
                    $best = $d;
                    $bestDist = $dist;
                }
            }
            if ($best === null) {
                continue;
            }
            $warnings[] = new Finding(
                'typo',
                'warning',
                $u,
                '"' . $u . '" is not defined; did you mean "' . $best . '"?',
                $used[$u]
            );
        }

        return array_merge($errors, $warnings);
    }

    /**
     * Serialize findings to the shared JSON shape. Values never appear.
     *
     * @param Finding[] $findings
     */
    /** @return array<string, mixed> */
    public static function loadSchema(string $root): array
    {
        $path = rtrim($root, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . 'envdoctor.schema.json';
        if (!is_file($path)) {
            return [];
        }
        $data = json_decode((string) file_get_contents($path), true);

        return is_array($data) ? $data : [];
    }

    private static function schemaTypeOk(string $value, string $declared): bool
    {
        switch ($declared) {
            case 'string': return true;
            case 'integer': return (bool) preg_match('/^-?\d+$/', $value);
            case 'float': return (bool) preg_match('/^-?\d+(\.\d+)?$/', $value);
            case 'boolean': return in_array(strtolower($value), ['true', 'false'], true);
            case 'url': return (bool) preg_match('#^https?://#', $value);
            case 'json': return json_decode($value) !== null || trim($value) === 'null';
            default: return true;
        }
    }

    /** @param array<string, mixed> $rule */
    public static function schemaFailure(array $rule, string $value): ?string
    {
        if (isset($rule['type']) && is_string($rule['type']) && !self::schemaTypeOk($value, $rule['type'])) {
            return "value does not match schema type {$rule['type']}";
        }
        if (isset($rule['enum']) && is_array($rule['enum']) && !in_array($value, $rule['enum'], true)) {
            return 'value is not one of the allowed values';
        }
        if (isset($rule['regex']) && is_string($rule['regex'])) {
            if (@preg_match('/' . str_replace('/', '\/', $rule['regex']) . '/', $value) === 0) {
                return 'value does not match the required pattern';
            }
        }
        if (preg_match('/^-?\d+(\.\d+)?$/', $value)) {
            $num = (float) $value;
            if (isset($rule['min']) && is_numeric($rule['min']) && $num < $rule['min']) {
                return 'value is below the minimum';
            }
            if (isset($rule['max']) && is_numeric($rule['max']) && $num > $rule['max']) {
                return 'value exceeds the maximum';
            }
        }

        return null;
    }

    public static function toJsonArray(array $findings): string
    {
        $out = [];
        foreach ($findings as $f) {
            $out[] = [
                'rule' => $f->rule,
                'severity' => $f->severity,
                'name' => $f->name,
                'message' => $f->message,
                'file' => $f->origin === null ? null : $f->origin['file'],
                'line' => $f->origin === null ? null : $f->origin['line'],
            ];
        }

        return json_encode($out, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    }

    private static function rel(string $root, string $path): string
    {
        return ltrim(substr($path, strlen($root)), DIRECTORY_SEPARATOR);
    }
}

/** One reported issue. */
final class Finding
{
    /** @param array{file: string, line: int}|null $origin */
    public function __construct(
        public string $rule,
        public string $severity,
        public string $name,
        public string $message,
        public ?array $origin = null,
    ) {
    }
}
