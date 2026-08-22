<?php

declare(strict_types=1);

// Dependency-free test runner (no PHPUnit needed): run `php tests/ScannerTest.php`.

require __DIR__ . '/../src/Scanner.php';

use Envdoctor\Scanner;

$failures = 0;
function check(bool $cond, string $label): void
{
    global $failures;
    if ($cond) {
        echo "  ok  $label\n";
    } else {
        echo "  FAIL $label\n";
        $failures++;
    }
}

// 1) usage detection + comment stripping
$src = <<<'PHP'
<?php
// getenv("COMMENTED")
# getenv("HASH_COMMENTED")
$db = getenv("DB_URL");
$port = $_ENV["PORT"];
$host = $_SERVER["HOST"];
/* getenv("BLOCK_IGNORED") */
PHP;
$used = Scanner::scanSource('config.php', $src);
$names = array_keys($used);
sort($names);
check($names === ['DB_URL', 'HOST', 'PORT'], 'detects getenv/$_ENV/$_SERVER, ignores comments');

// 2) reconcile missing + unused
$dir = sys_get_temp_dir() . '/envd_php_' . uniqid();
mkdir($dir);
file_put_contents("$dir/.env", "DB_URL=x\nUNUSED_KEY=1\n");
file_put_contents("$dir/app.php", "<?php\ngetenv(\"DB_URL\");\ngetenv(\"NEW_FLAG\");\n");
$findings = Scanner::scan($dir);
$errors = array_map(fn($f) => $f->name, array_filter($findings, fn($f) => $f->severity === 'error'));
$warnings = array_map(fn($f) => $f->name, array_filter($findings, fn($f) => $f->severity === 'warning'));
check(in_array('NEW_FLAG', $errors, true), 'NEW_FLAG reported as error');
check(in_array('UNUSED_KEY', $warnings, true), 'UNUSED_KEY reported as warning');
check(!in_array('DB_URL', $errors, true) && !in_array('DB_URL', $warnings, true), 'DB_URL reconciled');

echo $failures === 0 ? "\nAll tests passed\n" : "\n$failures test(s) failed\n";
exit($failures === 0 ? 0 : 1);
