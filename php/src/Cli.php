<?php

declare(strict_types=1);

namespace Envdoctor;

/** Command-line entry point. */
final class Cli
{
    /** @param string[] $argv */
    public static function run(array $argv): int
    {
        $args = array_slice($argv, 1);
        if (($args[0] ?? null) === 'diff') {
            return self::runDiff(array_slice($args, 1));
        }
        if (($args[0] ?? null) === 'sync') {
            return self::runSync(array_slice($args, 1));
        }
        if (($args[0] ?? null) === 'init') {
            return self::runInit(array_slice($args, 1));
        }
        if (($args[0] ?? null) === 'fix') {
            return self::runFix(array_slice($args, 1));
        }

        $dir = '.';
        $strict = false;
        $json = false;
        if (($args[0] ?? null) === 'scan') {
            array_shift($args);
        }
        for ($i = 0; $i < count($args); $i++) {
            $a = $args[$i];
            if ($a === '-d' || $a === '--dir') {
                $dir = $args[++$i] ?? '.';
            } elseif (str_starts_with($a, '--dir=')) {
                $dir = substr($a, 6);
            } elseif ($a === '--strict') {
                $strict = true;
            } elseif ($a === '--json') {
                $json = true;
            }
        }

        $root = realpath($dir) ?: $dir;
        $findings = Scanner::scan($root);
        $errors = array_values(array_filter($findings, fn($f) => $f->severity === 'error'));
        $warnings = array_values(array_filter($findings, fn($f) => $f->severity === 'warning'));

        if ($json) {
            echo Scanner::toJsonArray($findings) . "\n";

            return ($errors || ($strict && $warnings)) ? 1 : 0;
        }

        echo "ENVIRONMENT AUDIT\n";
        echo str_repeat('=', 40) . "\n";
        if (count($findings) === 0) {
            echo "\nNo issues found.\n";

            return 0;
        }
        $loc = static fn($f) => $f->origin === null ? '' : " {$f->origin['file']}:{$f->origin['line']}";
        if ($errors) {
            echo "\nErrors\n";
            foreach ($errors as $f) {
                echo "  x {$f->name}{$loc($f)}  {$f->message}\n";
            }
        }
        if ($warnings) {
            echo "\nWarnings\n";
            foreach ($warnings as $f) {
                echo "  ! {$f->name}{$loc($f)}  {$f->message}\n";
            }
        }
        echo "\nSummary: " . count($errors) . ' error(s), ' . count($warnings) . " warning(s)\n";

        return ($errors || ($strict && $warnings)) ? 1 : 0;
    }

    /**
     * @param string[] $args
     * @return array{0: string[], 1: string, 2: bool, 3: bool}
     */
    private static function parseSub(array $args): array
    {
        $pos = [];
        $dir = '.';
        $dryRun = false;
        $json = false;
        for ($i = 0; $i < count($args); $i++) {
            $a = $args[$i];
            if ($a === '-d' || $a === '--dir') {
                $dir = $args[++$i] ?? '.';
            } elseif (str_starts_with($a, '--dir=')) {
                $dir = substr($a, 6);
            } elseif ($a === '--dry-run') {
                $dryRun = true;
            } elseif ($a === '--json') {
                $json = true;
            } else {
                $pos[] = $a;
            }
        }

        return [$pos, $dir, $dryRun, $json];
    }

    /**
     * Generate `.env.example` and `ENVIRONMENT.md`, writing each only if absent
     * (or always with --force).
     *
     * @param string[] $args
     */
    private static function runInit(array $args): int
    {
        $dir = '.';
        $force = false;
        for ($i = 0; $i < count($args); $i++) {
            $a = $args[$i];
            if ($a === '-d' || $a === '--dir') {
                $dir = $args[++$i] ?? '.';
            } elseif (str_starts_with($a, '--dir=')) {
                $dir = substr($a, 6);
            } elseif ($a === '--force') {
                $force = true;
            }
        }
        $root = rtrim(realpath($dir) ?: $dir, DIRECTORY_SEPARATOR);
        $files = [
            '.env.example' => Scanner::envExampleContent($root),
            'ENVIRONMENT.md' => Scanner::environmentDocContent($root),
        ];
        foreach ($files as $name => $content) {
            $path = $root . DIRECTORY_SEPARATOR . $name;
            if (is_file($path) && !$force) {
                echo "skipped $name (exists)\n";
            } else {
                file_put_contents($path, $content);
                echo ($force ? 'wrote' : 'created') . " $name\n";
            }
        }

        return 0;
    }

    /**
     * Always (re)write both generated files.
     *
     * @param string[] $args
     */
    private static function runFix(array $args): int
    {
        $dir = '.';
        for ($i = 0; $i < count($args); $i++) {
            $a = $args[$i];
            if ($a === '-d' || $a === '--dir') {
                $dir = $args[++$i] ?? '.';
            } elseif (str_starts_with($a, '--dir=')) {
                $dir = substr($a, 6);
            }
        }
        $root = rtrim(realpath($dir) ?: $dir, DIRECTORY_SEPARATOR);
        file_put_contents($root . DIRECTORY_SEPARATOR . '.env.example', Scanner::envExampleContent($root));
        echo "wrote .env.example\n";
        file_put_contents($root . DIRECTORY_SEPARATOR . 'ENVIRONMENT.md', Scanner::environmentDocContent($root));
        echo "wrote ENVIRONMENT.md\n";

        return 0;
    }

    /** @param string[] $args */
    private static function runDiff(array $args): int
    {
        [$pos, $dir, , $json] = self::parseSub($args);
        $a = $pos[0] ?? '';
        $b = $pos[1] ?? '';
        $root = realpath($dir) ?: $dir;
        $d = Scanner::diffLabels($root, $a, $b);
        if ($json) {
            echo json_encode(['a' => $a, 'b' => $b] + $d) . "\n";

            return 0;
        }
        echo "ENVIRONMENT DIFF: $a vs $b\n";
        echo str_repeat('=', 40) . "\n";
        if ($d['onlyInA']) {
            echo "Only in $a:\n";
            foreach ($d['onlyInA'] as $k) {
                echo "  + $k\n";
            }
        }
        if ($d['onlyInB']) {
            echo "Only in $b:\n";
            foreach ($d['onlyInB'] as $k) {
                echo "  + $k\n";
            }
        }
        echo 'Common: ' . count($d['common']) . " variable(s)\n";

        return 0;
    }

    /** @param string[] $args */
    private static function runSync(array $args): int
    {
        [$pos, $dir, $dryRun, $json] = self::parseSub($args);
        $from = $pos[0] ?? '';
        $to = $pos[1] ?? '';
        $root = realpath($dir) ?: $dir;
        $added = Scanner::syncLabels($root, $from, $to, $dryRun);
        if ($json) {
            echo json_encode(['from' => $from, 'to' => $to, 'added' => $added, 'dryRun' => $dryRun]) . "\n";

            return 0;
        }
        if (!$added) {
            echo "Already in sync.\n";

            return 0;
        }
        $verb = $dryRun ? 'Would sync' : 'Synced';
        echo "$verb " . count($added) . " variable(s) from $from to $to:\n";
        foreach ($added as $k) {
            echo "  + $k\n";
        }

        return 0;
    }
}
