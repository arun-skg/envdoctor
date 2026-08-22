from pathlib import Path

from envdoctor.scanner import scan, scan_source_file


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


def test_clean_project_has_no_findings(tmp_path):
    _write(tmp_path, ".env", "DB_URL=x\n")
    _write(tmp_path, "app.py", "import os\nos.getenv('DB_URL')\n")
    result = scan(tmp_path)
    assert result.findings == []
