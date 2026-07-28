package speccraft_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Test_HotPath_UsesOnlyFindRoot_Grep enforces spec 0037 AC5: nothing on the
// Edit/Write hot path — the PreToolUse hooks and speccraft-guard — may reference
// the new FindWorkspaceRoot resolver (or its `find-workspace-root` subcommand
// spelling). That resolver is consumed only by the arch:* commands and the
// conductor; the guard and hooks keep resolving via FindRoot alone, so the
// "no change to the hot path" invariant holds by construction. Sibling to
// state_single_writer_test.go (the spec-0012 single-writer grep test).
func Test_HotPath_UsesOnlyFindRoot_Grep(t *testing.T) {
	toolsDir := findRepoRoot(t)
	repoRoot := filepath.Dir(toolsDir)

	var hotPath []string
	hooks, _ := filepath.Glob(filepath.Join(repoRoot, "hooks", "*.sh"))
	hotPath = append(hotPath, hooks...)
	guardGo, _ := filepath.Glob(filepath.Join(toolsDir, "cmd", "speccraft-guard", "*.go"))
	for _, f := range guardGo {
		if !strings.HasSuffix(f, "_test.go") {
			hotPath = append(hotPath, f)
		}
	}
	if len(hotPath) == 0 {
		t.Fatal("no hot-path files found to scan")
	}

	forbidden := []string{"FindWorkspaceRoot", "find-workspace-root"}
	sawFindRoot := false
	for _, f := range hotPath {
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		src := string(b)
		for _, tok := range forbidden {
			if strings.Contains(src, tok) {
				t.Errorf("%s references %q — the workspace resolver must never be on the Edit/Write hot path (spec 0037 AC5)", f, tok)
			}
		}
		if strings.Contains(src, "FindRoot") || strings.Contains(src, "find-root") {
			sawFindRoot = true
		}
	}
	if !sawFindRoot {
		t.Error("expected the hot path to reference FindRoot; otherwise this guard is vacuous")
	}
}
