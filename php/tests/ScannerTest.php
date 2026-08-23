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

// 3) duplicate keys within a single file
$dir = sys_get_temp_dir() . '/envd_php_' . uniqid();
mkdir($dir);
file_put_contents("$dir/.env", "DUP=a\nSOLO=1\nDUP=b\n");
file_put_contents("$dir/app.php", "<?php\ngetenv(\"DUP\");\ngetenv(\"SOLO\");\n");
$findings = Scanner::scan($dir);
$dup = null;
foreach ($findings as $f) {
    if ($f->rule === 'duplicates') {
        $dup = $f;
        break;
    }
}
check($dup !== null && $dup->name === 'DUP' && $dup->severity === 'error', 'DUP reported as duplicates error');
check($dup !== null && $dup->message === 'defined 2 times in the same file (lines 1, 3)', 'duplicates message correct');
$soloDup = array_filter($findings, fn($f) => $f->rule === 'duplicates' && $f->name === 'SOLO');
check(count($soloDup) === 0, 'single-definition SOLO not a duplicate');
$dupOther = array_filter($findings, fn($f) => $f->name === 'DUP' && in_array($f->rule, ['unused', 'undefined-in-source'], true));
check(count($dupOther) === 0, 'duplicated-but-used DUP not also unused/undefined');

// 4) public-prefix secret leaks
$dir = sys_get_temp_dir() . '/envd_php_' . uniqid();
mkdir($dir);
file_put_contents("$dir/.env", "NEXT_PUBLIC_API_KEY=x\nVITE_SECRET=y\nPUBLIC_URL=z\nAPI_KEY=w\nPUBLIC_KEY=k\n");
$findings = Scanner::scan($dir);
$flagged = array_map(fn($f) => $f->name, array_filter($findings, fn($f) => $f->rule === 'public-prefix'));
check(in_array('NEXT_PUBLIC_API_KEY', $flagged, true), 'NEXT_PUBLIC_API_KEY flagged');
check(in_array('VITE_SECRET', $flagged, true), 'VITE_SECRET flagged');
check(!in_array('PUBLIC_URL', $flagged, true), 'PUBLIC_URL not flagged');
check(!in_array('API_KEY', $flagged, true), 'bare API_KEY not flagged');
check(!in_array('PUBLIC_KEY', $flagged, true), 'PUBLIC_KEY not flagged');
$ppSev = array_filter($findings, fn($f) => $f->rule === 'public-prefix' && $f->severity !== 'error');
check(count($ppSev) === 0, 'public-prefix findings are errors');

// 5) weak-secret detection
$dir = sys_get_temp_dir() . '/envd_php_' . uniqid();
mkdir($dir);
file_put_contents("$dir/.env", "API_KEY=changeme\nDB_PASSWORD=s3cureLongValue!\nAUTH_TOKEN=\nSECRET_KEY=xxxxxx\nDATABASE_URL=postgres://localhost/db\n");
file_put_contents("$dir/app.php", "<?php\ngetenv(\"API_KEY\");\ngetenv(\"DB_PASSWORD\");\ngetenv(\"AUTH_TOKEN\");\ngetenv(\"SECRET_KEY\");\ngetenv(\"DATABASE_URL\");\n");
$findings = Scanner::scan($dir);
$weak = array_values(array_filter($findings, fn($f) => $f->rule === 'weak-secret'));
$weakNames = array_map(fn($f) => $f->name, $weak);
check(in_array('API_KEY', $weakNames, true), 'API_KEY placeholder value is weak');
check(in_array('AUTH_TOKEN', $weakNames, true), 'AUTH_TOKEN empty value is weak');
check(in_array('SECRET_KEY', $weakNames, true), 'SECRET_KEY xxxxxx value is weak');
check(!in_array('DB_PASSWORD', $weakNames, true), 'strong DB_PASSWORD not weak');
check(!in_array('DATABASE_URL', $weakNames, true), 'non-secret-name DATABASE_URL not weak');
$weakOk = array_reduce($weak, fn($c, $f) => $c && $f->severity === 'warning'
    && $f->message === 'secret-looking variable has a weak or placeholder value', true);
check($weakOk, 'weak-secret findings are warnings with correct message');

// 6) typo detection (DATBASE_URL used vs DATABASE_URL defined)
$dir = sys_get_temp_dir() . '/envd_php_' . uniqid();
mkdir($dir);
file_put_contents("$dir/.env", "DATABASE_URL=x\n");
file_put_contents("$dir/app.php", "<?php\ngetenv(\"DATBASE_URL\");\n");
$findings = Scanner::scan($dir);
$typo = null;
foreach ($findings as $f) {
    if ($f->rule === 'typo') {
        $typo = $f;
        break;
    }
}
check($typo !== null && $typo->name === 'DATBASE_URL' && $typo->severity === 'warning', 'DATBASE_URL typo reported');
check($typo !== null && $typo->message === '"DATBASE_URL" is not defined; did you mean "DATABASE_URL"?', 'typo message correct');
$undef = array_filter($findings, fn($f) => $f->rule === 'undefined-in-source' && $f->name === 'DATBASE_URL');
check(count($undef) === 1, 'undefined-in-source still fires for typo name');

// 7) environment-diff detection
$dir = sys_get_temp_dir() . '/envd_php_' . uniqid();
mkdir($dir);
file_put_contents("$dir/.env", "SHARED=1\nONLY_DEFAULT=1\n");
file_put_contents("$dir/.env.production", "SHARED=1\nONLY_PROD=1\n");
$findings = Scanner::scan($dir);
$diffs = array_values(array_filter($findings, fn($f) => $f->rule === 'environment-diff'));
$od = null;
foreach ($diffs as $f) {
    if ($f->name === 'ONLY_DEFAULT') {
        $od = $f;
    }
}
check($od !== null && $od->severity === 'warning' && $od->message === 'defined in default but missing in production', 'ONLY_DEFAULT env-diff correct');
$prodDiff = array_filter($diffs, fn($f) => $f->name === 'ONLY_PROD' && $f->message === 'defined in production but missing in default');
check(count($prodDiff) === 1, 'ONLY_PROD env-diff correct');
$sharedDiff = array_filter($diffs, fn($f) => $f->name === 'SHARED');
check(count($sharedDiff) === 0, 'SHARED present in both → no env-diff');

// 8) type-mismatch detection
$dir = sys_get_temp_dir() . '/envd_php_' . uniqid();
mkdir($dir);
file_put_contents("$dir/.env", "PORT=8080\nWORKERS=4\n");
file_put_contents("$dir/.env.production", "PORT=production\nWORKERS=8\n");
$findings = Scanner::scan($dir);
$tm = array_values(array_filter($findings, fn($f) => $f->rule === 'type-mismatch'));
$tmNames = array_map(fn($f) => $f->name, $tm);
check(in_array('PORT', $tmNames, true), 'PORT integer vs string → type-mismatch error');
check(!in_array('WORKERS', $tmNames, true), 'WORKERS two integers → no type-mismatch');
$portTm = array_filter($tm, fn($f) => $f->name === 'PORT' && $f->severity === 'error'
    && $f->message === 'inferred type differs across environments');
check(count($portTm) === 1, 'PORT type-mismatch is error with correct message');

// 9) JSON shape + no value leak
$dir = sys_get_temp_dir() . '/envd_php_' . uniqid();
mkdir($dir);
file_put_contents("$dir/.env", "API_KEY=changeme\nUNUSED_KEY=supersecretvalue\n");
file_put_contents("$dir/app.php", "<?php\ngetenv(\"API_KEY\");\n");
$findings = Scanner::scan($dir);
$jsonStr = Scanner::toJsonArray($findings);
$arr = json_decode($jsonStr, true);
check(is_array($arr), 'JSON output decodes to an array');
$shapeOk = true;
foreach ($arr as $obj) {
    $keys = array_keys($obj);
    sort($keys);
    if ($keys !== ['file', 'line', 'message', 'name', 'rule', 'severity']) {
        $shapeOk = false;
    }
}
check($shapeOk, 'each JSON object has exactly the required keys');
check(!str_contains($jsonStr, 'supersecretvalue') && !str_contains($jsonStr, 'changeme'), 'no value strings leak into JSON');


// diff + sync subcommands
$dir2 = sys_get_temp_dir() . '/envd_php_sub_' . uniqid();
mkdir($dir2);
file_put_contents("$dir2/.env", "A=1\nB=2\n");
file_put_contents("$dir2/.env.production", "A=9\n");
$d = Scanner::diffLabels($dir2, 'default', 'production');
check($d === ['onlyInA' => ['B'], 'onlyInB' => [], 'common' => ['A']], 'diff default vs production');
check(Scanner::syncLabels($dir2, 'default', 'production', true) === ['B'], 'sync --dry-run reports B');
check(!str_contains(file_get_contents("$dir2/.env.production"), 'B='), 'dry-run does not write');
check(Scanner::syncLabels($dir2, 'default', 'production') === ['B'], 'sync appends B');
$prod = file_get_contents("$dir2/.env.production");
check(str_contains($prod, "B=\n") && str_contains($prod, 'A=9') && !str_contains($prod, 'B=2'), 'sync copies no value');

echo $failures === 0 ? "\nAll tests passed\n" : "\n$failures test(s) failed\n";
exit($failures === 0 ? 0 : 1);
