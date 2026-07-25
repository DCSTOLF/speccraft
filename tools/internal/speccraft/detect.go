package speccraft

// Spec 0034 — stack detection core.
//
// DetectStack surfaces the host repo's primary language + effective *suite* test
// command + test-file globs for the authoring layer (planner prose, /speccraft:init
// seeding, the `speccraft-state detect-stack`/`test-command` subcommands). The
// EXECUTION substrate is already stack-aware (runner.AdapterForLanguage /
// runner.AdapterFor); this only reads the same config-backed commands and reports
// them. It probes ONLY exact repo-root manifest paths — never a walk or workspace
// discovery.

import (
	"os"
	"path/filepath"
	"strings"
)

// Stack is the typed detection result. TestCommand is a suite command (e.g.
// "go test ./...", distinct from the guard's bare per-test cfg.TDD.Go.Command).
// TestPatterns is an ordered list of filename globs and NEVER carries non-glob
// prose; rust inline #[test] modules are signalled by InlineTests, not a glob.
type Stack struct {
	Language     string
	TestCommand  string
	TestPatterns []string
	InlineTests  bool
}

// langProbe pairs a language id with the repo-root manifests that identify it
// (presence of ANY manifest in the list matches).
type langProbe struct {
	lang      string
	manifests []string
}

// manifestOrder is the SINGLE source of the polyglot precedence
// go > rust > python > ts > js. First matching probe wins, so the primary
// language is deterministic and not filesystem-iteration-order dependent.
// A compiled-language manifest (go.mod, Cargo.toml) is almost never present as
// mere tooling, whereas package.json frequently is, so JS/TS ranks last; the
// ts-vs-js refinement is decided within the package.json case by tsconfig.json.
var manifestOrder = []langProbe{
	{"go", []string{"go.mod"}},
	{"rust", []string{"Cargo.toml"}},
	{"python", []string{"pyproject.toml", "setup.py", "setup.cfg", "requirements.txt"}},
	{"js", []string{"package.json"}}, // → "ts" when tsconfig.json is also present
}

// hasManifest reports whether name exists at the repo root (exact path only).
func hasManifest(root, name string) bool {
	_, err := os.Stat(filepath.Join(root, name))
	return err == nil
}

// DetectStack inspects the exact repo-root manifests and returns the primary
// Stack. No recognized manifest → an explicit "unknown" with an empty command.
func DetectStack(root string, cfg SpeccraftConfig) Stack {
	for _, p := range manifestOrder {
		for _, m := range p.manifests {
			if hasManifest(root, m) {
				return stackFor(p.lang, root, cfg)
			}
		}
	}
	return Stack{Language: "unknown", TestPatterns: []string{}}
}

// stackFor builds the Stack for a matched language, composing the effective
// suite test command from the config-backed per-language command.
func stackFor(lang, root string, cfg SpeccraftConfig) Stack {
	switch lang {
	case "go":
		// Suite form: append the ./... package selector to the configured command
		// (the guard uses the bare command for per-test targeting).
		return Stack{
			Language:     "go",
			TestCommand:  strings.TrimSpace(cfg.TDD.Go.Command) + " ./...",
			TestPatterns: []string{"*_test.go"},
		}
	case "rust":
		cmd := "cargo test"
		if cfg.TDD.Rust.Runner == "nextest" {
			cmd = "cargo nextest run"
		}
		return Stack{
			Language:     "rust",
			TestCommand:  cmd,
			TestPatterns: []string{"tests/*.rs"},
			InlineTests:  true, // #[test] modules aren't a filesystem glob
		}
	case "python":
		return Stack{
			Language:     "python",
			TestCommand:  cfg.TDD.Python.Command,
			TestPatterns: []string{"test_*.py", "*_test.py"},
		}
	case "js":
		if hasManifest(root, "tsconfig.json") {
			return Stack{
				Language:     "ts",
				TestCommand:  cfg.TDD.TypeScript.Command,
				TestPatterns: []string{"*.test.ts", "*.spec.ts"},
			}
		}
		return Stack{
			Language:     "js",
			TestCommand:  cfg.TDD.JavaScript.Command,
			TestPatterns: []string{"*.test.js", "*.spec.js"},
		}
	}
	return Stack{Language: "unknown", TestPatterns: []string{}}
}
