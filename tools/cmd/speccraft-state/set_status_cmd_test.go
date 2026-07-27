package main

// Spec 0036 T13 (AC8, AC9) — `speccraft-state set-status <spec.md> <status>`.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func Test_StateCmd_SetStatus_ValidWrites_InvalidNonZero(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nstatus: draft\n---\n# S\n")
	spec := filepath.Join(specDir, "spec.md")
	if code, _, se := runCmd(t, repo, "set-status", spec, "reviewed"); code != 0 {
		t.Fatalf("valid status exit=%d stderr=%s", code, se)
	}
	b, _ := os.ReadFile(spec)
	if !strings.Contains(string(b), "status: reviewed") {
		t.Errorf("status not written: %s", b)
	}
	if code, _, _ := runCmd(t, repo, "set-status", spec, "bogus"); code == 0 {
		t.Error("invalid status must exit non-zero")
	}
}

func Test_StateCmd_SetStatus_RefusesClosed(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nstatus: closed\n---\n# S\n")
	spec := filepath.Join(specDir, "spec.md")
	if code, _, _ := runCmd(t, repo, "set-status", spec, "draft"); code == 0 {
		t.Error("mutating a closed spec must exit non-zero")
	}
}
