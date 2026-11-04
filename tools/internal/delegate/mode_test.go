package delegate_test

// Spec 0054 — registry dispatch modes. ACs 1, 2, 3.
//
// AC1: LoadConfig accepts cli | acp | codex-plugin | subagent; an OMITTED mode
// normalizes to cli (today's behaviour); an explicitly empty or unrecognised
// value — including case variants — is a named error.

import (
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
