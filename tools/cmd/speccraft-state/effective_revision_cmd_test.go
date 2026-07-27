package main

// Spec 0036 T11 (AC2) — `speccraft-state effective-revision <specDir>` over the
// run() seam. RED = "unknown subcommand" until wired.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func Test_StateCmd_EffectiveRevision_PrintsEffectiveAloneExitZero(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nrevision: 3\n---\n# S\n")
	if err := os.WriteFile(filepath.Join(specDir, "review-r5.md"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, stdout, stderr := runCmd(t, repo, "effective-revision", specDir)
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	if strings.TrimSpace(stdout) != "6" {
		t.Errorf("stdout=%q, want 6 (healed max(3,5+1))", stdout)
	}
}

func Test_StateCmd_EffectiveRevision_UnreadableSpec_NonZero(t *testing.T) {
	repo := makeRepo(t)
	code, _, _ := runCmd(t, repo, "effective-revision", filepath.Join(repo, "specs", "nope"))
	if code == 0 {
		t.Error("expected non-zero for a missing spec dir")
	}
}

func Test_StateCmd_Usage_ListsRevisionSubcommands(t *testing.T) {
	repo := makeRepo(t)
	_, _, stderr := runCmd(t, repo)
	for _, sub := range []string{"effective-revision", "set-status", "set-revision", "reconcile-revision"} {
		if !strings.Contains(stderr, sub) {
			t.Errorf("usage does not list %q", sub)
		}
	}
}
