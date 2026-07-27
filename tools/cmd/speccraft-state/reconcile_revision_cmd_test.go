package main

// Spec 0036 T15 (AC5) — `speccraft-state reconcile-revision <specDir>`.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func Test_StateCmd_ReconcileRevision_HealsToEffective(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nstatus: draft\nrevision: 3\n---\n# S\n")
	os.WriteFile(filepath.Join(specDir, "review-r5.md"), []byte("x"), 0o644)
	if code, _, se := runCmd(t, repo, "reconcile-revision", specDir); code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, se)
	}
	if b, _ := os.ReadFile(filepath.Join(specDir, "spec.md")); !strings.Contains(string(b), "revision: 6") {
		t.Errorf("not healed to 6: %s", b)
	}
}

func Test_StateCmd_ReconcileRevision_NoOpWhenLeads_ByteIdentical(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nstatus: draft\nrevision: 9\n---\n# S\n")
	os.WriteFile(filepath.Join(specDir, "review-r5.md"), []byte("x"), 0o644)
	spec := filepath.Join(specDir, "spec.md")
	before, _ := os.ReadFile(spec)
	if code, _, se := runCmd(t, repo, "reconcile-revision", specDir); code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, se)
	}
	if after, _ := os.ReadFile(spec); string(before) != string(after) {
		t.Error("reconcile no-op must be byte-identical when the counter already leads")
	}
}

func Test_StateCmd_ReconcileRevision_Idempotent(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nstatus: draft\nrevision: 3\n---\n# S\n")
	os.WriteFile(filepath.Join(specDir, "review-r5.md"), []byte("x"), 0o644)
	spec := filepath.Join(specDir, "spec.md")
	runCmd(t, repo, "reconcile-revision", specDir)
	once, _ := os.ReadFile(spec)
	runCmd(t, repo, "reconcile-revision", specDir)
	twice, _ := os.ReadFile(spec)
	if string(once) != string(twice) {
		t.Error("reconcile-revision must be idempotent")
	}
}
