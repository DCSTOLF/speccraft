package speccraft

// Spec 0048 T24 (AC18) — the policy files and the compiled bound cannot drift.
//
// This file is `package speccraft` (INTERNAL) while every other test in the
// directory is `package speccraft_test`. That is the whole reason it exists
// separately: `buildRepairMaxEdits` is unexported, deliberately, because the cap
// must be enforced inside the atomic record operation. Exporting it so an external
// test could read it would widen the API for a test's convenience; mixing an
// internal test file into the directory is legal Go and is the smaller change.
//
// The pin is BIDIRECTIONAL. Repair mode is a carve-out in the guard's most
// load-bearing rule, so the documented bound and the enforced bound must move
// together: raising the constant without amending guardrails.md fails here, and so
// does amending the prose to a different number.

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func repoRootFromInternal(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd() // .../tools/internal/speccraft
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Clean(filepath.Join(wd, "..", "..", ".."))
}

// AC18 — the compiled cap must appear INSIDE the carve-out sentence, not merely
// somewhere in the file.
//
// Anchoring on the sentence rather than on a bare numeral is the point:
// guardrails.md contains plenty of numbers, and a test that only asked "does 10
// appear anywhere?" would keep passing after the cap changed to 12, because some
// unrelated 10 would still be there. The regex therefore requires the number to sit
// in the same sentence as the words that describe the carve-out.
func Test_BuildRepairCap_AppearsInGuardrailCarveOutSentence(t *testing.T) {
	root := repoRootFromInternal(t)
	b, err := os.ReadFile(filepath.Join(root, ".speccraft", "guardrails.md"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(b)

	// Case-insensitive: the term legitimately starts a sentence ("Build-repair
	// mode is …"), and a case-sensitive check would fail on correct prose.
	if !strings.Contains(strings.ToLower(text), "build-repair") {
		t.Fatal("guardrails.md does not mention build-repair mode at all — a carve-out in the " +
			"TDD invariant must be documented where the invariant is stated")
	}

	// The sentence must carry the compiled bound. Built from the constant so the
	// expectation cannot be hand-edited out of step with the code.
	cap := fmt.Sprintf("%d", buildRepairMaxEdits)
	sentence := regexp.MustCompile(`(?i)[^.\n]*build-repair[^.]*\.`)
	found := false
	for _, s := range sentence.FindAllString(text, -1) {
		if strings.Contains(s, cap) {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("no sentence in guardrails.md mentions build-repair AND the compiled cap %s.\n"+
			"The documented bound and the enforced bound must move together: if the cap "+
			"changed, amend the guardrail; if the guardrail changed, this is the drift it exists to catch.", cap)
	}
}

// The converse direction. conventions.md told readers NOT to relax the
// build-failure-is-not-RED rule and called the proper fix a deferred follow-up.
// Spec 0048 IS that follow-up, so leaving the instruction in place would have the
// project's own conventions forbidding what the project just shipped — and the next
// person to hit the wedge would follow the stale advice and burn overrides.
func Test_Conventions_NoLongerForbidsTheRelaxationThisSpecShipped(t *testing.T) {
	root := repoRootFromInternal(t)
	b, err := os.ReadFile(filepath.Join(root, ".speccraft", "conventions.md"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(b)

	for _, stale := range []string{
		`Do not "fix" this by relaxing the build-failure-is-not-RED rule`,
		"is a deferred follow-up with its own ACs and latency profile",
	} {
		if strings.Contains(text, stale) {
			t.Errorf("conventions.md still says %q — spec 0048 implemented exactly that fix, so "+
				"the instruction now points readers away from the mechanism that would help them", stale)
		}
	}

	// And it must say what the situation IS now, not merely stop saying the old
	// thing: silence would leave the reader with no guidance at the moment they
	// hit a broken build.
	if !strings.Contains(strings.ToLower(text), "build-repair") {
		t.Error("conventions.md must describe build-repair mode where it used to forbid it")
	}
}
