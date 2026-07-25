package speccraft_test

// Spec 0034 — stack detection core (AC1, AC2).
//
// DetectStack inspects ONLY the exact repo-root manifest paths (never a walk /
// workspace discovery) and returns a typed Stack: the primary language, the
// config-backed effective test command (a *suite* command — e.g. "go test ./..."),
// an ordered list of test-file globs, and an InlineTests flag (rust #[test]
// modules aren't a filesystem glob). Polyglot repos resolve by the fixed public
// order go > rust > python > ts > js; no manifest → an explicit "unknown".

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// newManifestRoot writes each named (empty) manifest file into a fresh temp dir
// and returns the dir. Manifest presence at the root is all DetectStack probes.
func newManifestRoot(t *testing.T, files ...string) string {
	t.Helper()
	root := t.TempDir()
	for _, f := range files {
		if err := os.WriteFile(filepath.Join(root, f), []byte(""), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

// cfgRust builds a config with an explicit rust runner (mirrors applyDefaults'
// go/python defaults, which the zero value + ReadConfig would otherwise supply).
func cfgDefault() speccraft.SpeccraftConfig {
	var cfg speccraft.SpeccraftConfig
	cfg.TDD.Go.Command = "go test"
	cfg.TDD.Python.Command = "pytest"
	cfg.TDD.Rust.Runner = "cargo"
	return cfg
}

func cfgRust(runner string) speccraft.SpeccraftConfig {
	cfg := cfgDefault()
	cfg.TDD.Rust.Runner = runner
	return cfg
}

func assertStack(t *testing.T, got speccraft.Stack, wantLang, wantCmd string, wantPatterns []string, wantInline bool) {
	t.Helper()
	if got.Language != wantLang {
		t.Errorf("Language = %q, want %q", got.Language, wantLang)
	}
	if got.TestCommand != wantCmd {
		t.Errorf("TestCommand = %q, want %q", got.TestCommand, wantCmd)
	}
	if !reflect.DeepEqual(got.TestPatterns, wantPatterns) {
		t.Errorf("TestPatterns = %#v, want %#v", got.TestPatterns, wantPatterns)
	}
	if got.InlineTests != wantInline {
		t.Errorf("InlineTests = %v, want %v", got.InlineTests, wantInline)
	}
}

func Test_DetectStack_GoMod_ReturnsGo(t *testing.T) {
	root := newManifestRoot(t, "go.mod")
	assertStack(t, speccraft.DetectStack(root, cfgDefault()),
		"go", "go test ./...", []string{"*_test.go"}, false)
}

func Test_DetectStack_GoMod_CustomCommand_AppendsPackageSelector(t *testing.T) {
	// The surfaced go command is a SUITE command: DetectStack appends the ` ./...`
	// package selector to whatever cfg.TDD.Go.Command is configured, distinct from
	// the guard's bare per-test cfg.TDD.Go.Command.
	cfg := cfgDefault()
	cfg.TDD.Go.Command = "gotestsum --"
	root := newManifestRoot(t, "go.mod")
	assertStack(t, speccraft.DetectStack(root, cfg),
		"go", "gotestsum -- ./...", []string{"*_test.go"}, false)
}

func Test_DetectStack_CargoToml_Cargo_ReturnsRustInlineTrue(t *testing.T) {
	root := newManifestRoot(t, "Cargo.toml")
	assertStack(t, speccraft.DetectStack(root, cfgRust("cargo")),
		"rust", "cargo test", []string{"tests/*.rs"}, true)
}

func Test_DetectStack_CargoToml_Nextest_ReturnsCargoNextestRun(t *testing.T) {
	root := newManifestRoot(t, "Cargo.toml")
	assertStack(t, speccraft.DetectStack(root, cfgRust("nextest")),
		"rust", "cargo nextest run", []string{"tests/*.rs"}, true)
}

func Test_DetectStack_Pyproject_ReturnsPython(t *testing.T) {
	root := newManifestRoot(t, "pyproject.toml")
	assertStack(t, speccraft.DetectStack(root, cfgDefault()),
		"python", "pytest", []string{"test_*.py", "*_test.py"}, false)
}

func Test_DetectStack_SetupPy_ReturnsPython(t *testing.T) {
	root := newManifestRoot(t, "setup.py")
	assertStack(t, speccraft.DetectStack(root, cfgDefault()),
		"python", "pytest", []string{"test_*.py", "*_test.py"}, false)
}

func Test_DetectStack_SetupCfg_ReturnsPython(t *testing.T) {
	root := newManifestRoot(t, "setup.cfg")
	assertStack(t, speccraft.DetectStack(root, cfgDefault()),
		"python", "pytest", []string{"test_*.py", "*_test.py"}, false)
}

func Test_DetectStack_Requirements_ReturnsPython(t *testing.T) {
	root := newManifestRoot(t, "requirements.txt")
	assertStack(t, speccraft.DetectStack(root, cfgDefault()),
		"python", "pytest", []string{"test_*.py", "*_test.py"}, false)
}

func Test_DetectStack_PackageJSON_ReturnsJS(t *testing.T) {
	cfg := cfgDefault()
	cfg.TDD.JavaScript.Command = "npm test"
	root := newManifestRoot(t, "package.json")
	assertStack(t, speccraft.DetectStack(root, cfg),
		"js", "npm test", []string{"*.test.js", "*.spec.js"}, false)
}

func Test_DetectStack_PackageJSONWithTsconfig_ReturnsTS(t *testing.T) {
	cfg := cfgDefault()
	cfg.TDD.TypeScript.Command = "npm test"
	root := newManifestRoot(t, "package.json", "tsconfig.json")
	assertStack(t, speccraft.DetectStack(root, cfg),
		"ts", "npm test", []string{"*.test.ts", "*.spec.ts"}, false)
}

func Test_DetectStack_NoManifest_ReturnsUnknown(t *testing.T) {
	root := newManifestRoot(t) // empty
	got := speccraft.DetectStack(root, cfgDefault())
	// Direct assertion (AC2): not "by absence".
	assertStack(t, got, "unknown", "", []string{}, false)
}

// Polyglot precedence: each pins ONE adjacent boundary of go > rust > python >
// ts > js so the documented order cannot silently reorder (AC2).

func Test_DetectStack_Polyglot_GoBeatsRust(t *testing.T) {
	root := newManifestRoot(t, "go.mod", "Cargo.toml")
	if got := speccraft.DetectStack(root, cfgDefault()).Language; got != "go" {
		t.Errorf("go.mod+Cargo.toml → %q, want go", got)
	}
}

func Test_DetectStack_Polyglot_RustBeatsPython(t *testing.T) {
	root := newManifestRoot(t, "Cargo.toml", "pyproject.toml")
	if got := speccraft.DetectStack(root, cfgDefault()).Language; got != "rust" {
		t.Errorf("Cargo.toml+pyproject.toml → %q, want rust", got)
	}
}

func Test_DetectStack_Polyglot_PythonBeatsTS(t *testing.T) {
	cfg := cfgDefault()
	cfg.TDD.TypeScript.Command = "npm test"
	root := newManifestRoot(t, "pyproject.toml", "package.json", "tsconfig.json")
	if got := speccraft.DetectStack(root, cfg).Language; got != "python" {
		t.Errorf("pyproject+package.json+tsconfig → %q, want python", got)
	}
}

func Test_DetectStack_Polyglot_TSBeatsJS(t *testing.T) {
	cfg := cfgDefault()
	cfg.TDD.TypeScript.Command = "npm test"
	root := newManifestRoot(t, "package.json", "tsconfig.json")
	if got := speccraft.DetectStack(root, cfg).Language; got != "ts" {
		t.Errorf("package.json+tsconfig → %q, want ts", got)
	}
}
