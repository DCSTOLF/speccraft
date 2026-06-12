// Package runner is the language-neutral test-runner invocation primitive
// introduced by spec 0005. It defines the Runner interface that
// per-language adapters implement, the normalized record/outcome types
// that speccraft-guard consumes, and an AdapterFor factory that picks
// the right Rust adapter from speccraft.toml config.
package runner

import (
	"context"
	"strings"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// splitCommand splits a configured command line into its binary and base args,
// falling back to the default when the configured command is empty. The
// per-test targeting flags are appended by each adapter.
func splitCommand(cmd, fallback string) (string, []string) {
	fields := strings.Fields(cmd)
	if len(fields) == 0 {
		fields = strings.Fields(fallback)
	}
	if len(fields) == 0 {
		return "", nil
	}
	return fields[0], append([]string{}, fields[1:]...)
}

// Outcome is the high-level result of a runner invocation. Spec 0005 §What.3.
type Outcome int

const (
	// OutcomeBuildFailed: runner exited non-zero with compile errors. NOT a valid red state.
	OutcomeBuildFailed Outcome = iota
	// OutcomeAllPassed: runner exited zero with no failures in normalized records.
	OutcomeAllPassed
	// OutcomeAtLeastOneFailed: runner exited non-zero with at least one failing record.
	OutcomeAtLeastOneFailed
)

// String returns the snake_case form used in error messages and logs.
func (o Outcome) String() string {
	switch o {
	case OutcomeBuildFailed:
		return "build_failed"
	case OutcomeAllPassed:
		return "all_passed"
	case OutcomeAtLeastOneFailed:
		return "at_least_one_failed"
	default:
		return "unknown"
	}
}

// TestRecord is the normalized per-test result an adapter emits.
// TestName is the canonical fully-qualified libtest form (spec §What.3),
// with any crate-name prefix stripped by the adapter.
type TestRecord struct {
	TestName string
	Scope    string
	Status   string // "passed" | "failed" | "ignored"
}

// Request asks the adapter to run a single targeted test.
type Request struct {
	WorkDir                 string
	FullyQualifiedTestName  string
}

// Result is what the adapter returns after a single invocation.
type Result struct {
	Outcome Outcome
	Records []TestRecord
	Stderr  string
}

// Runner is implemented by per-language adapters.
type Runner interface {
	Run(ctx context.Context, req Request) (Result, error)
}

// StatusFromString validates and normalizes a record status string.
// Returns (status, true) on a known value; ("", false) otherwise.
func StatusFromString(s string) (string, bool) {
	switch s {
	case "passed", "failed", "ignored":
		return s, true
	default:
		return "", false
	}
}

// AdapterFor picks the right Rust runner adapter based on speccraft.toml
// config. Default is cargo; explicit "nextest" opts in. Unknown values
// (the config validator should have rejected them at parse) fall back to cargo.
func AdapterFor(cfg speccraft.SpeccraftConfig) Runner {
	switch cfg.TDD.Rust.Runner {
	case "nextest":
		return &NextestAdapter{}
	default:
		return &CargoAdapter{}
	}
}

// AdapterForLanguage selects the red-check adapter for a non-Rust language
// (spec 0018). lang is one of "go", "python", "js", "ts". The returned bool is
// false when no runner can be resolved — for JS/TS that means an empty
// configured command — and the guard must fail closed in that case (Decision
// D2), never fall back to the touch-check. JavaScript and TypeScript share the
// single JSTSAdapter; only the configured command differs.
func AdapterForLanguage(lang string, cfg speccraft.SpeccraftConfig) (Runner, bool) {
	switch lang {
	case "go":
		return &GoAdapter{Command: cfg.TDD.Go.Command}, true
	case "python":
		return &PytestAdapter{Command: cfg.TDD.Python.Command}, true
	case "js":
		if cfg.TDD.JavaScript.Command == "" {
			return nil, false
		}
		return &JSTSAdapter{Command: cfg.TDD.JavaScript.Command}, true
	case "ts":
		if cfg.TDD.TypeScript.Command == "" {
			return nil, false
		}
		return &JSTSAdapter{Command: cfg.TDD.TypeScript.Command}, true
	default:
		return nil, false
	}
}
