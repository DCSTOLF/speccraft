package speccraft_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func writeConfig(t *testing.T, root, content string) {
	t.Helper()
	dir := filepath.Join(root, ".speccraft")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "speccraft.toml"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestReadConfig_Missing(t *testing.T) {
	cfg := speccraft.ReadConfig(t.TempDir())
	if len(cfg.TDD.TestRoots) != 0 {
		t.Errorf("expected empty TestRoots, got %v", cfg.TDD.TestRoots)
	}
}

func TestReadConfig_SingleRoot(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd]\ntest_roots = [\"tests\"]\n")
	cfg := speccraft.ReadConfig(root)
	if len(cfg.TDD.TestRoots) != 1 || cfg.TDD.TestRoots[0] != "tests" {
		t.Errorf("TestRoots = %v, want [tests]", cfg.TDD.TestRoots)
	}
}

func TestReadConfig_MultipleRoots(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd]\ntest_roots = [\"tests\", \"test\"]\n")
	cfg := speccraft.ReadConfig(root)
	want := []string{"tests", "test"}
	if len(cfg.TDD.TestRoots) != len(want) {
		t.Fatalf("TestRoots = %v, want %v", cfg.TDD.TestRoots, want)
	}
	for i, v := range want {
		if cfg.TDD.TestRoots[i] != v {
			t.Errorf("TestRoots[%d] = %q, want %q", i, cfg.TDD.TestRoots[i], v)
		}
	}
}

func TestReadConfig_CommentsAndBlanks(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "# speccraft config\n\n[tdd]\n# roots\ntest_roots = [\"tests\"]\n")
	cfg := speccraft.ReadConfig(root)
	if len(cfg.TDD.TestRoots) != 1 || cfg.TDD.TestRoots[0] != "tests" {
		t.Errorf("TestRoots = %v, want [tests]", cfg.TDD.TestRoots)
	}
}

func TestReadConfig_WrongSection(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[other]\ntest_roots = [\"tests\"]\n")
	cfg := speccraft.ReadConfig(root)
	if len(cfg.TDD.TestRoots) != 0 {
		t.Errorf("expected empty TestRoots outside [tdd], got %v", cfg.TDD.TestRoots)
	}
}

func TestReadConfig_RustRunner_DefaultsToCargo(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd]\ntest_roots = [\"tests\"]\n")
	cfg := speccraft.ReadConfig(root)
	if cfg.TDD.Rust.Runner != "cargo" {
		t.Errorf("Rust.Runner = %q, want %q (default when [tdd.rust] absent)", cfg.TDD.Rust.Runner, "cargo")
	}
}

func TestReadConfig_RustRunner_ExplicitCargo(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd.rust]\nrunner = \"cargo\"\n")
	cfg := speccraft.ReadConfig(root)
	if cfg.TDD.Rust.Runner != "cargo" {
		t.Errorf("Rust.Runner = %q, want %q", cfg.TDD.Rust.Runner, "cargo")
	}
}

func TestReadConfig_RustRunner_ExplicitNextest(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd.rust]\nrunner = \"nextest\"\n")
	cfg := speccraft.ReadConfig(root)
	if cfg.TDD.Rust.Runner != "nextest" {
		t.Errorf("Rust.Runner = %q, want %q", cfg.TDD.Rust.Runner, "nextest")
	}
}

func TestReadConfigStrict_RustRunner_UnknownValueRejected(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd.rust]\nrunner = \"auto\"\n")
	_, err := speccraft.ReadConfigStrict(root)
	if err == nil {
		t.Fatal("ReadConfigStrict: expected error for runner = \"auto\", got nil")
	}
	msg := err.Error()
	for _, want := range []string{"speccraft.toml", "runner", "auto"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error message missing %q: %s", want, msg)
		}
	}
}

func TestReadConfigStrict_RustRunner_AllowedValuesListed(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd.rust]\nrunner = \"foo\"\n")
	_, err := speccraft.ReadConfigStrict(root)
	if err == nil {
		t.Fatal("ReadConfigStrict: expected error for runner = \"foo\", got nil")
	}
	msg := err.Error()
	for _, want := range []string{"cargo", "nextest"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error message missing allowed value %q: %s", want, msg)
		}
	}
}

func TestReadConfigStrict_RustRunner_Cargo_NoError(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd.rust]\nrunner = \"cargo\"\n")
	cfg, err := speccraft.ReadConfigStrict(root)
	if err != nil {
		t.Fatalf("ReadConfigStrict: unexpected error: %v", err)
	}
	if cfg.TDD.Rust.Runner != "cargo" {
		t.Errorf("Rust.Runner = %q, want %q", cfg.TDD.Rust.Runner, "cargo")
	}
}

func TestReadConfigStrict_RustRunner_Nextest_NoError(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd.rust]\nrunner = \"nextest\"\n")
	cfg, err := speccraft.ReadConfigStrict(root)
	if err != nil {
		t.Fatalf("ReadConfigStrict: unexpected error: %v", err)
	}
	if cfg.TDD.Rust.Runner != "nextest" {
		t.Errorf("Rust.Runner = %q, want %q", cfg.TDD.Rust.Runner, "nextest")
	}
}

func TestReadConfigStrict_RustRunner_Default_NoError(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd]\ntest_roots = [\"tests\"]\n")
	cfg, err := speccraft.ReadConfigStrict(root)
	if err != nil {
		t.Fatalf("ReadConfigStrict: unexpected error: %v", err)
	}
	if cfg.TDD.Rust.Runner != "cargo" {
		t.Errorf("Rust.Runner = %q, want %q (default)", cfg.TDD.Rust.Runner, "cargo")
	}
}

// --- Spec 0018 T8: per-language runner config (Go/Python/JS/TS) ---

func Test_ParseConfig_GoPythonJSTSCommands(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, `[tdd.go]
command = "go test -count=1"

[tdd.python]
command = "pytest -q"

[tdd.javascript]
command = "vitest run"

[tdd.typescript]
command = "vitest run --ts"
`)
	cfg := speccraft.ReadConfig(root)
	if cfg.TDD.Go.Command != "go test -count=1" {
		t.Errorf("Go.Command = %q", cfg.TDD.Go.Command)
	}
	if cfg.TDD.Python.Command != "pytest -q" {
		t.Errorf("Python.Command = %q", cfg.TDD.Python.Command)
	}
	if cfg.TDD.JavaScript.Command != "vitest run" {
		t.Errorf("JavaScript.Command = %q", cfg.TDD.JavaScript.Command)
	}
	if cfg.TDD.TypeScript.Command != "vitest run --ts" {
		t.Errorf("TypeScript.Command = %q", cfg.TDD.TypeScript.Command)
	}
}

func Test_ApplyDefaults_GoPythonCommands(t *testing.T) {
	cfg := speccraft.ReadConfig(t.TempDir()) // no config file → defaults
	if cfg.TDD.Go.Command != "go test" {
		t.Errorf("default Go.Command = %q, want %q", cfg.TDD.Go.Command, "go test")
	}
	if cfg.TDD.Python.Command != "pytest" {
		t.Errorf("default Python.Command = %q, want %q", cfg.TDD.Python.Command, "pytest")
	}
	if cfg.TDD.JavaScript.Command != "" {
		t.Errorf("default JavaScript.Command = %q, want empty (no safe default)", cfg.TDD.JavaScript.Command)
	}
	if cfg.TDD.TypeScript.Command != "" {
		t.Errorf("default TypeScript.Command = %q, want empty (no safe default)", cfg.TDD.TypeScript.Command)
	}
}

func Test_ReadConfigStrict_EmptyJSCommandIsNotError(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd.javascript]\ncommand = \"\"\n")
	if _, err := speccraft.ReadConfigStrict(root); err != nil {
		t.Errorf("empty JS command must be valid at parse (fail-closed is a runtime concern), got: %v", err)
	}
}
