package main

import (
	"fmt"
	"os"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

const version = "1.0.0"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "--version", "-v":
		fmt.Println(version)

	case "find-root":
		root, err := speccraft.FindRoot("")
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Println(root)

	case "get":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "usage: speccraft-state get <field>")
			os.Exit(1)
		}
		root, err := speccraft.FindRoot("")
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		val, err := speccraft.GetField(root, os.Args[2])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if val == "" {
			fmt.Println("null")
		} else {
			fmt.Println(val)
		}

	case "set":
		if len(os.Args) < 4 {
			fmt.Fprintln(os.Stderr, "usage: speccraft-state set <field> <value>")
			os.Exit(1)
		}
		root, err := speccraft.FindRoot("")
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if err := speccraft.SetField(root, os.Args[2], os.Args[3]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}

	case "track-edit":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "usage: speccraft-state track-edit <file>")
			os.Exit(1)
		}
		root, err := speccraft.FindRoot("")
		if err != nil {
			// Not a speccraft repo; silently ignore.
			os.Exit(0)
		}
		if err := speccraft.TrackEdit(root, os.Args[2]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}

	case "reset-session":
		root, err := speccraft.FindRoot("")
		if err != nil {
			os.Exit(0)
		}
		if err := speccraft.ResetSession(root); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}

	case "tasks-done-pct":
		root, err := speccraft.FindRoot("")
		if err != nil {
			fmt.Println("0")
			os.Exit(0)
		}
		pct, err := speccraft.TasksDonePct(root)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Println(pct)

	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand: %s\n", os.Args[1])
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `speccraft-state — speccraft runtime state helper

Usage:
  speccraft-state find-root              Find repo root (dir with .speccraft/)
  speccraft-state get <field>            Read a field from state.json
  speccraft-state set <field> <value>    Write a field to state.json
  speccraft-state track-edit <file>      Record a file edit in the session
  speccraft-state reset-session          Clear session.* fields (SessionStart)
  speccraft-state tasks-done-pct         % of [x] tasks in active spec's tasks.md
  speccraft-state --version              Print version`)
}
