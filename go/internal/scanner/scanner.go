// Package scanner is the native Go implementation of envdoctor's core:
// reconcile environment variables used in Go source against those defined in
// .env files. Local-first — no network, values never printed.
package scanner

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
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
	envLine      = regexp.MustCompile(`^\s*(?:export\s+)?([A-Za-z_]\w*)\s*=(.*)$`)
)

// publicPrefixes are client-exposed env prefixes (case-sensitive, exact).
var publicPrefixes = []string{
	"NEXT_PUBLIC_",
	"VITE_",
	"REACT_APP_",
	"EXPO_PUBLIC_",
	"GATSBY_",
	"NUXT_PUBLIC_",
	"VUE_APP_",
	"PUBLIC_",
}

// secretName matches secret-looking variable names (case-insensitive).
var secretName = regexp.MustCompile(`(?i)SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|API_?KEY|ACCESS_?KEY|AUTH`)

// weakSecretValue matches weak/placeholder secret values (case-insensitive).
var weakSecretValue = regexp.MustCompile(`(?i)^(changeme|change_me|placeholder|x{3,}|todo|secret|password|passwd|test|example|sample|dummy|your[_-].*|<.*>|\$\{.*\})$`)

var (
	intRe   = regexp.MustCompile(`^-?\d+$`)
	floatRe = regexp.MustCompile(`^-?\d+\.\d+$`)
	urlRe   = regexp.MustCompile(`(?i)^https?://`)
)

func hasPublicPrefix(name string) bool {
	for _, p := range publicPrefixes {
		if strings.HasPrefix(name, p) {
			return true
		}
	}
	return false
}

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

// parseValue trims the RHS and strips one matching pair of surrounding quotes.
func parseValue(rhs string) string {
	v := strings.TrimSpace(rhs)
	if len(v) >= 2 && (v[0] == '\'' || v[0] == '"') && v[len(v)-1] == v[0] {
		v = v[1 : len(v)-1]
	}
	return v
}

// envLabel derives an environment label from a dotenv filename.
func envLabel(filename string) string {
	if filename == ".env" {
		return "default"
	}
	rest := strings.TrimPrefix(filename, ".env.")
	if rest == "local" {
		return "local"
	}
	rest = strings.TrimSuffix(rest, ".local")
	return rest
}

// InferType infers a coarse type from a value string.
func InferType(value string) string {
	if value == "" {
		return "empty"
	}
	if intRe.MatchString(value) {
		return "integer"
	}
	if floatRe.MatchString(value) {
		return "float"
	}
	if lv := strings.ToLower(value); lv == "true" || lv == "false" {
		return "boolean"
	}
	if urlRe.MatchString(value) {
		return "url"
	}
	if value[0] == '{' || value[0] == '[' {
		var js interface{}
		if json.Unmarshal([]byte(value), &js) == nil {
			return "json"
		}
	}
	return "string"
}

func compatGroup(inferred string) string {
	if inferred == "integer" || inferred == "float" {
		return "numeric"
	}
	return inferred
}

// Levenshtein computes the edit distance between two strings.
func Levenshtein(a, b string) int {
	ra, rb := []rune(a), []rune(b)
	if a == b {
		return 0
	}
	if len(ra) == 0 {
		return len(rb)
	}
	if len(rb) == 0 {
		return len(ra)
	}
	prev := make([]int, len(rb)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(ra); i++ {
		cur := make([]int, len(rb)+1)
		cur[0] = i
		for j := 1; j <= len(rb); j++ {
			cost := 1
			if ra[i-1] == rb[j-1] {
				cost = 0
			}
			cur[j] = min3(prev[j]+1, cur[j-1]+1, prev[j-1]+cost)
		}
		prev = cur
	}
	return prev[len(rb)]
}

func min3(a, b, c int) int {
	m := a
	if b < m {
		m = b
	}
	if c < m {
		m = c
	}
	return m
}

// def tracks a variable's first origin and its value per environment label.
type def struct {
	origin Origin
	values map[string]string // label -> value
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

// envOccurrence is one definition of a key in a dotenv file.
type envOccurrence struct {
	Origin Origin
	Value  string
}

// ParseEnv returns variable name -> all occurrences (in file order) for the
// definitions in a dotenv file. Collecting every occurrence lets callers both
// reconcile against the first origin and detect in-file duplicates.
func ParseEnv(path, content string) map[string][]envOccurrence {
	defined := map[string][]envOccurrence{}
	for i, raw := range strings.Split(content, "\n") {
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if m := envLine.FindStringSubmatch(raw); m != nil {
			defined[m[1]] = append(defined[m[1]], envOccurrence{
				Origin: Origin{File: path, Line: i + 1},
				Value:  parseValue(m[2]),
			})
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

func isEnvFile(base string) bool {
	return base == ".env" || (strings.HasPrefix(base, ".env.") && !strings.HasSuffix(base, ".example"))
}

// Scan reconciles .env definitions against .go source usage under root.
func Scan(root string) (Result, error) {
	defined := map[string]*def{}
	used := map[string]Origin{}
	projectLabels := map[string]bool{}
	var duplicates []Finding

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
		isEnv := isEnvFile(base)
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
			label := envLabel(base)
			projectLabels[label] = true
			for k, occ := range ParseEnv(rel, string(data)) {
				d, ok := defined[k]
				if !ok {
					d = &def{origin: occ[0].Origin, values: map[string]string{}}
					defined[k] = d
				}
				if _, seen := d.values[label]; !seen {
					d.values[label] = occ[0].Value
				}
				// Duplicate within a single file: 2+ occurrences of a key.
				if len(occ) >= 2 {
					lines := make([]string, len(occ))
					for i, o := range occ {
						lines[i] = strconv.Itoa(o.Origin.Line)
					}
					duplicates = append(duplicates, Finding{
						Rule: "duplicates", Severity: "error", Name: k,
						Message: fmt.Sprintf("defined %d times in the same file (lines %s)",
							len(occ), strings.Join(lines, ", ")),
						Origin: occ[0].Origin,
					})
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

	// --- Errors, in rule order ---

	// undefined-in-source: used but never defined.
	for _, name := range sortedOrigins(used) {
		if _, ok := defined[name]; !ok {
			res.Findings = append(res.Findings, Finding{
				Rule: "undefined-in-source", Severity: "error", Name: name,
				Message: "used in source code but not defined in any environment file",
				Origin:  used[name],
			})
		}
	}

	// duplicates: same key defined 2+ times within a single .env file.
	sort.Slice(duplicates, func(i, j int) bool { return duplicates[i].Name < duplicates[j].Name })
	res.Findings = append(res.Findings, duplicates...)

	// public-prefix: secret-looking var exposed to client bundles.
	for _, name := range sortedDefs(defined) {
		if hasPublicPrefix(name) && secretName.MatchString(name) {
			res.Findings = append(res.Findings, Finding{
				Rule: "public-prefix", Severity: "error", Name: name,
				Message: "secret-looking variable is exposed to client bundles via a public prefix",
				Origin:  defined[name].origin,
			})
		}
	}

	// type-mismatch: incompatible inferred types across environments.
	for _, name := range sortedDefs(defined) {
		d := defined[name]
		if len(d.values) < 2 {
			continue
		}
		groups := map[string]bool{}
		for _, v := range d.values {
			t := InferType(v)
			if t == "empty" {
				continue
			}
			groups[compatGroup(t)] = true
		}
		if len(groups) >= 2 {
			res.Findings = append(res.Findings, Finding{
				Rule: "type-mismatch", Severity: "error", Name: name,
				Message: "inferred type differs across environments",
				Origin:  d.origin,
			})
		}
	}

	// --- Warnings, in rule order ---

	// unused: defined but never referenced.
	for _, name := range sortedDefs(defined) {
		if _, ok := used[name]; !ok {
			res.Findings = append(res.Findings, Finding{
				Rule: "unused", Severity: "warning", Name: name,
				Message: "defined but never referenced in source",
				Origin:  defined[name].origin,
			})
		}
	}

	// environment-diff: defined in some but not all project env labels.
	if len(projectLabels) >= 2 {
		for _, name := range sortedDefs(defined) {
			present := sortedStrings(defined[name].values)
			var absent []string
			for label := range projectLabels {
				if _, ok := defined[name].values[label]; !ok {
					absent = append(absent, label)
				}
			}
			sort.Strings(absent)
			if len(present) > 0 && len(absent) > 0 {
				res.Findings = append(res.Findings, Finding{
					Rule: "environment-diff", Severity: "warning", Name: name,
					Message: fmt.Sprintf("defined in %s but missing in %s",
						strings.Join(present, ", "), strings.Join(absent, ", ")),
					Origin: defined[name].origin,
				})
			}
		}
	}

	// weak-secret: secret-looking name with a weak or placeholder value.
	for _, name := range sortedDefs(defined) {
		if !secretName.MatchString(name) {
			continue
		}
		d := defined[name]
		value, ok := d.values[envLabel(filepath.Base(d.origin.File))]
		if !ok {
			// Fall back to any recorded value deterministically.
			for _, label := range sortedStrings(d.values) {
				value = d.values[label]
				break
			}
		}
		if value == "" || len(value) < 8 || weakSecretValue.MatchString(value) {
			res.Findings = append(res.Findings, Finding{
				Rule: "weak-secret", Severity: "warning", Name: name,
				Message: "secret-looking variable has a weak or placeholder value",
				Origin:  d.origin,
			})
		}
	}

	// typo: used-but-undefined name close to a defined name.
	definedNames := sortedDefs(defined)
	for _, u := range sortedOrigins(used) {
		if _, ok := defined[u]; ok {
			continue
		}
		bestD := ""
		bestDist := 0
		for _, dName := range definedNames {
			if dName == u {
				continue
			}
			threshold := 2
			if minInt(len(u), len(dName)) <= 4 {
				threshold = 1
			}
			dist := Levenshtein(u, dName)
			if dist <= threshold && (bestD == "" || dist < bestDist) {
				bestD, bestDist = dName, dist
			}
		}
		if bestD != "" {
			res.Findings = append(res.Findings, Finding{
				Rule: "typo", Severity: "warning", Name: u,
				Message: fmt.Sprintf("%q is not defined; did you mean %q?", u, bestD),
				Origin:  used[u],
			})
		}
	}

	return res, nil
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func sortedOrigins(m map[string]Origin) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func sortedDefs(m map[string]*def) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func sortedStrings(m map[string]string) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// DefinedByLabel maps each environment label to the set of variable names
// defined in it (across all matching .env files).
func DefinedByLabel(root string) (map[string]map[string]bool, error) {
	labels := map[string]map[string]bool{}
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
		if !isEnvFile(info.Name()) {
			return nil
		}
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		rel, _ := filepath.Rel(root, path)
		label := envLabel(info.Name())
		set := labels[label]
		if set == nil {
			set = map[string]bool{}
			labels[label] = set
		}
		for k := range ParseEnv(rel, string(data)) {
			set[k] = true
		}
		return nil
	})
	return labels, err
}

func sortedSet(s map[string]bool) []string {
	out := make([]string, 0, len(s))
	for k := range s {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// Diff is the result of comparing two environment labels.
type Diff struct {
	OnlyInA []string `json:"onlyInA"`
	OnlyInB []string `json:"onlyInB"`
	Common  []string `json:"common"`
}

// DiffLabels compares the variable names defined in labels a and b.
func DiffLabels(root, a, b string) (Diff, error) {
	labels, err := DefinedByLabel(root)
	if err != nil {
		return Diff{}, err
	}
	da, db := labels[a], labels[b]
	d := Diff{OnlyInA: []string{}, OnlyInB: []string{}, Common: []string{}}
	for _, k := range sortedSet(da) {
		if db[k] {
			d.Common = append(d.Common, k)
		} else {
			d.OnlyInA = append(d.OnlyInA, k)
		}
	}
	for _, k := range sortedSet(db) {
		if !da[k] {
			d.OnlyInB = append(d.OnlyInB, k)
		}
	}
	return d, nil
}

// SyncLabels appends keys present in `from` but missing from `to` to to's file
// as `KEY=` placeholders. Values are never copied.
func SyncLabels(root, from, to string, dryRun bool) ([]string, error) {
	labels, err := DefinedByLabel(root)
	if err != nil {
		return nil, err
	}
	missing := []string{}
	for _, k := range sortedSet(labels[from]) {
		if !labels[to][k] {
			missing = append(missing, k)
		}
	}
	if len(missing) > 0 && !dryRun {
		target := filepath.Join(root, ".env")
		if to != "default" {
			target = filepath.Join(root, ".env."+to)
		}
		existing, _ := os.ReadFile(target)
		var b strings.Builder
		if len(existing) > 0 && existing[len(existing)-1] != '\n' {
			b.WriteString("\n")
		}
		for _, k := range missing {
			b.WriteString(k + "=\n")
		}
		f, ferr := os.OpenFile(target, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
		if ferr != nil {
			return nil, ferr
		}
		defer f.Close()
		if _, werr := f.WriteString(b.String()); werr != nil {
			return nil, werr
		}
	}
	return missing, nil
}
