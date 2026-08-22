<?php

declare(strict_types=1);

namespace Envdoctor;

/** Command-line entry point. */
final class Cli
{
    /** @param string[] $argv */
    public static function run(array $argv): int
    {
        $dir = '.';
        $strict = false;
        $args = array_slice($argv, 1);
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
            }
        }

        $root = realpath($dir) ?: $dir;
        $findings = Scanner::scan($root);
        $errors = array_values(array_filter($findings, fn($f) => $f->severity === 'error'));
        $warnings = array_values(array_filter($findings, fn($f) => $f->severity === 'warning'));

        echo "ENVIRONMENT AUDIT\n";
        echo str_repeat('=', 40) . "\n";
        if (count($findings) === 0) {
            echo "\nNo issues found.\n";

            return 0;
        }
        if ($errors) {
            echo "\nErrors\n";
            foreach ($errors as $f) {
                echo "  x {$f->name} {$f->origin['file']}:{$f->origin['line']}  {$f->message}\n";
            }
        }
        if ($warnings) {
            echo "\nWarnings\n";
            foreach ($warnings as $f) {
                echo "  ! {$f->name} {$f->origin['file']}:{$f->origin['line']}  {$f->message}\n";
            }
        }
        echo "\nSummary: " . count($errors) . ' error(s), ' . count($warnings) . " warning(s)\n";

        return ($errors || ($strict && $warnings)) ? 1 : 0;
    }
}
