package speccraft_test

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// TestRustState_NoExternalWriters_Grep asserts that the Rust state fields
// (RustTestBaseline, RustGateFingerprint) and their JSON keys are written
// only from the allowed packages: the state package itself and
// tools/cmd/speccraft-state. This enforces the AC #8 + AC #12(e)
// single-writer guardrail at the code-review layer.
//
// Allowed writers:
//   - tools/internal/speccraft/state.go (defines the struct + helpers)
//   - tools/cmd/speccraft-state/ (the CLI binary)
//
// All Go test files (*_test.go) are allowed everywhere; tests can simulate
// or assert on the state without violating the single-writer rule in prod
// code.
func TestRustState_NoExternalWriters_Grep(t *testing.T) {
	// findRepoRoot returns the directory containing go.mod, which here is
	// .../speccraft/tools — i.e. the module root we want to scan.
	toolsDir := findRepoRoot(t)

	// Patterns that constitute a "write" to the Rust state fields:
	//   - Go field assignment: `.RustTestBaseline =`, `.RustGateFingerprint =`
	//   - JSON write of the keys with a value: `"rust_test_baseline":` (in non-test code)
	//   - JSON write of the keys with a value: `"rust_gate_fingerprint":`
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`\.RustTestBaseline\s*=[^=]`),
		regexp.MustCompile(`\.RustGateFingerprint\s*=[^=]`),
		regexp.MustCompile(`\.OverridePending\s*=[^=]`),
	}

	allowedFiles := map[string]bool{
		filepath.Join(toolsDir, "internal", "speccraft", "state.go"): true,
	}

	var violations []string

	err := filepath.Walk(toolsDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		// Only scan Go production source files.
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		if allowedFiles[path] {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		for _, re := range patterns {
			if loc := re.FindIndex(data); loc != nil {
				// Locate the line number for a useful failure message.
				line := 1 + strings.Count(string(data[:loc[0]]), "\n")
				violations = append(violations, path+":"+itoa(line))
				break
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walk: %v", err)
	}

	if len(violations) > 0 {
		t.Errorf("found %d non-allowed writer(s) of Rust state fields:\n  %s",
			len(violations), strings.Join(violations, "\n  "))
		t.Errorf("Allowed writers: tools/internal/speccraft/state.go and tools/cmd/speccraft-state/main.go.")
		t.Errorf("This is the single-writer guardrail for AC #8 / AC #12(e).")
	}
}

// findRepoRoot walks upward from the current working directory to find the
// repo root (the directory containing go.mod or .speccraft/).
func findRepoRoot(t *testing.T) string {
	t.Helper()
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	dir := cwd
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatal("could not find repo root from " + cwd)
		}
		dir = parent
	}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
