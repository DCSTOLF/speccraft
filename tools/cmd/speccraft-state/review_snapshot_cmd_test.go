package main

// Spec 0035 T6 (AC1) — `speccraft-state review-snapshot write <spec-dir>`.
// Drives the compile-stable run() seam (detect_cmd_test.go technique): compiles
// today, fails at RUNTIME with "unknown subcommand" until the case is wired.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func mkSpecDir(t *testing.T, repo, name, content string) string {
	t.Helper()
	dir := filepath.Join(repo, "specs", name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if content != "" {
		if err := os.WriteFile(filepath.Join(dir, "spec.md"), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func Test_StateCmd_ReviewSnapshotWrite_WritesAndPrintsFingerprint(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "# Spec\n\n## Why\n\nx\n")
	code, stdout, stderr := runCmd(t, repo, "review-snapshot", "write", specDir)
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	fp := strings.TrimSpace(stdout)
	if len(fp) != 64 {
		t.Errorf("fingerprint = %q, want 64 hex chars", fp)
	}
	if _, err := os.Stat(filepath.Join(specDir, "review-snapshot.md")); err != nil {
		t.Errorf("snapshot not written: %v", err)
	}
}

func Test_StateCmd_ReviewSnapshotWrite_MissingSpec_ExitsNonZero(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "empty", "")
	code, _, _ := runCmd(t, repo, "review-snapshot", "write", specDir)
	if code == 0 {
		t.Errorf("exit = 0, want non-zero for missing spec.md")
	}
}

func Test_StateCmd_Usage_ListsReviewSnapshotWrite(t *testing.T) {
	repo := makeRepo(t)
	_, _, stderr := runCmd(t, repo) // no args → usage to stderr
	if !strings.Contains(stderr, "review-snapshot write") {
		t.Errorf("usage does not list `review-snapshot write`:\n%s", stderr)
	}
}

func Test_StateCmd_ReviewSnapshotWrite_FingerprintIsHex(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0002-y", "hello\n")
	code, stdout, stderr := runCmd(t, repo, "review-snapshot", "write", specDir)
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	fp := strings.TrimSpace(stdout)
	for _, c := range fp {
		if !strings.ContainsRune("0123456789abcdef", c) {
			t.Fatalf("fingerprint %q has non-hex char %q", fp, c)
		}
	}
}
