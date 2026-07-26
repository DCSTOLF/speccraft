package main

// Spec 0035 T12 (AC3/AC4/AC6) — `speccraft-state review-diff <dir> [--promote]`.
// Drives the compile-stable run() seam; a LOCAL envelope struct is unmarshalled
// from stdout (detect_cmd_test.go technique). RED = "unknown subcommand" until
// the case is wired.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type reviewEnvelope struct {
	Schema          int     `json:"schema"`
	Snapshot        bool    `json:"snapshot"`
	Changed         bool    `json:"changed"`
	Diff            string  `json:"diff"`
	Fingerprint     string  `json:"fingerprint"`
	BaseFingerprint *string `json:"base_fingerprint"`
}

func Test_StateCmd_ReviewDiff_Usage_ListsReviewDiff(t *testing.T) {
	repo := makeRepo(t)
	_, _, stderr := runCmd(t, repo)
	if !strings.Contains(stderr, "review-diff") {
		t.Errorf("usage does not list review-diff:\n%s", stderr)
	}
}

func Test_StateCmd_ReviewDiff_EmitsSchema1Envelope(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "# Spec\n\n## Why\n\nx\n")
	// establish a snapshot
	if code, _, se := runCmd(t, repo, "review-snapshot", "write", specDir); code != 0 {
		t.Fatalf("seed snapshot exit=%d stderr=%s", code, se)
	}
	code, stdout, stderr := runCmd(t, repo, "review-diff", specDir)
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	var env reviewEnvelope
	if err := json.Unmarshal([]byte(strings.TrimSpace(stdout)), &env); err != nil {
		t.Fatalf("unmarshal envelope %q: %v", stdout, err)
	}
	if env.Schema != 1 {
		t.Errorf("schema = %d, want 1", env.Schema)
	}
	if !env.Snapshot || env.Changed {
		t.Errorf("snapshot=%v changed=%v, want true/false", env.Snapshot, env.Changed)
	}
}

func Test_StateCmd_ReviewDiff_ReadOnly_NoSnapshot_Exit0(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0002-y", "# Spec\n\n## Why\n\ny\n")
	code, stdout, stderr := runCmd(t, repo, "review-diff", specDir)
	if code != 0 {
		t.Fatalf("exit = %d, want 0 for no-snapshot; stderr=%s", code, stderr)
	}
	var env reviewEnvelope
	if err := json.Unmarshal([]byte(strings.TrimSpace(stdout)), &env); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if env.Snapshot {
		t.Errorf("snapshot = true, want false")
	}
	if env.BaseFingerprint != nil {
		t.Errorf("base_fingerprint = %v, want null", *env.BaseFingerprint)
	}
}

func Test_StateCmd_ReviewDiff_ReadOnly_ClosedSpec_Exit0(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0003-closed", "---\nstatus: closed\n---\n\n# Spec\n\n## Why\n\nz\n")
	if code, _, se := runCmd(t, repo, "review-snapshot", "write", specDir); code != 0 {
		t.Fatalf("seed snapshot exit=%d stderr=%s", code, se)
	}
	code, _, stderr := runCmd(t, repo, "review-diff", specDir)
	if code != 0 {
		t.Fatalf("read-only review-diff on closed spec exit = %d, want 0; stderr=%s", code, stderr)
	}
}

func Test_StateCmd_ReviewDiff_UnreadableSpec_ExitsNonZero(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0004-nospec", "") // no spec.md
	code, _, _ := runCmd(t, repo, "review-diff", specDir)
	if code == 0 {
		t.Errorf("exit = 0, want non-zero for unreadable spec.md")
	}
}

func Test_StateCmd_ReviewDiff_UnreadableSnapshot_ExitsNonZero(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0005-badsnap", "# Spec\n\n## Why\n\nq\n")
	// review-snapshot.md present but unreadable: a directory in its place (uid-independent).
	if err := os.MkdirAll(filepath.Join(specDir, "review-snapshot.md"), 0o755); err != nil {
		t.Fatal(err)
	}
	code, _, _ := runCmd(t, repo, "review-diff", specDir)
	if code == 0 {
		t.Errorf("exit = 0, want non-zero for unreadable (present) snapshot")
	}
}

func Test_StateCmd_ReviewDiff_PromoteClosedSpec_Refused_WritesNothing(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0006-closed", "---\nstatus: closed\n---\n\nOLD\n")
	if code, _, se := runCmd(t, repo, "review-snapshot", "write", specDir); code != 0 {
		t.Fatalf("seed snapshot exit=%d stderr=%s", code, se)
	}
	if err := os.WriteFile(filepath.Join(specDir, "spec.md"), []byte("---\nstatus: closed\n---\n\nNEW\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	snapBefore, _ := os.ReadFile(filepath.Join(specDir, "review-snapshot.md"))
	code, _, _ := runCmd(t, repo, "review-diff", specDir, "--promote")
	if code == 0 {
		t.Errorf("exit = 0, want non-zero: --promote must be refused on a closed spec")
	}
	snapAfter, _ := os.ReadFile(filepath.Join(specDir, "review-snapshot.md"))
	if string(snapBefore) != string(snapAfter) {
		t.Errorf("refused --promote still wrote the snapshot: %q -> %q", snapBefore, snapAfter)
	}
}
