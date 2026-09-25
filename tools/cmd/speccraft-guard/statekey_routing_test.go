package main

// Spec 0048 T10 (AC15) — the guard's half of the one-normalizer rule.
//
// The repo-wide "exactly one `func NormalizeStateKey(`" assertion lives in
// tools/internal/speccraft/statekey_normalizer_test.go, next to the definition.
// The per-function ROUTING scan is split per package instead of centralised, for
// two reasons: each package then pins its own call sites (so a new guard call
// site is caught by the guard's own suite), and the TDD red-check is
// package-scoped — a structural RED in another package cannot authorise an edit
// here, which is exactly the wrinkle that split this test out.
//
// Anchored per spec 0032: anchor on `func X(` and search WITHIN that body. A
// whole-file search passes as soon as ANY function mentions the token, so it
// would give a clean bill of health to a function deriving its own key.

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// guardFuncBody returns the source of `func <name>(` up to the next top-level func.
func guardFuncBody(t *testing.T, src, name string) string {
	t.Helper()
	anchor := "func " + name + "("
	i := strings.Index(src, anchor)
	if i < 0 {
		t.Fatalf("anchor %q not found — the scan would pass vacuously", anchor)
	}
	rest := src[i+len(anchor):]
	if j := strings.Index(rest, "\nfunc "); j >= 0 {
		return rest[:j]
	}
	return rest
}

// Both of the guard's state-key touchpoints must route through the single
// normalizer. captureRedCandidates WRITES the key; siblingRedCheck READS it. The
// defect was the two disagreeing, so requiring the call at both — even where the
// state layer would normalize anyway — keeps the intent explicit and survives a
// later refactor that starts using the raw path as a key.
func Test_GuardStateKeyConstruction_RoutesThroughNormalizer(t *testing.T) {
	b, err := os.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}
	src := string(b)

	bare := regexp.MustCompile(`filepath\.(Abs|Clean|EvalSymlinks)\(`)

	for _, fn := range []string{"captureRedCandidates", "siblingRedCheck"} {
		body := guardFuncBody(t, src, fn)
		if !strings.Contains(body, "NormalizeStateKey(") {
			t.Errorf("%s does not route its state key through speccraft.NormalizeStateKey", fn)
		}
		if loc := bare.FindString(body); loc != "" {
			t.Errorf("%s derives a path with a bare %s — use speccraft.NormalizeStateKey", fn, loc)
		}
	}
}
