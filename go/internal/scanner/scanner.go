// Package scanner is the native Go implementation of envdoctor's core:
// reconcile environment variables used in Go source against those defined in
// .env files. Local-first — no network, values never printed.
package scanner

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Origin is where a variable was seen.
type Origin struct {
	File string
	Line int
}

// Finding is one reported issue.
type Finding struct {
	Rule     string
	Severity string // "error" | "warning"
	Name     string
	Message  string
	Origin   Origin
}

// Result holds all findings from a scan.
type Result struct {
	Findings []Finding
}

// Errors returns only error-severity findings.
func (r Result) Errors() []Finding { return r.filter("error") }

// Warnings returns only warning-severity findings.
func (r Result) Warnings() []Finding { return r.filter("warning") }

func (r Result) filter(sev string) []Finding {
	var out []Finding
	for _, f := range r.Findings {
		if f.Severity == sev {
			out = append(out, f)
		}
	}
	return out
}

var usagePatterns = []*regexp.Regexp{
	regexp.MustCompile(`\bos\.Getenv\(\s*"([A-Za-z_]\w*)"`),
	regexp.MustCompile(`\bos\.LookupEnv\(\s*"([A-Za-z_]\w*)"`),
}

var (
	lineComment  = regexp.MustCompile(`(?m)//[^\n]*`)
	blockComment = regexp.MustCompile(`(?s)/\*.*?\*/`)
	envLine      = regexp.MustCompile(`^\s*(?:export\s+)?([A-Za-z_]\w*)\s*=`)
)

// blankMatch replaces every non-newline rune with a space to preserve offsets.
func blankMatch(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r == '\n' {
			b.WriteRune('\n')
		} else {
			b.WriteByte(' ')
		}
	}
	return b.String()
}

func stripNoise(code string) string {
	code = blockComment.ReplaceAllStringFunc(code, blankMatch)
	code = lineComment.ReplaceAllStringFunc(code, blankMatch)
	return code
}

// ScanSource returns variable name -> first origin for env usage in Go source.
func ScanSource(path, content string) map[string]Origin {
	text := stripNoise(content)
	used := map[string]Origin{}
	for _, re := range usagePatterns {
		for _, m := range re.FindAllStringSubmatchIndex(text, -1) {
			name := text[m[2]:m[3]]
			if _, ok := used[name]; ok {
				continue
			}
			line := strings.Count(text[:m[0]], "\n") + 1
			used[name] = Origin{File: path, Line: line}
		}
	}
	return used
}

// ParseEnv returns variable name -> origin for definitions in a dotenv file.
func ParseEnv(path, content string) map[string]Origin {
	defined := map[string]Origin{}
	for i, raw := range strings.Split(content, "\n") {
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if m := envLine.FindStringSubmatch(raw); m != nil {
			if _, ok := defined[m[1]]; !ok {
				defined[m[1]] = Origin{File: path, Line: i + 1}
			}
		}
	}
	return defined
}

func skipDir(name string) bool {
	switch name {
	case ".git", "vendor", "node_modules":
		return true
	}
	return false
}

// Scan reconciles .env definitions against .go source usage under root.
func Scan(root string) (Result, error) {
	defined := map[string]Origin{}
	used := map[string]Origin{}

	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			if skipDir(info.Name()) {
				return filepath.SkipDir
			}
			return nil
		}
		base := info.Name()
		isEnv := base == ".env" || (strings.HasPrefix(base, ".env.") && !strings.HasSuffix(base, ".example"))
		isGo := strings.HasSuffix(base, ".go")
		if !isEnv && !isGo {
			return nil
		}
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		rel, _ := filepath.Rel(root, path)
		if isEnv {
			for k, v := range ParseEnv(rel, string(data)) {
				if _, ok := defined[k]; !ok {
					defined[k] = v
				}
			}
		} else {
			for k, v := range ScanSource(rel, string(data)) {
				if _, ok := used[k]; !ok {
					used[k] = v
				}
			}
		}
		return nil
	})
	if err != nil {
		return Result{}, err
	}

	var res Result
	usedNames := sortedKeys(used)
	for _, name := range usedNames {
		if _, ok := defined[name]; !ok {
			res.Findings = append(res.Findings, Finding{
				Rule: "undefined-in-source", Severity: "error", Name: name,
				Message: "used in source code but not defined in any environment file",
				Origin:  used[name],
			})
		}
	}
	for _, name := range sortedKeys(defined) {
		if _, ok := used[name]; !ok {
			res.Findings = append(res.Findings, Finding{
				Rule: "unused", Severity: "warning", Name: name,
				Message: "defined but never referenced in source",
				Origin:  defined[name],
			})
		}
	}
	return res, nil
}

func sortedKeys(m map[string]Origin) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
