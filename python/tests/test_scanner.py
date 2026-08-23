import json
from pathlib import Path

from envdoctor.cli import main
from envdoctor.scanner import (
    finding_to_dict,
    infer_type,
    levenshtein,
    scan,
    scan_source_file,
)


def _write(tmp_path: Path, name: str, content: str) -> Path:
    p = tmp_path / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    return p


def test_detects_all_usage_forms(tmp_path):
    src = _write(
        tmp_path,
        "app.py",
        "import os\n"
        "from os import environ\n"
        "# os.getenv('COMMENTED')\n"
        "a = os.getenv('DB_URL')\n"
        "b = os.environ.get('PORT')\n"
        "c = os.environ['API_KEY']\n"
        "d = environ.get('HOST')\n"
        "e = environ['DB_USER']\n"
        '"""docstring os.getenv("DOC_IGNORED")"""\n',
    )
    used = scan_source_file(src)
    assert set(used) == {"DB_URL", "PORT", "API_KEY", "HOST", "DB_USER"}
    assert "COMMENTED" not in used
    assert "DOC_IGNORED" not in used


def test_missing_and_unused(tmp_path):
    _write(tmp_path, ".env", "DB_URL=postgres://x\nUNUSED_KEY=1\n")
    _write(tmp_path, "app.py", "import os\nos.getenv('DB_URL')\nos.getenv('NEW_FLAG')\n")

    result = scan(tmp_path)
    errors = {f.name for f in result.errors}
    warnings = {f.name for f in result.warnings}

    assert "NEW_FLAG" in errors  # used but not defined
    assert "UNUSED_KEY" in warnings  # defined but not used
    assert "DB_URL" not in errors and "DB_URL" not in warnings  # reconciled


def test_duplicates(tmp_path):
    _write(tmp_path, ".env", "DB_URL=a\nDB_URL=b\nSOLO=1\n")
    _write(tmp_path, "app.py", "import os\nos.getenv('DB_URL')\nos.getenv('SOLO')\n")

    result = scan(tmp_path)
    dups = [f for f in result.findings if f.rule == "duplicates"]
    assert len(dups) == 1
    assert dups[0].name == "DB_URL"
    assert dups[0].severity == "error"
    assert "lines 1, 2" in dups[0].message
    # Single-definition key is not reported as a duplicate.
    assert "SOLO" not in {f.name for f in dups}
    # First occurrence still reconciles: DB_URL is not undefined/unused.
    assert "DB_URL" not in {f.name for f in result.warnings}


def test_public_prefix(tmp_path):
    _write(
        tmp_path,
        ".env",
        "NEXT_PUBLIC_API_KEY=x\nPUBLIC_URL=x\nAPI_KEY=x\n",
    )
    result = scan(tmp_path)
    pp = [f for f in result.findings if f.rule == "public-prefix"]
    names = {f.name for f in pp}
    assert names == {"NEXT_PUBLIC_API_KEY"}
    assert pp[0].severity == "error"
    assert "PUBLIC_URL" not in names  # public prefix but not secret-like
    assert "API_KEY" not in names  # secret-like but no public prefix


def test_clean_project_has_no_findings(tmp_path):
    _write(tmp_path, ".env", "DB_URL=x\n")
    _write(tmp_path, "app.py", "import os\nos.getenv('DB_URL')\n")
    result = scan(tmp_path)
    assert result.findings == []


def test_infer_type():
    assert infer_type("") == "empty"
    assert infer_type("3000") == "integer"
    assert infer_type("-7") == "integer"
    assert infer_type("1.5") == "float"
    assert infer_type("TRUE") == "boolean"
    assert infer_type("https://x.io") == "url"
    assert infer_type('{"a":1}') == "json"
    assert infer_type("hello") == "string"


def test_levenshtein():
    assert levenshtein("abc", "abc") == 0
    assert levenshtein("DATBASE_URL", "DATABASE_URL") == 1


def test_weak_secret(tmp_path):
    _write(
        tmp_path,
        ".env",
        "API_KEY=changeme\nSTRONG_TOKEN=s0m3-l0ng-r4nd0m-value\nSHORT_SECRET=abc\n",
    )
    _write(tmp_path, "app.py", "import os\n")
    result = scan(tmp_path)
    weak = {f.name for f in result.findings if f.rule == "weak-secret"}
    assert "API_KEY" in weak  # placeholder
    assert "SHORT_SECRET" in weak  # too short
    assert "STRONG_TOKEN" not in weak
    for f in result.findings:
        assert f.severity in ("error", "warning")
        # value must never appear anywhere in a finding
        assert "changeme" not in f.message
        assert "s0m3" not in f.message


def test_typo_suggestion(tmp_path):
    _write(tmp_path, ".env", "DATABASE_URL=postgres://x\n")
    _write(tmp_path, "app.py", "import os\nos.getenv('DATBASE_URL')\n")
    result = scan(tmp_path)
    typos = [f for f in result.findings if f.rule == "typo"]
    assert len(typos) == 1
    assert typos[0].name == "DATBASE_URL"
    assert typos[0].severity == "warning"
    assert 'did you mean "DATABASE_URL"' in typos[0].message
    # undefined-in-source still fires too.
    assert "DATBASE_URL" in {f.name for f in result.errors}


def test_environment_diff(tmp_path):
    _write(tmp_path, ".env", "SHARED=1\n")
    _write(tmp_path, ".env.production", "SHARED=1\nONLY_PROD=1\n")
    _write(tmp_path, "app.py", "import os\n")
    result = scan(tmp_path)
    diffs = {f.name: f for f in result.findings if f.rule == "environment-diff"}
    assert "ONLY_PROD" in diffs
    assert diffs["ONLY_PROD"].severity == "warning"
    assert "default" in diffs["ONLY_PROD"].message
    assert "production" in diffs["ONLY_PROD"].message
    assert "SHARED" not in diffs  # present in both


def test_type_mismatch(tmp_path):
    _write(tmp_path, ".env", "PORT=3000\nHOST=8080\n")
    _write(tmp_path, ".env.production", "PORT=abc\nHOST=9090\n")
    _write(tmp_path, "app.py", "import os\n")
    result = scan(tmp_path)
    mismatches = {f.name for f in result.findings if f.rule == "type-mismatch"}
    assert "PORT" in mismatches  # integer vs string
    assert "HOST" not in mismatches  # integer vs integer, same group
    tm = next(f for f in result.findings if f.rule == "type-mismatch")
    assert tm.severity == "error"
    assert "3000" not in tm.message and "abc" not in tm.message


def test_json_output_shape(tmp_path, capsys):
    _write(tmp_path, ".env", "API_KEY=changeme\n")
    _write(tmp_path, "app.py", "import os\nos.getenv('DATBASE_URL')\n")
    _write(tmp_path, ".env.production", "API_KEY=changeme\nDATABASE_URL=x\n")
    code = main(["scan", "--dir", str(tmp_path), "--json"])
    assert code == 1  # undefined-in-source is an error
    out = capsys.readouterr().out
    data = json.loads(out)
    assert isinstance(data, list)
    for obj in data:
        assert set(obj) == {"rule", "severity", "name", "message", "file", "line"}
    # no value strings leak
    assert "changeme" not in out


def test_finding_to_dict_shape(tmp_path):
    _write(tmp_path, ".env", "UNUSED=1\n")
    _write(tmp_path, "app.py", "import os\n")
    result = scan(tmp_path)
    d = finding_to_dict(result.findings[0], tmp_path)
    assert d["file"] == ".env"
    assert isinstance(d["line"], int)


def test_diff_and_sync(tmp_path):
    from envdoctor.scanner import diff_labels, sync_labels

    (tmp_path / ".env").write_text("A=1\nB=2\n")
    (tmp_path / ".env.production").write_text("A=9\n")

    d = diff_labels(tmp_path, "default", "production")
    assert d == {"onlyInA": ["B"], "onlyInB": [], "common": ["A"]}

    # dry-run does not write
    assert sync_labels(tmp_path, "default", "production", dry_run=True) == ["B"]
    assert "B=" not in (tmp_path / ".env.production").read_text()

    # real sync appends B= (no value copied) and leaves A's value intact
    assert sync_labels(tmp_path, "default", "production") == ["B"]
    prod = (tmp_path / ".env.production").read_text()
    assert "B=\n" in prod and "A=9" in prod and "B=2" not in prod
    assert diff_labels(tmp_path, "default", "production")["common"] == ["A", "B"]
