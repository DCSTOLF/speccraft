package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// mkWorkspace makes a temp repo whose .speccraft is kind = workspace, with an
// optional workspace.yml body (spec 0037).
func mkWorkspace(t *testing.T, ymlBody string) string {
	t.Helper()
	tmp := t.TempDir()
	sd := filepath.Join(tmp, ".speccraft")
	if err := os.MkdirAll(sd, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sd, "speccraft.toml"), []byte("kind = \"workspace\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if ymlBody != "" {
		if err := os.WriteFile(filepath.Join(tmp, "workspace.yml"), []byte(ymlBody), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return tmp
}

func Test_StateCmd_ListMembers_EmitsPresenceLines(t *testing.T) {
	ws := mkWorkspace(t, "members:\n  - path: ./api\n  - path: ./web\n")
	if err := os.MkdirAll(filepath.Join(ws, "api"), 0o755); err != nil { // api present, web missing
		t.Fatal(err)
	}
	code, stdout, stderr := runCmd(t, ws, "list-members")
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	if !strings.Contains(stdout, "present\t./api") || !strings.Contains(stdout, "missing\t./web") {
		t.Errorf("stdout=%q, want present ./api + missing ./web", stdout)
	}
	if !strings.Contains(stderr, "missing member") || !strings.Contains(stderr, "./web") {
		t.Errorf("stderr=%q, want missing-member warning for ./web", stderr)
	}
}

func Test_StateCmd_ListMembers_EmptyMembership_ExitZero(t *testing.T) {
	ws := mkWorkspace(t, "members:\n")
	code, stdout, stderr := runCmd(t, ws, "list-members")
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	if strings.TrimSpace(stdout) != "" {
		t.Errorf("stdout=%q, want empty for empty membership", stdout)
	}
}

func Test_StateCmd_ListMembers_ManifestAbsent_NonZero(t *testing.T) {
	ws := mkWorkspace(t, "") // kind=workspace but no workspace.yml
	code, _, stderr := runCmd(t, ws, "list-members")
	if code == 0 {
		t.Fatal("want non-zero for absent manifest")
	}
	if !strings.Contains(stderr, "no workspace.yml") {
		t.Errorf("stderr=%q, want 'no workspace.yml'", stderr)
	}
}

func Test_StateCmd_ListMembers_MalformedManifest_NonZero(t *testing.T) {
	ws := mkWorkspace(t, "members: [./api, ./web]\n") // flow style → malformed
	code, _, stderr := runCmd(t, ws, "list-members")
	if code == 0 {
		t.Fatal("want non-zero for malformed manifest")
	}
	if !strings.Contains(stderr, "malformed workspace.yml") {
		t.Errorf("stderr=%q, want 'malformed workspace.yml'", stderr)
	}
}

func Test_StateCmd_Usage_ListsTopologySubcommands(t *testing.T) {
	ws := mkWorkspace(t, "")
	_, _, stderr := runCmd(t, ws) // no args → usage on stderr
	for _, sub := range []string{"list-members", "get-status", "get-frontmatter"} {
		if !strings.Contains(stderr, sub) {
			t.Errorf("usage missing %q; stderr=%q", sub, stderr)
		}
	}
}
