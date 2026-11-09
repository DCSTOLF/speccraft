package delegate_test

// Spec 0054 — registry dispatch modes. ACs 1, 2, 3.
//
// AC1: LoadConfig accepts cli | acp | codex-plugin | subagent; an OMITTED mode
// normalizes to cli (today's behaviour); an explicitly empty or unrecognised
// value — including case variants — is a named error.

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/delegate"
)

// writeRegistry builds a repo root whose .speccraft/agents.toml is exactly
// body. Distinct from toml_test.go's makeAgentRepo, which pins one fixture.
func writeRegistry(t *testing.T, body string) string {
	t.Helper()
	tmp := t.TempDir()
	dir := filepath.Join(tmp, ".speccraft")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "agents.toml"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return tmp
}

// oneAgent wraps a single [[agents]] body in a minimal registry.
func oneAgent(body string) string {
	return "[defaults]\nreview_quorum = 1\n\n[[agents]]\n" + body
}

func Test_LoadConfig_Mode_AcceptsFourModes(t *testing.T) {
	// Each mode's entry carries only fields legal for that mode: strict-key
	// checking (AC2) lands in step 4, but writing illegal fields here would
	// make these rows fail later for the wrong reason.
	for _, tc := range []struct{ mode, extra string }{
		{"cli", "cmd = [\"codex\", \"exec\"]\ninput = \"stdin\"\n"},
		{"acp", "acp_agent = \"codex\"\n"},
		{"codex-plugin", "effort = \"medium\"\n"},
		{"subagent", "subagent_type = \"speccraft:reviewer\"\n"},
	} {
		t.Run(tc.mode, func(t *testing.T) {
			root := writeRegistry(t, oneAgent(
				"name = \"a\"\nmode = \""+tc.mode+"\"\n"+tc.extra))
			cfg, err := delegate.LoadConfig(root)
			if err != nil {
				t.Fatalf("mode %q must load, got error: %v", tc.mode, err)
			}
			if len(cfg.Agents) != 1 {
				t.Fatalf("want 1 agent, got %d", len(cfg.Agents))
			}
			if got := cfg.Agents[0].Mode; got != tc.mode {
				t.Errorf("Mode = %q, want %q", got, tc.mode)
			}
		})
	}
}

func Test_LoadConfig_Mode_OmittedNormalizesToCLI(t *testing.T) {
	// The key is ABSENT, not empty. This is today's shipped behaviour and must
	// stay: host registries written before this spec omit `mode`.
	root := writeRegistry(t, oneAgent(
		"name = \"a\"\ncmd = [\"codex\", \"exec\"]\ninput = \"stdin\"\n"))
	cfg, err := delegate.LoadConfig(root)
	if err != nil {
		t.Fatalf("an omitted mode must load, got error: %v", err)
	}
	if got := cfg.Agents[0].Mode; got != "cli" {
		t.Errorf("Mode = %q, want %q (omitted normalizes to cli)", got, "cli")
	}
}

func Test_LoadConfig_Mode_ExplicitEmptyIsNamedError(t *testing.T) {
	// Explicitly empty is NOT the same as absent — that distinction is the
	// whole point, and it needs toml.MetaData.IsDefined to detect.
	root := writeRegistry(t, oneAgent("name = \"needle\"\nmode = \"\"\n"))
	_, err := delegate.LoadConfig(root)
	if err == nil {
		t.Fatal("an explicitly empty mode must be an error, got nil")
	}
	assertNamesAgentAndModes(t, err.Error(), "needle")
}

func Test_LoadConfig_Mode_CaseVariantsRejected(t *testing.T) {
	// Modes are case-SENSITIVE. A permissive decode would accept these
	// silently and then route on a mode no dispatcher knows.
	for _, mode := range []string{"Subagent", "CLI", "Codex-Plugin", "ACP"} {
		t.Run(mode, func(t *testing.T) {
			root := writeRegistry(t, oneAgent(
				"name = \"needle\"\nmode = \""+mode+"\"\n"))
			_, err := delegate.LoadConfig(root)
			if err == nil {
				t.Fatalf("mode %q must be rejected, got nil error", mode)
			}
			assertNamesAgentAndModes(t, err.Error(), "needle")
		})
	}
}

// --- AC2: strict keys and per-mode enums on the NEW modes only -------------

func Test_LoadConfig_StrictKeys_RejectedOnNewModes(t *testing.T) {
	// On codex-plugin and subagent entries, a field belonging to another mode
	// is a named error rather than silently ignored. Scoped to the new modes:
	// cli/acp keep today's permissive decode (AC3).
	for _, tc := range []struct{ name, mode, field, line string }{
		{"cmd-on-codex-plugin", "codex-plugin", "cmd", "cmd = [\"codex\"]\n"},
		{"input-on-codex-plugin", "codex-plugin", "input", "input = \"stdin\"\n"},
		{"acp_agent-on-codex-plugin", "codex-plugin", "acp_agent", "acp_agent = \"codex\"\n"},
		{"cmd-on-subagent", "subagent", "cmd", "cmd = [\"claude\"]\n"},
		{"input-on-subagent", "subagent", "input", "input = \"stdin\"\n"},
		{"acp_agent-on-subagent", "subagent", "acp_agent", "acp_agent = \"codex\"\n"},
		{"subagent_type-on-codex-plugin", "codex-plugin", "subagent_type", "subagent_type = \"x\"\n"},
		{"effort-on-subagent", "subagent", "effort", "effort = \"high\"\n"},
		{"plugin_root-on-subagent", "subagent", "plugin_root", "plugin_root = \"/tmp/x\"\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := writeRegistry(t, oneAgent(
				"name = \"needle\"\nmode = \""+tc.mode+"\"\n"+tc.line))
			_, err := delegate.LoadConfig(root)
			if err == nil {
				t.Fatalf("%s on a %s entry must be an error, got nil", tc.field, tc.mode)
			}
			msg := err.Error()
			if !strings.Contains(msg, "needle") {
				t.Errorf("error must name the agent, got: %s", msg)
			}
			if !strings.Contains(msg, tc.field) {
				t.Errorf("error must name the offending key %q, got: %s", tc.field, msg)
			}
		})
	}
}

func Test_LoadConfig_Effort_OutsideSixValues_IsNamedError(t *testing.T) {
	for _, ok := range []string{"none", "minimal", "low", "medium", "high", "xhigh"} {
		root := writeRegistry(t, oneAgent(
			"name = \"a\"\nmode = \"codex-plugin\"\neffort = \""+ok+"\"\n"))
		if _, err := delegate.LoadConfig(root); err != nil {
			t.Errorf("effort %q must be accepted, got: %v", ok, err)
		}
	}
	root := writeRegistry(t, oneAgent(
		"name = \"needle\"\nmode = \"codex-plugin\"\neffort = \"turbo\"\n"))
	_, err := delegate.LoadConfig(root)
	if err == nil {
		t.Fatal("effort \"turbo\" must be an error, got nil")
	}
	for _, want := range []string{"needle", "effort", "xhigh"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error must mention %q, got: %s", want, err.Error())
		}
	}
}

func Test_LoadConfig_SubagentModel_OutsideFiveValues_IsNamedError(t *testing.T) {
	for _, ok := range []string{"opus", "sonnet", "haiku", "fable", "inherit"} {
		root := writeRegistry(t, oneAgent(
			"name = \"a\"\nmode = \"subagent\"\nmodel = \""+ok+"\"\n"))
		if _, err := delegate.LoadConfig(root); err != nil {
			t.Errorf("model %q must be accepted, got: %v", ok, err)
		}
	}
	root := writeRegistry(t, oneAgent(
		"name = \"needle\"\nmode = \"subagent\"\nmodel = \"gpt-5\"\n"))
	_, err := delegate.LoadConfig(root)
	if err == nil {
		t.Fatal("model \"gpt-5\" must be an error, got nil")
	}
	for _, want := range []string{"needle", "model", "inherit"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error must mention %q, got: %s", want, err.Error())
		}
	}
}

func Test_LoadConfig_NewModeFields_DecodeAndDefault(t *testing.T) {
	// Absent subagent_type defaults to speccraft:reviewer; absent model to
	// inherit; reference_read is opt-out (absent means true).
	root := writeRegistry(t, oneAgent("name = \"a\"\nmode = \"subagent\"\n"))
	cfg, err := delegate.LoadConfig(root)
	if err != nil {
		t.Fatalf("a bare subagent entry must load, got: %v", err)
	}
	a := cfg.Agents[0]
	if a.SubagentType != "speccraft:reviewer" {
		t.Errorf("SubagentType = %q, want %q", a.SubagentType, "speccraft:reviewer")
	}
	if a.Model != "inherit" {
		t.Errorf("Model = %q, want %q", a.Model, "inherit")
	}
	if !a.IsReferenceRead() {
		t.Error("IsReferenceRead() = false, want true when reference_read is absent")
	}

	// An explicit false must survive, or the opt-out is unusable.
	root = writeRegistry(t, oneAgent(
		"name = \"a\"\nmode = \"subagent\"\nreference_read = false\n"))
	cfg, err = delegate.LoadConfig(root)
	if err != nil {
		t.Fatalf("reference_read = false must load, got: %v", err)
	}
	if cfg.Agents[0].IsReferenceRead() {
		t.Error("IsReferenceRead() = true, want false when reference_read = false")
	}

	// Explicit values are not overwritten by the defaults.
	root = writeRegistry(t, oneAgent(
		"name = \"a\"\nmode = \"subagent\"\nsubagent_type = \"custom:rev\"\nmodel = \"opus\"\n"))
	cfg, _ = delegate.LoadConfig(root)
	if cfg.Agents[0].SubagentType != "custom:rev" || cfg.Agents[0].Model != "opus" {
		t.Errorf("explicit values overwritten: type=%q model=%q",
			cfg.Agents[0].SubagentType, cfg.Agents[0].Model)
	}
}

// --- AC3: unknown keys are strict on new modes, permissive on cli/acp -------

func Test_LoadConfig_UnknownKey_OnNewMode_IsNamedError(t *testing.T) {
	// A typo on a new-mode entry must not be silently ignored — that is the
	// whole value of strict keys.
	root := writeRegistry(t, oneAgent(
		"name = \"needle\"\nmode = \"subagent\"\ninstall_hint = \"brew install x\"\n"))
	_, err := delegate.LoadConfig(root)
	if err == nil {
		t.Fatal("an unknown key on a subagent entry must be an error, got nil")
	}
	for _, want := range []string{"needle", "install_hint"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error must mention %q, got: %s", want, err.Error())
		}
	}
}

func Test_LoadConfig_UnknownKey_OnCLIEntry_StillLoads(t *testing.T) {
	// THE REGRESSION FLOOR. cli/acp entries keep today's permissive decode, so
	// no existing host registry stops loading. If strict-key checking ever
	// leaks out of the new modes, this is what catches it.
	root := writeRegistry(t, oneAgent(
		"name = \"a\"\nmode = \"cli\"\ncmd = [\"codex\"]\ninput = \"stdin\"\n"+
			"install_hint = \"brew install codex\"\n"))
	if _, err := delegate.LoadConfig(root); err != nil {
		t.Fatalf("an unknown key on a cli entry must be ignored, got: %v", err)
	}

	// Same for acp, and for an entry with no explicit mode at all.
	root = writeRegistry(t, oneAgent(
		"name = \"a\"\nmode = \"acp\"\nacp_agent = \"codex\"\nwhatever = 3\n"))
	if _, err := delegate.LoadConfig(root); err != nil {
		t.Fatalf("an unknown key on an acp entry must be ignored, got: %v", err)
	}
	root = writeRegistry(t, oneAgent(
		"name = \"a\"\ncmd = [\"codex\"]\ninput = \"stdin\"\nwhatever = 3\n"))
	if _, err := delegate.LoadConfig(root); err != nil {
		t.Fatalf("an unknown key on a mode-less entry must be ignored, got: %v", err)
	}
}

func Test_LoadConfig_KnownKey_OnLegacyEntry_IsNotEnumChecked(t *testing.T) {
	// THE REGRESSION FLOOR, second half. Test_LoadConfig_UnknownKey_On...
	// covers a key the schema does not know; this covers one it DOES know but
	// which belongs to another mode. Found by cross-vendor review of Phase A:
	// the effort enum check fired on every explicit mode, so a host registry
	// carrying `effort` as a note on a cli entry stopped loading on upgrade —
	// exactly the breakage conventions.md §"A capability key added to
	// host-owned config is OPT-OUT" exists to prevent.
	//
	// The asymmetry made it worse than a uniform rule: an entry with no `mode`
	// returned early and loaded, so DELETING `mode = "cli"` fixed the error.
	for _, entry := range []string{
		"name = \"a\"\nmode = \"cli\"\ncmd = [\"codex\"]\ninput = \"stdin\"\neffort = \"turbo\"\n",
		"name = \"a\"\nmode = \"acp\"\nacp_agent = \"codex\"\neffort = \"turbo\"\n",
		"name = \"a\"\ncmd = [\"codex\"]\ninput = \"stdin\"\neffort = \"turbo\"\n",
		"name = \"a\"\nmode = \"cli\"\ncmd = [\"codex\"]\nmodel = \"gpt-5\"\n",
	} {
		root := writeRegistry(t, oneAgent(entry))
		cfg, err := delegate.LoadConfig(root)
		if err != nil {
			t.Errorf("a legacy entry must not be enum-checked, got: %v\nentry:\n%s", err, entry)
			continue
		}
		// Ignored, not honoured: a cli entry must not come back claiming an
		// effort the dispatcher would then have to interpret.
		if got := cfg.Agents[0].Mode; got != "cli" && got != "acp" {
			t.Errorf("Mode = %q, want cli or acp", got)
		}
	}
}

func Test_LoadConfig_Effort_ValidatedOnOwningModeOnly(t *testing.T) {
	// The two halves of the same rule, asserted together so neither can drift:
	// the mode that OWNS `effort` still rejects a bad value, and the identical
	// value on a mode that does not own it is ignored. Keeping these in one
	// test is the point — scoping the check by deleting it would pass the
	// permissive half alone.
	const bad = "effort = \"turbo\"\n"

	root := writeRegistry(t, oneAgent("name = \"owner\"\nmode = \"codex-plugin\"\n"+bad))
	if _, err := delegate.LoadConfig(root); err == nil {
		t.Error("codex-plugin owns effort, so a bad value must still be rejected")
	}

	root = writeRegistry(t, oneAgent("name = \"other\"\nmode = \"cli\"\ncmd = [\"x\"]\n"+bad))
	if _, err := delegate.LoadConfig(root); err != nil {
		t.Errorf("cli does not own effort, so the same value must be ignored, got: %v", err)
	}
}

func Test_LoadConfig_UnknownKeys_ReportedDeterministically(t *testing.T) {
	// Two unknown keys on one new-mode entry. The loop over them is a Go map,
	// so returning on the first one makes the error text depend on hash order
	// and any assertion naming a specific key flakes. Report ALL of them, in
	// sorted order, so the message is a function of the input alone.
	root := writeRegistry(t, oneAgent(
		"name = \"needle\"\nmode = \"subagent\"\nzeta = 1\nalpha = 2\n"))
	var first string
	for i := 0; i < 24; i++ {
		_, err := delegate.LoadConfig(root)
		if err == nil {
			t.Fatal("two unknown keys on a subagent entry must be an error, got nil")
		}
		if i == 0 {
			first = err.Error()
			continue
		}
		if err.Error() != first {
			t.Fatalf("error text is not deterministic across loads:\n  %s\n  %s", first, err.Error())
		}
	}
	for _, want := range []string{"needle", "alpha", "zeta"} {
		if !strings.Contains(first, want) {
			t.Errorf("error must mention every unknown key, missing %q: %s", want, first)
		}
	}
	if strings.Index(first, "alpha") > strings.Index(first, "zeta") {
		t.Errorf("unknown keys must be listed in sorted order, got: %s", first)
	}
}

func Test_LoadConfig_RealRegistries_LoadUnchanged(t *testing.T) {
	// Every registry this repo actually ships must keep loading. LoadConfig
	// resolves <root>/.speccraft/agents.toml, so each candidate is staged into
	// its own temp root rather than loaded in place.
	repoRoot := "../../.." // tools/internal/delegate -> repo root
	candidates := []string{
		filepath.Join(repoRoot, ".speccraft", "agents.toml"),
		filepath.Join(repoRoot, "templates", "speccraft", "agents.toml"),
	}
	// Plus every registry fixture anywhere under tests/, so fixtures added
	// later are covered without editing this test.
	//
	// NOT filepath.Glob("tests/**/agents.toml"): Go's Glob has no recursive
	// `**` — each star matches only non-separator runs, so that pattern means
	// `tests/<one-dir>/agents.toml` and matched NOTHING in this tree. The loop
	// was silently empty while claiming to cover the fixture corpus. Caught by
	// cross-vendor review of Phase A; an assertion over an empty set is not an
	// assertion.
	walked := 0
	err := filepath.WalkDir(filepath.Join(repoRoot, "tests"),
		func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			walked++
			if !d.IsDir() && d.Name() == "agents.toml" {
				candidates = append(candidates, path)
			}
			return nil
		})
	if err != nil {
		t.Fatal(err)
	}

	// Prove the walk reached a populated tree. Asserting len(candidates) >= 2
	// would NOT bite — the two shipped registries are appended unconditionally
	// above — and there are legitimately zero agents.toml fixtures under tests/
	// today, so the count of matches cannot be asserted either. What can go
	// silently wrong is the walk root: point it at the wrong directory and every
	// future fixture is skipped. That is what this catches.
	if walked < 2 {
		t.Fatalf("walk of %s visited %d entries; the fixture tree is not being traversed",
			filepath.Join(repoRoot, "tests"), walked)
	}

	for _, src := range candidates {
		body, err := os.ReadFile(src)
		if err != nil {
			t.Fatalf("cannot read %s: %v", src, err)
		}
		root := writeRegistry(t, string(body))
		cfg, err := delegate.LoadConfig(root)
		if err != nil {
			t.Errorf("%s must load unchanged, got: %v", src, err)
			continue
		}
		// "Unchanged" is about the decoded VALUES, not merely the absence of an
		// error: a loader that accepted the file and then normalized a mode or
		// dropped a cmd would pass an error-only assertion.
		if len(cfg.Agents) == 0 {
			t.Errorf("%s decoded to zero agents", src)
		}
		for _, a := range cfg.Agents {
			if a.Name == "" {
				t.Errorf("%s: an agent decoded with an empty name", src)
			}
			if !contains([]string{"cli", "acp", "codex-plugin", "subagent"}, a.Mode) {
				t.Errorf("%s: agent %q decoded mode %q, outside the valid set", src, a.Name, a.Mode)
			}
			if a.Mode == "cli" && len(a.Cmd) == 0 {
				t.Errorf("%s: cli agent %q decoded an empty cmd", src, a.Name)
			}
		}
	}
}

// contains is local to the test: asserting against delegate's own unexported
// helper would make the assertion depend on the code under test.
func contains(set []string, v string) bool {
	for _, s := range set {
		if s == v {
			return true
		}
	}
	return false
}

// assertNamesAgentAndModes pins the diagnostic quality the AC asks for: the
// error must name the offending agent AND all four valid values, so an
// operator can fix the registry without reading our source.
func assertNamesAgentAndModes(t *testing.T, msg, agent string) {
	t.Helper()
	if !strings.Contains(msg, agent) {
		t.Errorf("error must name the agent %q, got: %s", agent, msg)
	}
	for _, want := range []string{"cli", "acp", "codex-plugin", "subagent"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error must name the valid mode %q, got: %s", want, msg)
		}
	}
}
