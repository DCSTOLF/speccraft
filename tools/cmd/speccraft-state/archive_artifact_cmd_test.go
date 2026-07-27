package main

// Spec 0036 T17/T19 (AC3, AC4, AC15) — `speccraft-state archive-artifact
// <spec-dir> <kind> <ordinal>`: no-clobber move of a disposable artifact to
// <kind>-r<ordinal>.md, leaving spec.md live. RED = unknown subcommand until wired.

import (
	"os"
	"strings"
	"testing"
)

func Test_StateCmd_ArchiveArtifact_MovesToOrdinal_LeavesSpecMd(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nrevision: 5\n---\n# S\n")
	if err := os.WriteFile(specDir+"/review.md", []byte("R"), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, _, se := runCmd(t, repo, "archive-artifact", specDir, "review", "5"); code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, se)
	}
	if _, err := os.Stat(specDir + "/review.md"); !os.IsNotExist(err) {
		t.Error("review.md should have been moved away")
	}
	if b, err := os.ReadFile(specDir + "/review-r5.md"); err != nil || string(b) != "R" {
		t.Errorf("review-r5.md: err=%v content=%q", err, b)
	}
	if _, err := os.Stat(specDir + "/spec.md"); err != nil {
		t.Error("spec.md must remain live (never archived)")
	}
}

func Test_StateCmd_ArchiveArtifact_SelfHealsPastExisting(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nrevision: 5\n---\n# S\n")
	os.WriteFile(specDir+"/review-r5.md", []byte("old"), 0o644)
	os.WriteFile(specDir+"/review.md", []byte("new"), 0o644)
	_, out, _ := runCmd(t, repo, "effective-revision", specDir) // review-r5 present ⇒ 6
	a := strings.TrimSpace(out)
	if a != "6" {
		t.Fatalf("effective-revision = %q, want 6", a)
	}
	if code, _, se := runCmd(t, repo, "archive-artifact", specDir, "review", a); code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, se)
	}
	if b, _ := os.ReadFile(specDir + "/review-r6.md"); string(b) != "new" {
		t.Errorf("review-r6.md = %q, want new", b)
	}
	if b, _ := os.ReadFile(specDir + "/review-r5.md"); string(b) != "old" {
		t.Error("pre-existing review-r5.md must be untouched")
	}
}

func Test_MoveArtifactNoReplace_LinkOkUnlinkFail_RecoversByInode(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nrevision: 5\n---\n# S\n")
	os.WriteFile(specDir+"/review.md", []byte("R"), 0o644)
	// First move: link succeeds (real os.Link) but unlink fails (injected) — leaves
	// review.md AND review-r5.md as the SAME inode.
	orig := unlinkFile
	unlinkFile = func(string) error { return os.ErrPermission }
	if err := moveArtifactNoReplace(specDir, "review", 5); err == nil {
		t.Fatal("expected error when unlink fails")
	}
	unlinkFile = orig
	// Retry (caller passes the healed ordinal 6). Recovery must detect the
	// same-inode sibling and complete by unlinking the source — NOT create a
	// duplicate at review-r6.md.
	if err := moveArtifactNoReplace(specDir, "review", 6); err != nil {
		t.Fatalf("retry recovery: %v", err)
	}
	if _, err := os.Stat(specDir + "/review.md"); !os.IsNotExist(err) {
		t.Error("source must be unlinked on inode-identity recovery")
	}
	if _, err := os.Stat(specDir + "/review-r6.md"); !os.IsNotExist(err) {
		t.Error("recovery must NOT create a duplicate archive at a fresh ordinal")
	}
	if b, _ := os.ReadFile(specDir + "/review-r5.md"); string(b) != "R" {
		t.Error("the already-linked review-r5.md must be the single archived copy")
	}
}

func Test_MoveArtifactNoReplace_FailsSafeNoInodeIdentity_KeepsSource(t *testing.T) {
	// A pre-existing DIFFERENT-inode target ⇒ link EEXIST, no same-inode sibling,
	// so the source must be preserved (never deleted on byte coincidence).
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nrevision: 5\n---\n# S\n")
	os.WriteFile(specDir+"/review-r5.md", []byte("unrelated"), 0o644)
	os.WriteFile(specDir+"/review.md", []byte("R"), 0o644)
	if err := moveArtifactNoReplace(specDir, "review", 5); err == nil {
		t.Error("expected error linking onto an existing different-inode target")
	}
	if b, _ := os.ReadFile(specDir + "/review.md"); string(b) != "R" {
		t.Error("source must be preserved when there is no same-inode sibling")
	}
}

func Test_StateCmd_Usage_ListsArchiveArtifact(t *testing.T) {
	repo := makeRepo(t)
	_, _, stderr := runCmd(t, repo)
	if !strings.Contains(stderr, "archive-artifact") {
		t.Error("usage does not list archive-artifact")
	}
}

func Test_StateCmd_ArchiveArtifact_RefusesClobber(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nrevision: 5\n---\n# S\n")
	os.WriteFile(specDir+"/review-r5.md", []byte("old"), 0o644)
	os.WriteFile(specDir+"/review.md", []byte("new"), 0o644)
	if code, _, _ := runCmd(t, repo, "archive-artifact", specDir, "review", "5"); code == 0 {
		t.Error("clobbering an existing review-r5.md must be refused")
	}
	if b, _ := os.ReadFile(specDir + "/review.md"); string(b) != "new" {
		t.Error("source must remain intact when the move is refused")
	}
}
