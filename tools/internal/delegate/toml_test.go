package delegate_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/delegate"
)

const sampleTOML = `
[defaults]
review_quorum = 1
review_timeout_s = 600

[[agents]]
name = "codex"
mode = "cli"
cmd = ["codex", "exec", "--full-auto"]
input = "stdin"
strengths = ["refactoring", "review"]

[[agents]]
name = "opencode"
mode = "cli"
cmd = ["opencode", "run"]
input = "argv"
strengths = ["analysis"]

[[agents]]
name = "codex-acp"
mode = "acp"
acp_agent = "codex"
strengths = ["refactoring"]
enabled = false
`

func makeAgentRepo(t *testing.T) string {
	t.Helper()
	tmp := t.TempDir()
	dir := filepath.Join(tmp, ".speccraft")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "agents.toml"), []byte(sampleTOML), 0o644); err != nil {
		t.Fatal(err)
	}
	return tmp
}

func TestLoadConfig(t *testing.T) {
	root := makeAgentRepo(t)
	cfg, err := delegate.LoadConfig(root)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Defaults.ReviewQuorum != 1 {
		t.Errorf("quorum = %d, want 1", cfg.Defaults.ReviewQuorum)
	}
	if len(cfg.Agents) != 3 {
		t.Errorf("agents = %d, want 3", len(cfg.Agents))
	}
}

func TestFindAgent(t *testing.T) {
	root := makeAgentRepo(t)
	cfg, _ := delegate.LoadConfig(root)

	a, err := cfg.FindAgent("codex")
	if err != nil {
		t.Fatal(err)
	}
	if a.Input != "stdin" {
		t.Errorf("input = %q, want stdin", a.Input)
	}

	_, err = cfg.FindAgent("notfound")
	if err == nil {
		t.Error("expected error for missing agent")
	}
}

func TestEnabledAgents(t *testing.T) {
	root := makeAgentRepo(t)
	cfg, _ := delegate.LoadConfig(root)

	enabled := cfg.EnabledAgents()
	if len(enabled) != 2 { // codex + opencode; codex-acp is disabled
		t.Errorf("enabled = %d, want 2", len(enabled))
	}
}
