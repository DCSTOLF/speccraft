package main

import (
	"bytes"
	"os"
	"regexp"
	"strings"
	"testing"
)

// Spec 0050 — every subcommand the top-level switch dispatches must appear in
// `usage()`.
//
// WHY THIS IS WORTH A TEST. `usage()` is the only self-description a built binary
// carries, so it is what you read to work out WHICH build you are holding — and it
// was misleading in exactly that role. Diagnosing eight red CI runs, the bats log's
// only direct evidence was a usage dump that stopped at spec 0044's subcommands,
// which looked like proof that a release binary had been installed over the freshly
// built one. It was not proof: when this test was written it found that `tasks-verify`,
// `review-commit` and `build-repair-log` were missing from usage at HEAD too, so a
// CURRENT binary produced the same truncated-looking dump. (The clobber was real, but
// it was established by a different observation — running the installer unpinned and
// watching `tasks-verify` disappear.)
//
// A self-description that silently lags the code invites precisely that wrong
// inference, and adding a `case` while forgetting the usage line also leaves the
// subcommand undiscoverable, with nothing else in the suite noticing.
//
// Bounded to the FIRST switch (the subcommand dispatch) on purpose. main.go has a
// second `switch args[0]` inside the field-level helpers whose cases are state
// FIELD names — `rust_test_baseline`, `rust_gate_fingerprint` — which are not
// subcommands and must not be required in usage. The bound is the `default:` arm
// that prints "unknown subcommand", which is by definition the end of the dispatch.
func Test_Usage_DocumentsEverySubcommand(t *testing.T) {
	src, err := os.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(string(src), "\n")

	start, end := -1, -1
	for i, ln := range lines {
		if start < 0 && strings.Contains(ln, "switch args[0] {") {
			start = i
			continue
		}
		if start >= 0 && strings.Contains(ln, "unknown subcommand") {
			end = i
			break
		}
	}
	if start < 0 || end < 0 {
		t.Fatalf("could not bound the subcommand switch (start=%d end=%d) — if main.go was "+
			"restructured, re-anchor this scan rather than deleting it", start, end)
	}

	caseRe := regexp.MustCompile(`^\s*case\s+(".*"):`)
	litRe := regexp.MustCompile(`"([^"]+)"`)
	var subs []string
	for _, ln := range lines[start:end] {
		m := caseRe.FindStringSubmatch(ln)
		if m == nil {
			continue
		}
		for _, lit := range litRe.FindAllStringSubmatch(m[1], -1) {
			subs = append(subs, lit[1])
		}
	}
	if len(subs) < 20 {
		t.Fatalf("found only %d subcommands (%v) — the scan is no longer matching the "+
			"dispatch and would pass vacuously", len(subs), subs)
	}

	var buf bytes.Buffer
	usage(&buf)
	text := buf.String()

	// `-v` is documented as `--version`; a one-character alias needs no line of its
	// own. Listed explicitly so the exemption is a visible decision, not a silent
	// substring coincidence.
	exempt := map[string]bool{"-v": true}

	var missing []string
	for _, s := range subs {
		if exempt[s] {
			continue
		}
		if !strings.Contains(text, "speccraft-state "+s) {
			missing = append(missing, s)
		}
	}
	if len(missing) > 0 {
		t.Errorf("these subcommands are dispatched but absent from usage(): %v\n"+
			"usage() is how a reader identifies which build they are holding; an omission "+
			"makes the binary misreport its own age.", missing)
	}
}
