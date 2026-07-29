package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func Test_StateCmd_FindWorkspaceRoot_ReturnsSelfForWorkspaceRoot(t *testing.T) {
	ws := mkWorkspace(t, "") // kind = "workspace"
	code, stdout, stderr := runCmd(t, ws, "find-workspace-root")
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	want, _ := filepath.EvalSymlinks(ws) // normalize only the EXPECTED
	if strings.TrimSpace(stdout) != want {
		t.Errorf("stdout=%q, want %q", strings.TrimSpace(stdout), want)
	}
}

func Test_StateCmd_FindWorkspaceRoot_FromChildDir_ReturnsWorkspaceAncestor(t *testing.T) {
	ws := mkWorkspace(t, "")
	child := filepath.Join(ws, "sub", "deep")
	if err := os.MkdirAll(child, 0o755); err != nil {
		t.Fatal(err)
	}
	code, stdout, stderr := runCmd(t, child, "find-workspace-root")
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	want, _ := filepath.EvalSymlinks(ws)
	if strings.TrimSpace(stdout) != want {
		t.Errorf("stdout=%q, want workspace ancestor %q", strings.TrimSpace(stdout), want)
	}
}

// Usage must advertise the two new spec-0042 topology subcommands (spec 0015
// argument/usage accuracy discipline).
func Test_StateCmd_Usage_ListsWorkspaceInitSubcommands(t *testing.T) {
	ws := mkWorkspace(t, "")
	_, _, stderr := runCmd(t, ws) // no args → usage on stderr
	for _, sub := range []string{"config-kind", "find-workspace-root"} {
		if !strings.Contains(stderr, sub) {
			t.Errorf("usage missing %q; stderr=%q", sub, stderr)
		}
	}
}
