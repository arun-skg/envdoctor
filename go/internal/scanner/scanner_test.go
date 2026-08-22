package scanner

import (
	"os"
	"path/filepath"
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
