package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

const version = "1.0.0"

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run is the testable entrypoint. Returns the exit code.
func run(args []string, stdout, stderr io.Writer) int {
	if len(args) < 1 {
		usage(stderr)
		return 1
	}

	switch args[0] {
	case "--version", "-v":
		fmt.Fprintln(stdout, version)
		return 0

	case "find-root":
		root, err := speccraft.FindRoot("")
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		fmt.Fprintln(stdout, root)
		return 0

	case "init":
		// Sanctioned creation path for .speccraft/state.json (spec 0012).
		// Idempotent: if state.json already exists, succeed silently.
		// Resolves repo root by walking up from CWD to a directory
		// containing .speccraft/.
		root, err := speccraft.FindRoot("")
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		if err := speccraft.InitState(root); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return 0

	case "get":
		if len(args) < 2 {
			fmt.Fprintln(stderr, "usage: speccraft-state get <field>")
			return 1
		}
		root, err := speccraft.FindRoot("")
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return doGet(root, args[1], stdout, stderr)

	case "set":
		if len(args) < 3 {
			fmt.Fprintln(stderr, "usage: speccraft-state set <field> <value>")
			return 1
		}
		root, err := speccraft.FindRoot("")
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return doSet(root, args[1], args[2], stderr)

	case "rust-baseline":
		if len(args) < 2 {
			fmt.Fprintln(stderr, "usage: speccraft-state rust-baseline append <json-array>")
			return 1
		}
		root, err := speccraft.FindRoot("")
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return doRustBaseline(root, args[1:], stdout, stderr)

	case "track-edit":
		if len(args) < 2 {
			fmt.Fprintln(stderr, "usage: speccraft-state track-edit <file>")
			return 1
		}
		root, err := speccraft.FindRoot("")
		if err != nil {
			return 0
		}
		if err := speccraft.TrackEdit(root, args[1]); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return 0

	case "reset-session":
		root, err := speccraft.FindRoot("")
		if err != nil {
			return 0
		}
		if err := speccraft.ResetSession(root); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return 0

	case "tasks-done-pct":
		root, err := speccraft.FindRoot("")
		if err != nil {
			fmt.Fprintln(stdout, "0")
			return 0
		}
		pct, err := speccraft.TasksDonePct(root)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		fmt.Fprintln(stdout, pct)
		return 0

	default:
		fmt.Fprintf(stderr, "unknown subcommand: %s\n", args[0])
		usage(stderr)
		return 1
	}
}

func doGet(root, field string, stdout, stderr io.Writer) int {
	switch field {
	case "rust_test_baseline":
		ids, err := speccraft.GetRustBaseline(root)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		out, _ := json.Marshal(ids)
		fmt.Fprintln(stdout, string(out))
		return 0
	case "rust_gate_fingerprint":
		fp, err := speccraft.GetRustFingerprint(root)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		if fp == "" {
			fmt.Fprintln(stdout, "null")
		} else {
			fmt.Fprintln(stdout, fp)
		}
		return 0
	default:
		val, err := speccraft.GetField(root, field)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		if val == "" {
			fmt.Fprintln(stdout, "null")
		} else {
			fmt.Fprintln(stdout, val)
		}
		return 0
	}
}

func doSet(root, field, value string, stderr io.Writer) int {
	switch field {
	case "rust_test_baseline":
		var ids []string
		if err := json.Unmarshal([]byte(value), &ids); err != nil {
			fmt.Fprintf(stderr, "set rust_test_baseline: invalid json array: %v\n", err)
			return 1
		}
		if err := speccraft.SetRustBaseline(root, ids); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return 0
	case "rust_gate_fingerprint":
		if err := speccraft.SetRustFingerprint(root, strings.TrimSpace(value)); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return 0
	default:
		if err := speccraft.SetField(root, field, value); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return 0
	}
}

func doRustBaseline(root string, args []string, stdout, stderr io.Writer) int {
	switch args[0] {
	case "append":
		if len(args) < 2 {
			fmt.Fprintln(stderr, "usage: speccraft-state rust-baseline append <json-array>")
			return 1
		}
		var ids []string
		if err := json.Unmarshal([]byte(args[1]), &ids); err != nil {
			fmt.Fprintf(stderr, "rust-baseline append: invalid json array: %v\n", err)
			return 1
		}
		if err := speccraft.AppendRustBaseline(root, ids); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return 0
	case "recapture":
		count, err := speccraft.RecaptureRustBaseline(root)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		fmt.Fprintf(stdout, "recaptured: %d tests\n", count)
		return 0
	default:
		fmt.Fprintf(stderr, "rust-baseline: unknown action %q\n", args[0])
		return 1
	}
}

func usage(w io.Writer) {
	fmt.Fprintln(w, `speccraft-state — speccraft runtime state helper

Usage:
  speccraft-state find-root              Find repo root (dir with .speccraft/)
  speccraft-state init                   Create empty state.json if absent (idempotent)
  speccraft-state get <field>            Read a field from state.json
  speccraft-state set <field> <value>    Write a field to state.json
  speccraft-state rust-baseline append <json-array>
                                          Merge IDs into rust_test_baseline (deduped, sorted)
  speccraft-state track-edit <file>      Record a file edit in the session
  speccraft-state reset-session          Clear session.* fields (SessionStart)
  speccraft-state tasks-done-pct         % of [x] tasks in active spec's tasks.md
  speccraft-state --version              Print version`)
}
