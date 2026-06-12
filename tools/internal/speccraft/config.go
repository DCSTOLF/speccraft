package speccraft

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ErrInvalidConfig is returned by ReadConfigStrict when speccraft.toml contains
// a value that fails validation. Wrap-friendly sentinel.
var ErrInvalidConfig = errors.New("invalid speccraft.toml")

// SpeccraftConfig holds settings from .speccraft/speccraft.toml.
type SpeccraftConfig struct {
	TDD TDDConfig
}

type TDDConfig struct {
	// TestRoots are directories (relative to repo root) searched for Python test
	// files when no same-directory sibling is found.
	TestRoots []string

	// Rust holds Rust-specific TDD settings parsed from `[tdd.rust]`.
	Rust RustConfig

	// Go/Python/JavaScript/TypeScript hold the per-language red-check test
	// command parsed from `[tdd.<lang>]` (spec 0018). Go and Python carry
	// defaults; JS/TS have no safe default — an empty command means the runner
	// is unresolved and the guard fails closed (spec 0018, Decision D2).
	Go         GoConfig
	Python     PythonConfig
	JavaScript JSConfig
	TypeScript TSConfig
}

// RustConfig holds settings from `[tdd.rust]` in speccraft.toml.
type RustConfig struct {
	// Runner selects the test runner: "cargo" (default) or "nextest".
	Runner string
}

// GoConfig holds settings from `[tdd.go]`.
type GoConfig struct {
	// Command is the test runner command line; defaults to "go test".
	Command string
}

// PythonConfig holds settings from `[tdd.python]`.
type PythonConfig struct {
	// Command is the test runner command line; defaults to "pytest".
	Command string
}

// JSConfig holds settings from `[tdd.javascript]`.
type JSConfig struct {
	// Command is the test runner command line; no default (must be configured).
	Command string
}

// TSConfig holds settings from `[tdd.typescript]`.
type TSConfig struct {
	// Command is the test runner command line; no default (must be configured).
	Command string
}

// ReadConfig loads .speccraft/speccraft.toml from the repo root.
// Missing file → zero-value config with defaults applied (no error).
// Parse errors are silently skipped.
func ReadConfig(root string) SpeccraftConfig {
	var cfg SpeccraftConfig
	data, err := os.ReadFile(filepath.Join(root, ".speccraft", "speccraft.toml"))
	if err == nil {
		parseSpeccraftTOML(string(data), &cfg)
	}
	applyDefaults(&cfg)
	return cfg
}

func applyDefaults(cfg *SpeccraftConfig) {
	if cfg.TDD.Rust.Runner == "" {
		cfg.TDD.Rust.Runner = "cargo"
	}
	if cfg.TDD.Go.Command == "" {
		cfg.TDD.Go.Command = "go test"
	}
	if cfg.TDD.Python.Command == "" {
		cfg.TDD.Python.Command = "pytest"
	}
	// JS/TS intentionally have no default command: an unconfigured JS/TS
	// runner must fail closed at the guard (spec 0018, Decision D2), not run
	// some guessed binary.
}

// allowedRustRunners enumerates the valid `runner` values for `[tdd.rust]`.
// Order is preserved in error messages.
var allowedRustRunners = []string{"cargo", "nextest"}

// ReadConfigStrict loads .speccraft/speccraft.toml and validates field values.
// Unknown enum values produce an error whose message names the file, the
// offending key, the offending value, and the allowed alternatives.
// Missing file is not an error — defaults apply.
func ReadConfigStrict(root string) (SpeccraftConfig, error) {
	cfg := ReadConfig(root)
	if err := validate(&cfg); err != nil {
		return SpeccraftConfig{}, err
	}
	return cfg, nil
}

func validate(cfg *SpeccraftConfig) error {
	runner := cfg.TDD.Rust.Runner
	if !isAllowed(runner, allowedRustRunners) {
		return fmt.Errorf(
			"speccraft.toml: tdd.rust.runner = %q: allowed values are %q, %q: %w",
			runner, allowedRustRunners[0], allowedRustRunners[1], ErrInvalidConfig,
		)
	}
	return nil
}

func isAllowed(v string, allowed []string) bool {
	for _, a := range allowed {
		if v == a {
			return true
		}
	}
	return false
}

func parseSpeccraftTOML(content string, cfg *SpeccraftConfig) {
	section := ""
	for _, line := range strings.Split(content, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = line
			continue
		}
		switch section {
		case "[tdd]":
			if strings.HasPrefix(line, "test_roots") {
				cfg.TDD.TestRoots = parseTOMLStringArray(line)
			}
		case "[tdd.rust]":
			if strings.HasPrefix(line, "runner") {
				cfg.TDD.Rust.Runner = parseTOMLStringValue(line)
			}
		case "[tdd.go]":
			if strings.HasPrefix(line, "command") {
				cfg.TDD.Go.Command = parseTOMLStringValue(line)
			}
		case "[tdd.python]":
			if strings.HasPrefix(line, "command") {
				cfg.TDD.Python.Command = parseTOMLStringValue(line)
			}
		case "[tdd.javascript]":
			if strings.HasPrefix(line, "command") {
				cfg.TDD.JavaScript.Command = parseTOMLStringValue(line)
			}
		case "[tdd.typescript]":
			if strings.HasPrefix(line, "command") {
				cfg.TDD.TypeScript.Command = parseTOMLStringValue(line)
			}
		}
	}
}

// parseTOMLStringValue parses a single-line TOML string assignment, e.g.:
//
//	runner = "cargo"
func parseTOMLStringValue(line string) string {
	eq := strings.Index(line, "=")
	if eq < 0 {
		return ""
	}
	val := strings.TrimSpace(line[eq+1:])
	return strings.Trim(val, `"'`)
}

// parseTOMLStringArray parses a single-line TOML string array value, e.g.:
//
//	test_roots = ["tests", "test"]
func parseTOMLStringArray(line string) []string {
	open := strings.Index(line, "[")
	close := strings.LastIndex(line, "]")
	if open < 0 || close <= open {
		return nil
	}
	inner := line[open+1 : close]
	var result []string
	for _, part := range strings.Split(inner, ",") {
		val := strings.Trim(strings.TrimSpace(part), `"'`)
		if val != "" {
			result = append(result, val)
		}
	}
	return result
}
