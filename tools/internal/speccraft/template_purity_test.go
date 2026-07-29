package speccraft_test

// Spec 0034 AC7 — the shipped template must stay stack-agnostic.
//
// templates/speccraft/conventions.md is COPIED verbatim into every host repo by
// /speccraft:init. Shipping Go-specific conventions (a `^func Test` enforce regex
// bound to **/*_test.go, fmt.Errorf, slog) into a Python/JS/Rust project violates
// the standing "template purity" guardrail. This test promotes that guardrail
// from advisory to an executable check: the shipped template must contain none of
// the language-specific tokens below.

import (
	"path/filepath"
	"strings"
	"testing"
)

func Test_ShippedTemplate_ConventionsIsStackAgnostic(t *testing.T) {
	root := findDocsRoot(t)
	tmpl := readFile(t, filepath.Join(root, "templates", "speccraft", "conventions.md"))

	// Language-specific idioms + any enforce: regex bound to a language file glob.
	forbidden := []string{
		"fmt.Errorf",
		"slog",
		"^func Test",           // Go test-name enforce regex
		"*_test.go",            // Go test-file glob (also catches scope="**/*_test.go")
		`scope="!cmd/"`,        // Go cmd/ layout enforce scope
		"PascalCase",           // Go/typed-language naming idiom
	}
	for _, tok := range forbidden {
		if strings.Contains(tmpl, tok) {
			t.Errorf("templates/speccraft/conventions.md contains language-specific token %q; "+
				"the shipped template must stay stack-agnostic (spec 0034 AC7 / guardrails §Template purity)", tok)
		}
	}
}

// Spec 0042 AC5 — the workspace index template must carry the structural marker
// + a ## Members header (a grep-able structural signal, not model prose) and
// stay stack-agnostic like every shipped template.
func Test_ShippedTemplate_WorkspaceIndex_HasMarkerMembersHeaderAndStackAgnostic(t *testing.T) {
	root := findDocsRoot(t)
	tmpl := readFile(t, filepath.Join(root, "templates", "speccraft", "index.workspace.md"))

	if !strings.Contains(tmpl, "<!-- speccraft:kind = workspace -->") {
		t.Errorf("index.workspace.md is missing the structural marker %q (spec 0042 AC5)",
			"<!-- speccraft:kind = workspace -->")
	}
	if !strings.Contains(tmpl, "## Members") {
		t.Errorf("index.workspace.md is missing the ## Members header (spec 0042 AC5)")
	}

	// Language idioms + repo-index (code-repo) leakage that a workspace-coordination
	// root must not carry.
	forbidden := []string{
		"fmt.Errorf",
		"slog",
		"^func Test",
		"*_test.go",
		"PascalCase",
		"internal/domain/",
		"internal/store/",
		"HTTP handlers",
	}
	for _, tok := range forbidden {
		if strings.Contains(tmpl, tok) {
			t.Errorf("index.workspace.md contains stack/repo-specific token %q; "+
				"the shipped workspace template must stay stack-agnostic (spec 0042 AC5 / guardrails §Template purity)", tok)
		}
	}
}
