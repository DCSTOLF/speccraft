package main

// Tests for the `speccraft-state plugin-root` subcommand (spec 0030 AC1).
//
// The subcommand wraps speccraft.ResolvePluginRoot(), which reads
// SPECCRAFT_PLUGIN_ROOT / CLAUDE_PLUGIN_ROOT and os.Executable(). We drive the
// happy path through the explicit override (SPECCRAFT_PLUGIN_ROOT) so the test
// does not depend on where the test binary happens to live, and drive the
// failure path by clearing both env vars (os.Executable() = the test binary,
// which has no validating plugin-root ancestor).

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newValidRootForCmd(t *testing.T) string {
	t.Helper()
	root := filepath.Join(t.TempDir(), "plugin")
	for _, d := range []string{".claude-plugin", "bin", "commands", "templates"} {
		if err := os.MkdirAll(filepath.Join(root, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(root, ".claude-plugin", "plugin.json"),
		[]byte(`{"name":"speccraft","version":"0.0.0"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	abs, err := filepath.Abs(root)
	if err != nil {
		t.Fatal(err)
	}
	return abs
}

func Test_StateCmd_PluginRoot_PrintsValidRoot_Exit0(t *testing.T) {
	repo := makeRepo(t)
	root := newValidRootForCmd(t)
	t.Setenv("SPECCRAFT_PLUGIN_ROOT", root)
	t.Setenv("CLAUDE_PLUGIN_ROOT", "")
	code, stdout, stderr := runCmd(t, repo, "plugin-root")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	if got := strings.TrimSpace(stdout); got != root {
		t.Errorf("plugin-root = %q, want %q", got, root)
	}
}

func Test_StateCmd_PluginRoot_Unresolvable_Exit1_NamesSources(t *testing.T) {
	repo := makeRepo(t)
	t.Setenv("SPECCRAFT_PLUGIN_ROOT", "")
	t.Setenv("CLAUDE_PLUGIN_ROOT", "")
	code, _, stderr := runCmd(t, repo, "plugin-root")
	if code == 0 {
		t.Fatal("exit = 0, want non-zero when no plugin root resolves")
	}
	if !strings.Contains(stderr, "SPECCRAFT_PLUGIN_ROOT") || !strings.Contains(stderr, "CLAUDE_PLUGIN_ROOT") {
		t.Errorf("stderr does not name the sources tried: %q", stderr)
	}
}
