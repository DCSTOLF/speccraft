package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// mkRepoWithToml makes a temp dir with a .speccraft/speccraft.toml carrying the
// given body (empty body → the .speccraft dir but no toml file). Returns the dir.
func mkRepoWithToml(t *testing.T, tomlBody string) string {
	t.Helper()
	tmp := t.TempDir()
	sd := filepath.Join(tmp, ".speccraft")
	if err := os.MkdirAll(sd, 0o755); err != nil {
		t.Fatal(err)
	}
	if tomlBody != "" {
		if err := os.WriteFile(filepath.Join(sd, "speccraft.toml"), []byte(tomlBody), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return tmp
}

func Test_StateCmd_ConfigKind_Workspace_PrintsWorkspace(t *testing.T) {
	dir := mkRepoWithToml(t, "kind = \"workspace\"\n")
	code, stdout, stderr := runCmd(t, dir, "config-kind", dir)
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	if strings.TrimSpace(stdout) != "workspace" {
		t.Errorf("stdout=%q, want workspace", stdout)
	}
}

func Test_StateCmd_ConfigKind_Repo_PrintsRepo(t *testing.T) {
	// Explicit repo kind and absent-kind default both resolve to "repo".
	for _, body := range []string{"kind = \"repo\"\n", "[tdd]\ntest_roots = []\n"} {
		dir := mkRepoWithToml(t, body)
		code, stdout, stderr := runCmd(t, dir, "config-kind", dir)
		if code != 0 {
			t.Fatalf("body=%q exit=%d stderr=%s", body, code, stderr)
		}
		if strings.TrimSpace(stdout) != "repo" {
			t.Errorf("body=%q stdout=%q, want repo", body, stdout)
		}
	}
}

func Test_StateCmd_ConfigKind_StrictInvalid_NonZero(t *testing.T) {
	dir := mkRepoWithToml(t, "kind = \"bogus\"\n")
	code, _, stderr := runCmd(t, dir, "config-kind", dir)
	if code == 0 {
		t.Fatal("want non-zero for strict-invalid kind")
	}
	if !strings.Contains(stderr, "bogus") {
		t.Errorf("stderr=%q, want it to name the invalid value", stderr)
	}
}

func Test_StateCmd_ConfigKind_NoSpeccraft_NonZero(t *testing.T) {
	// A bare dir with NO .speccraft/ must be non-zero: ReadConfigStrict would
	// otherwise coerce a missing config to kind=repo, wrongly marking any dir a
	// candidate.
	tmp := t.TempDir()
	code, _, stderr := runCmd(t, tmp, "config-kind", tmp)
	if code == 0 {
		t.Fatal("want non-zero for a dir with no .speccraft/")
	}
	if !strings.Contains(stderr, ".speccraft") {
		t.Errorf("stderr=%q, want it to mention .speccraft", stderr)
	}
}
