package scanner

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestScanSourceDetectsUsage(t *testing.T) {
	src := `package main
import "os"
// os.Getenv("COMMENTED")
func main() {
	_ = os.Getenv("DB_URL")
	_, _ = os.LookupEnv("PORT")
	/* os.Getenv("BLOCK_IGNORED") */
}
`
	used := ScanSource("main.go", src)
	if _, ok := used["DB_URL"]; !ok {
		t.Fatal("expected DB_URL")
	}
	if _, ok := used["PORT"]; !ok {
		t.Fatal("expected PORT")
	}
	if _, ok := used["COMMENTED"]; ok {
		t.Fatal("COMMENTED should be ignored (line comment)")
	}
	if _, ok := used["BLOCK_IGNORED"]; ok {
		t.Fatal("BLOCK_IGNORED should be ignored (block comment)")
	}
}

func TestScanReconciles(t *testing.T) {
	dir := t.TempDir()
	must(t, filepath.Join(dir, ".env"), "DB_URL=x\nUNUSED_KEY=1\n")
	must(t, filepath.Join(dir, "main.go"), "package main\nimport \"os\"\nfunc main(){ os.Getenv(\"DB_URL\"); os.Getenv(\"NEW_FLAG\") }\n")

	res, err := Scan(dir)
	if err != nil {
		t.Fatal(err)
	}
	errs := names(res.Errors())
	warns := names(res.Warnings())
	if !errs["NEW_FLAG"] {
		t.Fatalf("expected NEW_FLAG error, got %v", errs)
	}
	if !warns["UNUSED_KEY"] {
		t.Fatalf("expected UNUSED_KEY warning, got %v", warns)
	}
	if errs["DB_URL"] || warns["DB_URL"] {
		t.Fatal("DB_URL should be reconciled")
	}
}

func TestDuplicates(t *testing.T) {
	dir := t.TempDir()
	must(t, filepath.Join(dir, ".env"), "DB_URL=a\nDB_URL=b\nSOLO=1\n")
	must(t, filepath.Join(dir, "main.go"), "package main\nimport \"os\"\nfunc main(){ os.Getenv(\"DB_URL\"); os.Getenv(\"SOLO\") }\n")

	res, err := Scan(dir)
	if err != nil {
		t.Fatal(err)
	}
	var dups []Finding
	for _, f := range res.Findings {
		if f.Rule == "duplicates" {
			dups = append(dups, f)
		}
	}
	if len(dups) != 1 {
		t.Fatalf("expected 1 duplicate finding, got %d: %v", len(dups), dups)
	}
	if dups[0].Name != "DB_URL" || dups[0].Severity != "error" {
		t.Fatalf("unexpected duplicate finding: %+v", dups[0])
	}
	if want := "lines 1, 2"; !contains(dups[0].Message, want) {
		t.Fatalf("message %q should contain %q", dups[0].Message, want)
	}
	// First occurrence reconciles: DB_URL is neither undefined nor unused.
	if warns := names(res.Warnings()); warns["DB_URL"] {
		t.Fatal("DB_URL should be reconciled, not unused")
	}
}

func TestPublicPrefix(t *testing.T) {
	dir := t.TempDir()
	must(t, filepath.Join(dir, ".env"), "NEXT_PUBLIC_API_KEY=x\nPUBLIC_URL=x\nAPI_KEY=x\n")
	must(t, filepath.Join(dir, "main.go"), "package main\nfunc main(){}\n")

	res, err := Scan(dir)
	if err != nil {
		t.Fatal(err)
	}
	pp := map[string]bool{}
	for _, f := range res.Findings {
		if f.Rule == "public-prefix" {
			if f.Severity != "error" {
				t.Fatalf("public-prefix should be error, got %s", f.Severity)
			}
			pp[f.Name] = true
		}
	}
	if !pp["NEXT_PUBLIC_API_KEY"] {
		t.Fatalf("expected NEXT_PUBLIC_API_KEY flagged, got %v", pp)
	}
	if pp["PUBLIC_URL"] {
		t.Fatal("PUBLIC_URL should not be flagged (not secret-like)")
	}
	if pp["API_KEY"] {
		t.Fatal("API_KEY should not be flagged (no public prefix)")
	}
}

func TestInferType(t *testing.T) {
	cases := map[string]string{
		"":          "empty",
		"3000":      "integer",
		"-7":        "integer",
		"1.5":       "float",
		"TRUE":      "boolean",
		"https://x": "url",
		`{"a":1}`:   "json",
		"hello":     "string",
	}
	for in, want := range cases {
		if got := InferType(in); got != want {
			t.Fatalf("InferType(%q)=%q want %q", in, got, want)
		}
	}
}

func TestLevenshtein(t *testing.T) {
	if Levenshtein("abc", "abc") != 0 {
		t.Fatal("equal strings should be 0")
	}
	if Levenshtein("DATBASE_URL", "DATABASE_URL") != 1 {
		t.Fatal("expected distance 1")
	}
}

func TestWeakSecret(t *testing.T) {
	dir := t.TempDir()
	must(t, filepath.Join(dir, ".env"), "API_KEY=changeme\nSTRONG_TOKEN=s0m3-l0ng-r4nd0m\nSHORT_SECRET=abc\n")
	must(t, filepath.Join(dir, "main.go"), "package main\nfunc main(){}\n")

	res, err := Scan(dir)
	if err != nil {
		t.Fatal(err)
	}
	weak := map[string]bool{}
	for _, f := range res.Findings {
		if f.Rule == "weak-secret" {
			weak[f.Name] = true
		}
	}
	if !weak["API_KEY"] {
		t.Fatal("API_KEY (placeholder) should be weak")
	}
	if !weak["SHORT_SECRET"] {
		t.Fatal("SHORT_SECRET (too short) should be weak")
	}
	if weak["STRONG_TOKEN"] {
		t.Fatal("STRONG_TOKEN should not be weak")
	}
	// No value must leak into any message.
	for _, f := range res.Findings {
		if strings.Contains(f.Message, "changeme") || strings.Contains(f.Message, "s0m3") {
			t.Fatalf("value leaked into message: %q", f.Message)
		}
	}
}

func TestTypoSuggestion(t *testing.T) {
	dir := t.TempDir()
	must(t, filepath.Join(dir, ".env"), "DATABASE_URL=postgres://x\n")
	must(t, filepath.Join(dir, "main.go"), "package main\nimport \"os\"\nfunc main(){ os.Getenv(\"DATBASE_URL\") }\n")

	res, err := Scan(dir)
	if err != nil {
		t.Fatal(err)
	}
	var typos []Finding
	for _, f := range res.Findings {
		if f.Rule == "typo" {
			typos = append(typos, f)
		}
	}
	if len(typos) != 1 || typos[0].Name != "DATBASE_URL" {
		t.Fatalf("expected one typo for DATBASE_URL, got %v", typos)
	}
	if !strings.Contains(typos[0].Message, `did you mean "DATABASE_URL"`) {
		t.Fatalf("unexpected message %q", typos[0].Message)
	}
	// undefined-in-source still fires too.
	if !names(res.Errors())["DATBASE_URL"] {
		t.Fatal("undefined-in-source should still fire for DATBASE_URL")
	}
}

func TestEnvironmentDiff(t *testing.T) {
	dir := t.TempDir()
	must(t, filepath.Join(dir, ".env"), "SHARED=1\n")
	must(t, filepath.Join(dir, ".env.production"), "SHARED=1\nONLY_PROD=1\n")
	must(t, filepath.Join(dir, "main.go"), "package main\nfunc main(){}\n")

	res, err := Scan(dir)
	if err != nil {
		t.Fatal(err)
	}
	diffs := map[string]Finding{}
	for _, f := range res.Findings {
		if f.Rule == "environment-diff" {
			diffs[f.Name] = f
		}
	}
	f, ok := diffs["ONLY_PROD"]
	if !ok {
		t.Fatalf("expected ONLY_PROD diff, got %v", diffs)
	}
	if !strings.Contains(f.Message, "production") || !strings.Contains(f.Message, "default") {
		t.Fatalf("unexpected diff message %q", f.Message)
	}
	if _, ok := diffs["SHARED"]; ok {
		t.Fatal("SHARED present in both, should not diff")
	}
}

func TestTypeMismatch(t *testing.T) {
	dir := t.TempDir()
	must(t, filepath.Join(dir, ".env"), "PORT=3000\nHOST=8080\n")
	must(t, filepath.Join(dir, ".env.production"), "PORT=abc\nHOST=9090\n")
	must(t, filepath.Join(dir, "main.go"), "package main\nfunc main(){}\n")

	res, err := Scan(dir)
	if err != nil {
		t.Fatal(err)
	}
	mm := map[string]Finding{}
	for _, f := range res.Findings {
		if f.Rule == "type-mismatch" {
			mm[f.Name] = f
		}
	}
	if _, ok := mm["PORT"]; !ok {
		t.Fatal("PORT should mismatch (integer vs string)")
	}
	if mm["PORT"].Severity != "error" {
		t.Fatal("type-mismatch should be error")
	}
	if _, ok := mm["HOST"]; ok {
		t.Fatal("HOST integer vs integer should not mismatch")
	}
	if strings.Contains(mm["PORT"].Message, "3000") || strings.Contains(mm["PORT"].Message, "abc") {
		t.Fatal("value leaked into type-mismatch message")
	}
}

func contains(s, sub string) bool { return strings.Contains(s, sub) }

func must(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func names(fs []Finding) map[string]bool {
	m := map[string]bool{}
	for _, f := range fs {
		m[f.Name] = true
	}
	return m
}

func TestDiffAndSync(t *testing.T) {
	dir := t.TempDir()
	must(t, filepath.Join(dir, ".env"), "A=1\nB=2\n")
	must(t, filepath.Join(dir, ".env.production"), "A=9\n")

	d, err := DiffLabels(dir, "default", "production")
	if err != nil {
		t.Fatal(err)
	}
	if len(d.OnlyInA) != 1 || d.OnlyInA[0] != "B" || len(d.OnlyInB) != 0 || len(d.Common) != 1 || d.Common[0] != "A" {
		t.Fatalf("unexpected diff: %+v", d)
	}

	// dry-run does not write
	m, _ := SyncLabels(dir, "default", "production", true)
	if len(m) != 1 || m[0] != "B" {
		t.Fatalf("dry-run missing: %v", m)
	}
	data, _ := os.ReadFile(filepath.Join(dir, ".env.production"))
	if strings.Contains(string(data), "B=") {
		t.Fatal("dry-run should not write")
	}

	// real sync appends B= (no value), keeps A's value
	SyncLabels(dir, "default", "production", false)
	data, _ = os.ReadFile(filepath.Join(dir, ".env.production"))
	if !strings.Contains(string(data), "B=\n") || !strings.Contains(string(data), "A=9") || strings.Contains(string(data), "B=2") {
		t.Fatalf("bad synced file: %q", string(data))
	}
}
