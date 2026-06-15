package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
	"github.com/dcstolf/speccraft/tools/internal/speccraft/drift"
)

const version = "1.1.0"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "--version", "-v":
		fmt.Println(version)

	case "scan-file":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "usage: speccraft-drift scan-file <path>")
			os.Exit(1)
		}
		if err := scanFile(os.Args[2]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}

	case "scan-all":
		if err := scanAll(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}

	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand: %s\n", os.Args[1])
		usage()
		os.Exit(1)
	}
}

func scanFile(path string) error {
	root, err := speccraft.FindRoot("")
	if err != nil {
		return nil // not a speccraft repo; silently succeed
	}

	rules, err := drift.LoadRules(root)
	if err != nil {
		return err
	}

	absPath, _ := filepath.Abs(path)
	violations, err := drift.CheckFile(absPath, root, rules)
	if err != nil {
		return err
	}

	for _, v := range violations {
		fmt.Println(v)
	}
	return nil
}

func scanAll() error {
	root, err := speccraft.FindRoot("")
	if err != nil {
		return nil
	}

	rules, err := drift.LoadRules(root)
	if err != nil {
		return err
	}

	violations, err := drift.CheckAll(root, rules)
	if err != nil {
		return err
	}

	for _, v := range violations {
		fmt.Println(v)
	}
	return nil
}

func usage() {
	fmt.Fprintln(os.Stderr, `speccraft-drift — regex-based drift detection

Usage:
  speccraft-drift scan-file <path>    Scan a single file against enforce: rules
  speccraft-drift scan-all            Scan entire repo against enforce: rules
  speccraft-drift --version           Print version`)
}
