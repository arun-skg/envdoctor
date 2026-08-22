// Command envdoctor is the native Go CLI for environment-variable auditing.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/arun-skg/envdoctor/go/internal/scanner"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	fs := flag.NewFlagSet("envdoctor", flag.ExitOnError)
	dir := fs.String("dir", ".", "Project root (default: cwd)")
	strict := fs.Bool("strict", false, "Treat warnings as errors")

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

	fmt.Println("ENVIRONMENT AUDIT")
	fmt.Println("========================================")
	errs := res.Errors()
	warns := res.Warnings()
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
