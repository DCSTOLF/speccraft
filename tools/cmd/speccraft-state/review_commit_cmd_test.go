package main

// Spec 0035 (AC2) — `speccraft-state review-commit <review-file> <fingerprint>`
// atomically rewrites review.md carrying exactly one reviewed_sha256 line, so the
// command layer can record the reviewed fingerprint after the review workflow
// completes. Drives the run() seam; RED = "unknown subcommand" until wired.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func Test_StateCmd_ReviewCommit_RecordsFingerprintAtomically(t *testing.T) {
	// AC2: after commit, review.md carries the fingerprint and preserves the body.
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "# Spec\n")
	reviewPath := filepath.Join(specDir, "review.md")
	if err := os.WriteFile(reviewPath, []byte("# Review\n\nverdict: approve\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	fp := strings.Repeat("a", 64)
	code, _, stderr := runCmd(t, repo, "review-commit", reviewPath, fp)
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	got, _ := os.ReadFile(reviewPath)
	if !strings.Contains(string(got), "reviewed_sha256: "+fp) {
		t.Errorf("review.md missing fingerprint line:\n%s", got)
	}
	if !strings.Contains(string(got), "verdict: approve") {
		t.Errorf("review body not preserved:\n%s", got)
	}
}

func Test_StateCmd_ReviewCommit_ExitZeroOnSuccess(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0009-z", "# Spec\n")
	reviewPath := filepath.Join(specDir, "review.md")
	if err := os.WriteFile(reviewPath, []byte("# Review\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, _, _ := runCmd(t, repo, "review-commit", reviewPath, strings.Repeat("b", 64))
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
}

func Test_StateCmd_ReviewCommit_MissingArgs_ExitsNonZero(t *testing.T) {
	repo := makeRepo(t)
	code, _, _ := runCmd(t, repo, "review-commit")
	if code == 0 {
		t.Errorf("exit = 0, want non-zero when args missing")
	}
}
