package speccraft_test

// Tests for the plugin-root resolver (spec 0030 AC1–AC5).
//
// The resolver's core is a PURE function, ResolvePluginRootFrom(speccraftRoot,
// claudeRoot, exePath), that takes injected inputs — no os.Getenv/os.Executable
// I/O — so the precedence table (AC2) and the EvalSymlinks-before-ascend rule
// (AC4) are table-testable exactly like FindRoot(dir). The thin ResolvePluginRoot()
// wrapper (exercised via the speccraft-state `plugin-root` subcommand test) does
// the environment/executable I/O.
//
// Validity predicate (AC5): a directory is a valid plugin root iff it contains
// .claude-plugin/plugin.json AND bin/ AND commands/ AND templates/.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// newValidRoot builds a fixture directory that satisfies IsValidPluginRoot and
// returns its absolute path. name lets a single test build several distinct roots.
func newValidRoot(t *testing.T, name string) string {
	t.Helper()
	root := filepath.Join(t.TempDir(), name)
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

func Test_IsValidPluginRoot_AcceptsCompleteRoot(t *testing.T) {
	root := newValidRoot(t, "plugin")
	if !speccraft.IsValidPluginRoot(root) {
		t.Errorf("IsValidPluginRoot(%q) = false, want true", root)
	}
}

func Test_IsValidPluginRoot_RequiresManifest(t *testing.T) {
	// A dir with bin/ + commands/ + templates/ but NO .claude-plugin/plugin.json
	// must be rejected (AC5 negative — a coincidentally shaped tree is not a root).
	root := filepath.Join(t.TempDir(), "nomanifest")
	for _, d := range []string{"bin", "commands", "templates"} {
		if err := os.MkdirAll(filepath.Join(root, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if speccraft.IsValidPluginRoot(root) {
		t.Errorf("IsValidPluginRoot(%q) = true, want false (no plugin.json manifest)", root)
	}
}

func Test_ResolvePluginRoot_SelfDerive_BinLayout(t *testing.T) {
	// AC2a / AC3: both env sources empty; self-derivation from a binary directly
	// under <root>/bin/ resolves <root>.
	root := newValidRoot(t, "plugin")
	exe := filepath.Join(root, "bin", "speccraft-state")
	got, err := speccraft.ResolvePluginRootFrom("", "", exe)
	if err != nil {
		t.Fatalf("err = %v, want nil", err)
	}
	if got != root {
		t.Errorf("resolved = %q, want %q", got, root)
	}
}

func Test_ResolvePluginRoot_SelfDerive_ToolsBinLayout(t *testing.T) {
	// AC2b: dogfood layout — binary under <root>/tools/bin/; ascent walks up past
	// tools/ to the nearest validating ancestor <root>.
	root := newValidRoot(t, "plugin")
	if err := os.MkdirAll(filepath.Join(root, "tools", "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	exe := filepath.Join(root, "tools", "bin", "speccraft-state")
	got, err := speccraft.ResolvePluginRootFrom("", "", exe)
	if err != nil {
		t.Fatalf("err = %v, want nil", err)
	}
	if got != root {
		t.Errorf("resolved = %q, want %q (must ascend past tools/)", got, root)
	}
}

func Test_ResolvePluginRoot_ClaudeEnvInvalidParent_Skipped_SelfDeriveWins(t *testing.T) {
	// AC2c (the field bug): CLAUDE_PLUGIN_ROOT points at the plugins *parent*
	// (no manifest → invalid). It is skipped (not fatal); self-derivation wins.
	root := newValidRoot(t, "plugin")
	parent := filepath.Dir(root) // has no .claude-plugin/plugin.json
	exe := filepath.Join(root, "bin", "speccraft-state")
	got, err := speccraft.ResolvePluginRootFrom("", parent, exe)
	if err != nil {
		t.Fatalf("err = %v, want nil (invalid CLAUDE_PLUGIN_ROOT must fall through)", err)
	}
	if got != root {
		t.Errorf("resolved = %q, want %q (self-derivation should win over invalid env)", got, root)
	}
}

func Test_ResolvePluginRoot_SpeccraftEnvValid_WinsOverAll(t *testing.T) {
	// AC2d: SPECCRAFT_PLUGIN_ROOT (valid) wins over a different valid
	// CLAUDE_PLUGIN_ROOT and over self-derivation from a third valid root.
	override := newValidRoot(t, "override")
	claude := newValidRoot(t, "claude")
	self := newValidRoot(t, "self")
	exe := filepath.Join(self, "bin", "speccraft-state")
	got, err := speccraft.ResolvePluginRootFrom(override, claude, exe)
	if err != nil {
		t.Fatalf("err = %v, want nil", err)
	}
	if got != override {
		t.Errorf("resolved = %q, want %q (SPECCRAFT_PLUGIN_ROOT must win)", got, override)
	}
}

func Test_ResolvePluginRoot_SpeccraftEnvInvalid_HardError(t *testing.T) {
	// AC2e: an explicit override that does not validate is a hard error, even
	// though self-derivation could otherwise succeed — a misconfigured override
	// must not be silently ignored.
	bad := filepath.Join(t.TempDir(), "not-a-root")
	if err := os.MkdirAll(bad, 0o755); err != nil {
		t.Fatal(err)
	}
	self := newValidRoot(t, "self")
	exe := filepath.Join(self, "bin", "speccraft-state")
	got, err := speccraft.ResolvePluginRootFrom(bad, "", exe)
	if err == nil {
		t.Fatalf("err = nil (resolved %q), want error for invalid explicit override", got)
	}
	if !strings.Contains(err.Error(), "SPECCRAFT_PLUGIN_ROOT") {
		t.Errorf("error %q does not name SPECCRAFT_PLUGIN_ROOT", err.Error())
	}
}

func Test_ResolvePluginRoot_SymlinkedExe_ResolvesRealInstall(t *testing.T) {
	// AC4: os.Executable() may be reached via a symlink; EvalSymlinks must be
	// applied before ascending so the REAL install directory is found.
	root := newValidRoot(t, "plugin")
	realExe := filepath.Join(root, "bin", "speccraft-state")
	if err := os.WriteFile(realExe, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(t.TempDir(), "speccraft-state-link")
	if err := os.Symlink(realExe, link); err != nil {
		t.Skipf("symlink unsupported: %v", err)
	}
	got, err := speccraft.ResolvePluginRootFrom("", "", link)
	if err != nil {
		t.Fatalf("err = %v, want nil", err)
	}
	// Assert asymmetrically (spec 0033): normalize only the EXPECTED root through
	// EvalSymlinks — on macOS t.TempDir() sits under /var, a symlink to
	// /private/var — and compare the resolver's got to it directly. Do NOT
	// normalize got: a resolver that skipped EvalSymlinks would return the
	// un-normalized path (or ascend from the wrong dir via the through-symlink
	// exe and error), and must still fail. On Linux EvalSymlinks(root) == root,
	// so the assertion is unchanged.
	want, err := filepath.EvalSymlinks(root)
	if err != nil {
		t.Fatalf("EvalSymlinks(root) = %v", err)
	}
	if got != want {
		t.Errorf("resolved = %q, want %q (EvalSymlinks must resolve the link to the real install)", got, want)
	}
}

func Test_ResolvePluginRoot_NoneResolvable_ErrorNamesAllSources(t *testing.T) {
	// AC1 failure contract: no env sources and an exe with no validating ancestor
	// → error whose message names each source tried.
	lonely := filepath.Join(t.TempDir(), "sub", "bin", "speccraft-state")
	if err := os.MkdirAll(filepath.Dir(lonely), 0o755); err != nil {
		t.Fatal(err)
	}
	_, err := speccraft.ResolvePluginRootFrom("", "", lonely)
	if err == nil {
		t.Fatal("err = nil, want error when nothing resolves")
	}
	msg := err.Error()
	for _, want := range []string{"SPECCRAFT_PLUGIN_ROOT", "CLAUDE_PLUGIN_ROOT"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error %q does not name source %q", msg, want)
		}
	}
}
