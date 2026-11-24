package delegate_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/delegate"
)

// Spec 0054 AC25 — the registry a fresh /speccraft:init copies into a host repo
// must LOAD, and must decode to the configuration the template appears to
// describe.
//
// The bats rows beside this one parse the template's text per entry. That
// proves what the file SAYS. This proves what the loader SEES, which is a
// different question: a key the loader does not recognise, or a mode arm that
// rejects a combination the template ships, would leave every freshly
// initialized repo unable to run a review round at all — and the text rows
// would still be green.
//
// CACHING: both tests in this file read a file that is NOT a Go source input,
// so `go test` will not re-run them when the template changes — it serves the
// cached pass and reports `(cached)`. Verified: editing the template to ship
// the subagent entry disabled left `go test ./internal/delegate/` green, and
// only `-count=1` reddened it. So anything checking these must pass
// `-count=1`, and this spec's `done:` predicate does. The same caveat applies
// to Test_LoadConfig_RealRegistries_LoadUnchanged, which reads the two shipped
// registries for the same reason.
//
// There is no way to declare a non-source dependency to the Go test cache, so
// this is documented rather than fixed.
func Test_ShippedTemplate_LoadsWithNewModes(t *testing.T) {
	src := filepath.Join("..", "..", "..", "templates", "speccraft", "agents.toml")
	body, err := os.ReadFile(src)
	if err != nil {
		t.Fatalf("cannot read the shipped template: %v", err)
	}
	root := writeRegistry(t, string(body))
	cfg, err := delegate.LoadConfig(root)
	if err != nil {
		t.Fatalf("the shipped template must load: %v", err)
	}

	var subagents, codexPlugins int
	for _, a := range cfg.Agents {
		// Every entry needs an explicit reference_read. The key is opt-out, so
		// an absent one still works — but a fresh init should not depend on
		// that default, and `nil` here is exactly what "absent" decodes to.
		if a.ReferenceRead == nil {
			t.Errorf("entry %q has no explicit reference_read", a.Name)
		}
		switch a.Mode {
		case "subagent":
			subagents++
			if a.Model != "opus" {
				t.Errorf("the subagent entry %q has model %q, want opus", a.Name, a.Model)
			}
			// It ships ENABLED: it is the one reviewer that needs no external
			// install, so a fresh repo can run a real round immediately.
			if a.Enabled != nil && !*a.Enabled {
				t.Errorf("the subagent entry %q ships disabled", a.Name)
			}
			// A subagent entry carrying a cmd is refused by the mode arm, so
			// shipping one would make the template fail its own LoadConfig.
			if len(a.Cmd) != 0 {
				t.Errorf("the subagent entry %q carries a cmd: %v", a.Name, a.Cmd)
			}
		case "codex-plugin":
			codexPlugins++
			// Shipped DISABLED: it needs the Codex plugin installed, and a
			// round that refuses a reviewer the user never asked for is noise
			// on every fresh init.
			if a.Enabled == nil || *a.Enabled {
				t.Errorf("the codex-plugin entry %q is not shipped disabled", a.Name)
			}
		}
	}
	if subagents != 1 {
		t.Errorf("want exactly 1 subagent entry, got %d", subagents)
	}
	if codexPlugins != 1 {
		t.Errorf("want exactly 1 codex-plugin entry, got %d", codexPlugins)
	}
}

// The default round the template configures must consult more than one vendor.
// A single-vendor default would make `single_vendor_approval: true` the norm
// rather than the exception the flag exists to surface (AC23a).
func Test_ShippedTemplate_DefaultRoundIsCrossVendor(t *testing.T) {
	src := filepath.Join("..", "..", "..", "templates", "speccraft", "agents.toml")
	body, err := os.ReadFile(src)
	if err != nil {
		t.Fatalf("cannot read the shipped template: %v", err)
	}
	root := writeRegistry(t, string(body))
	cfg, err := delegate.LoadConfig(root)
	if err != nil {
		t.Fatalf("the shipped template must load: %v", err)
	}

	// Resolved the same way commands/spec/review.lib.sh does it: by exact
	// basename match on argv[0], with the two constructed modes decided by the
	// mode itself. Kept deliberately small and duplicated rather than exported
	// — if the shell table and this one ever disagree, the disagreement is
	// about which vendor a BINARY belongs to, which is a fact, not a policy.
	vendorOf := func(a delegate.Agent) string {
		switch a.Mode {
		case "subagent":
			return "anthropic"
		case "codex-plugin":
			return "openai"
		}
		if len(a.Cmd) == 0 {
			return "unknown"
		}
		switch filepath.Base(a.Cmd[0]) {
		case "claude":
			return "anthropic"
		case "codex":
			return "openai"
		}
		return "unknown"
	}

	seen := map[string]bool{}
	for _, a := range cfg.Agents {
		if a.Enabled != nil && !*a.Enabled {
			continue
		}
		if v := vendorOf(a); v != "unknown" {
			seen[v] = true
		}
	}
	if len(seen) < 2 {
		t.Errorf("the default enabled set resolves to %d known vendor(s) (%v); "+
			"a fresh init should be able to run a cross-vendor round", len(seen), seen)
	}
}
