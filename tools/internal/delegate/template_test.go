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

// Spec 0054 §6's same-vendor default, at the loader.
//
// REPLACES a test I wrote and should not have:
// Test_ShippedTemplate_DefaultRoundIsCrossVendor asserted that the default
// enabled set spans two vendors. That was my invented policy, not the spec's —
// §6 says the opposite, that "with only the `subagent` entry enabled, quorum
// can be met by a Claude reviewer on a Claude-authored spec", and names
// /codex:setup as the route OUT of that. Both round-8 reviewers caught it, and
// both also noted it was vacuous: the pre-existing `codex` and `claude-p`
// entries already supply two vendors, so it passed with the subagent entry
// deleted entirely.
//
// What the spec does require is testable and is what this asserts: the entry
// that needs NO external binary is enabled, so a fresh repo can run a round at
// all; and it is an anthropic reviewer, which is why the same-vendor comment
// has to exist.
func Test_ShippedTemplate_HasAnEnabledReviewerNeedingNoBinary(t *testing.T) {
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

	found := 0
	for _, a := range cfg.Agents {
		if a.Mode != "subagent" {
			continue
		}
		if a.Enabled != nil && !*a.Enabled {
			continue
		}
		// NOT `len(a.Cmd) != 0`: LoadConfig refuses a `cmd` on a subagent entry
		// (AC2), so that branch can never fire and the check was dead — round 9
		// caught it. The install-free property is already guaranteed by the
		// loader accepting this entry at all; what this test can still add is
		// that the entry is usable as a reviewer once dispatched.
		if a.Model != "opus" {
			t.Errorf("the install-free reviewer %q has model %q, want opus — "+
				"without it the round cannot report which model answered",
				a.Name, a.Model)
		}
		if a.ReferenceRead == nil || !*a.ReferenceRead {
			t.Errorf("the install-free reviewer %q does not read reference-tier "+
				"context, so it would be sent every memory file inline", a.Name)
		}
		found++
	}
	// And exactly one reviewer is enabled IN TOTAL. An enabled reviewer whose
	// binary is absent does not degrade gracefully: its dispatch fails,
	// responses_complete goes false, and no review.md is written even if
	// another reviewer approved. So a fresh repo ships only the one that needs
	// nothing installed (operator ruling, 2026-11-24).
	enabled := 0
	for _, a := range cfg.Agents {
		if a.Enabled == nil || *a.Enabled {
			enabled++
		}
	}
	if enabled != 1 {
		t.Errorf("want exactly 1 ENABLED reviewer in the shipped template, got %d: "+
			"any enabled entry whose binary is missing makes every round inert", enabled)
	}

	if found != 1 {
		t.Errorf("want exactly 1 ENABLED install-free reviewer, got %d: a fresh "+
			"repo with none has no reviewer that answers at all, and more than "+
			"one makes the same-vendor default worse without saying so", found)
	}
}
