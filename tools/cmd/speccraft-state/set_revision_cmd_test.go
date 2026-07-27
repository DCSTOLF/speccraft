package main

// Spec 0036 T13 (AC8, AC9, AC14) — `speccraft-state set-revision <spec.md> <N>`.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func Test_StateCmd_SetRevision_Writes_RejectsDemotion_RejectsOverflow(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nstatus: draft\nrevision: 5\n---\n# S\n")
	spec := filepath.Join(specDir, "spec.md")
	if code, _, se := runCmd(t, repo, "set-revision", spec, "7"); code != 0 {
		t.Fatalf("forward exit=%d stderr=%s", code, se)
	}
	if b, _ := os.ReadFile(spec); !strings.Contains(string(b), "revision: 7") {
		t.Errorf("revision not written: %s", b)
	}
	if code, _, _ := runCmd(t, repo, "set-revision", spec, "3"); code == 0 {
		t.Error("demotion must exit non-zero")
	}
	if code, _, _ := runCmd(t, repo, "set-revision", spec, "99999999999999999999999999"); code == 0 {
		t.Error("over-uint64 argument must exit non-zero")
	}
	if code, _, _ := runCmd(t, repo, "set-revision", spec, "-1"); code == 0 {
		t.Error("negative argument must exit non-zero")
	}
}
