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
