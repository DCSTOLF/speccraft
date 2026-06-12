package speccraft_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Test_Docs_RedGreenParity is the spec-0018 AC11 oracle. It pins that project
// memory and the technical-review report reflect red→green parity across all
// four languages and no longer claim the non-Rust guard is a touch-only check
// or that Go/Python runner adoption is a non-goal.
//
// It reads files at the repository root (the parent of the tools module). If
// that root cannot be located (e.g. the module is vendored elsewhere), the test
// skips rather than failing spuriously.
func Test_Docs_RedGreenParity(t *testing.T) {
	root := findDocsRoot(t)

	arch := readFile(t, filepath.Join(root, ".speccraft", "architecture.md"))
	// Both spec-0005 non-goal sites must be scrubbed (claude-p round-2 catch).
	if strings.Contains(arch, "non-goal of spec 0005") {
		t.Error("architecture.md still claims runner adoption is a 'non-goal of spec 0005' (layer-8 site)")
	}
	if strings.Contains(arch, "Runner adoption by Go/Python is a non-goal") {
		t.Error("architecture.md still claims 'Runner adoption by Go/Python is a non-goal' (§Key decisions site)")
	}
	if !strings.Contains(strings.ToLower(arch), "spec 0018") {
		t.Error("architecture.md should record the spec-0018 extension of the runner primitive to Go/Python/JS-TS")
	}

	review := readFile(t, filepath.Join(root, "speccraft-technical-review.md"))
	if !strings.Contains(review, "Resolved by spec 0018") {
		t.Error("speccraft-technical-review.md should mark P0-1 / the §4 matrix as Resolved by spec 0018")
	}

	// index.md and guardrails.md describe the invariant generically; that
	// wording is now accurate for all four languages. Assert it survives
	// (no-regression) and carries no per-language touch-only claim.
	index := readFile(t, filepath.Join(root, ".speccraft", "index.md"))
	if !strings.Contains(index, "red→green invariant") {
		t.Error("index.md should retain the red→green invariant description")
	}
	if strings.Contains(index, "touched this session") {
		t.Error("index.md must not describe the guard as a touch-only check")
	}
	guard := readFile(t, filepath.Join(root, ".speccraft", "guardrails.md"))
	if !strings.Contains(guard, "red→green invariant") {
		t.Error("guardrails.md should retain the red→green invariant description")
	}
}

func findDocsRoot(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	for {
		_, e1 := os.Stat(filepath.Join(dir, ".speccraft"))
		_, e2 := os.Stat(filepath.Join(dir, "speccraft-technical-review.md"))
		if e1 == nil && e2 == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Skip("repo docs root (.speccraft + speccraft-technical-review.md) not found; skipping doc-parity oracle")
		}
		dir = parent
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(data)
}
