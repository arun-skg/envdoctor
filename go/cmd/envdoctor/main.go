// Command envdoctor is the native Go CLI for environment-variable auditing.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/arun-skg/envdoctor/go/internal/scanner"
)

type diffJSON struct {
	A       string   `json:"a"`
	B       string   `json:"b"`
	OnlyInA []string `json:"onlyInA"`
	OnlyInB []string `json:"onlyInB"`
	Common  []string `json:"common"`
}

type syncJSON struct {
	From   string   `json:"from"`
	To     string   `json:"to"`
	Added  []string `json:"added"`
	DryRun bool     `json:"dryRun"`
}

// parseSub extracts positional args and the shared flags for diff/sync.
func parseSub(args []string) (pos []string, dir string, dryRun, asJSON bool) {
	dir = "."
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-d" || a == "--dir":
			if i+1 < len(args) {
				i++
				dir = args[i]
			}
		case strings.HasPrefix(a, "--dir="):
			dir = a[len("--dir="):]
		case a == "--dry-run":
			dryRun = true
		case a == "--json":
			asJSON = true
		default:
			pos = append(pos, a)
		}
	}
	return
}

func runDiff(args []string) int {
	pos, dir, _, asJSON := parseSub(args)
	if len(pos) < 2 {
		fmt.Fprintln(os.Stderr, "usage: envdoctor diff <a> <b>")
		return 2
	}
	a, b := pos[0], pos[1]
	d, err := scanner.DiffLabels(dir, a, b)
	if err != nil {
		fmt.Fprintln(os.Stderr, "envdoctor: "+err.Error())
		return 2
	}
	if asJSON {
		data, _ := json.Marshal(diffJSON{A: a, B: b, OnlyInA: d.OnlyInA, OnlyInB: d.OnlyInB, Common: d.Common})
		fmt.Println(string(data))
		return 0
	}
	fmt.Printf("ENVIRONMENT DIFF: %s vs %s\n", a, b)
	fmt.Println("========================================")
	if len(d.OnlyInA) > 0 {
		fmt.Printf("Only in %s:\n", a)
		for _, k := range d.OnlyInA {
			fmt.Printf("  + %s\n", k)
		}
	}
	if len(d.OnlyInB) > 0 {
		fmt.Printf("Only in %s:\n", b)
		for _, k := range d.OnlyInB {
			fmt.Printf("  + %s\n", k)
		}
	}
	fmt.Printf("Common: %d variable(s)\n", len(d.Common))
	return 0
}

func runSync(args []string) int {
	pos, dir, dryRun, asJSON := parseSub(args)
	if len(pos) < 2 {
		fmt.Fprintln(os.Stderr, "usage: envdoctor sync <from> <to>")
		return 2
	}
	from, to := pos[0], pos[1]
	added, err := scanner.SyncLabels(dir, from, to, dryRun)
	if err != nil {
		fmt.Fprintln(os.Stderr, "envdoctor: "+err.Error())
		return 2
	}
	if asJSON {
		data, _ := json.Marshal(syncJSON{From: from, To: to, Added: added, DryRun: dryRun})
		fmt.Println(string(data))
		return 0
	}
	if len(added) == 0 {
		fmt.Println("Already in sync.")
		return 0
	}
	verb := "Synced"
	if dryRun {
		verb = "Would sync"
	}
	fmt.Printf("%s %d variable(s) from %s to %s:\n", verb, len(added), from, to)
	for _, k := range added {
		fmt.Printf("  + %s\n", k)
	}
	return 0
}

func main() {
	os.Exit(run(os.Args[1:]))
}

// jsonFinding is the exact serialization shape. Values are never included.
type jsonFinding struct {
	Rule     string  `json:"rule"`
	Severity string  `json:"severity"`
	Name     string  `json:"name"`
	Message  string  `json:"message"`
	File     *string `json:"file"`
	Line     *int    `json:"line"`
}

func toJSON(findings []scanner.Finding) []jsonFinding {
	out := make([]jsonFinding, 0, len(findings))
	for _, f := range findings {
		jf := jsonFinding{Rule: f.Rule, Severity: f.Severity, Name: f.Name, Message: f.Message}
		if f.Origin.File != "" {
			file := f.Origin.File
			line := f.Origin.Line
			jf.File = &file
			jf.Line = &line
		}
		out = append(out, jf)
	}
	return out
}

func run(args []string) int {
	if len(args) > 0 && args[0] == "diff" {
		return runDiff(args[1:])
	}
	if len(args) > 0 && args[0] == "sync" {
		return runSync(args[1:])
	}

	fs := flag.NewFlagSet("envdoctor", flag.ExitOnError)
	dir := fs.String("dir", ".", "Project root (default: cwd)")
	strict := fs.Bool("strict", false, "Treat warnings as errors")
	asJSON := fs.Bool("json", false, "Emit findings as JSON")

	// Support "envdoctor scan [flags]".
	if len(args) > 0 && args[0] == "scan" {
		args = args[1:]
	}
	_ = fs.Parse(args)

	res, err := scanner.Scan(*dir)
	if err != nil {
		fmt.Fprintln(os.Stderr, "envdoctor: "+err.Error())
		return 2
	}

	errs := res.Errors()
	warns := res.Warnings()

	if *asJSON {
		data, mErr := json.Marshal(toJSON(res.Findings))
		if mErr != nil {
			fmt.Fprintln(os.Stderr, "envdoctor: "+mErr.Error())
			return 2
		}
		fmt.Println(string(data))
		if len(errs) > 0 || (*strict && len(warns) > 0) {
			return 1
		}
		return 0
	}

	fmt.Println("ENVIRONMENT AUDIT")
	fmt.Println("========================================")
	if len(res.Findings) == 0 {
		fmt.Println("\nNo issues found.")
		return 0
	}
	if len(errs) > 0 {
		fmt.Println("\nErrors")
		for _, f := range errs {
			fmt.Printf("  x %s %s:%d  %s\n", f.Name, f.Origin.File, f.Origin.Line, f.Message)
		}
	}
	if len(warns) > 0 {
		fmt.Println("\nWarnings")
		for _, f := range warns {
			fmt.Printf("  ! %s %s:%d  %s\n", f.Name, f.Origin.File, f.Origin.Line, f.Message)
		}
	}
	fmt.Printf("\nSummary: %d error(s), %d warning(s)\n", len(errs), len(warns))

	if len(errs) > 0 || (*strict && len(warns) > 0) {
		return 1
	}
	return 0
}
