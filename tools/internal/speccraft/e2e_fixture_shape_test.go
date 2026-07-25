package speccraft_test

// Spec 0033: repo-structural guards over the e2e shell fixtures.
//
// AC3 — recurrence guard for the spec-0031 class: a Write-tool payload must
// carry its content in `content`, never in `new_string`. Spec 0031's Go-only
// AC5 guard missed the shell fixtures, so rust_integration_cycle.sh kept
// mis-simulating a Write via new_string. This test scans every tests/e2e/*.sh
// and fails if any Write envelope carries new_string.
//
// AC4 (credit-free) — the [cons 1/3] decline leg prompt must imperatively pin
// the three terminal actions (write the consolidation-skip marker; do not move
// the directory; act without asking), so a credit-gated model cannot
// propose-and-wait. This meta-test makes that wording requirement deterministic
// without a model run; the credit-gated post-condition remains the behavioral
// backstop.

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// e2eDir walks up from the test's working directory to the nearest ancestor
// containing a tests/e2e directory, and returns that directory's path.
func e2eDir(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	start := dir
	for {
		cand := filepath.Join(dir, "tests", "e2e")
		if fi, err := os.Stat(cand); err == nil && fi.IsDir() {
			return cand
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	t.Fatalf("could not locate tests/e2e above %s", start)
	return ""
}

func Test_E2EFixtures_NoWritePayloadUsesNewString(t *testing.T) {
	dir := e2eDir(t)
	files, err := filepath.Glob(filepath.Join(dir, "*.sh"))
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatalf("no *.sh fixtures found under %s", dir)
	}
	tokRe := regexp.MustCompile(`"tool_name"`)
	writeRe := regexp.MustCompile(`"tool_name"\s*:\s*"Write"`)
	for _, f := range files {
		src := readFile(t, f)
		locs := tokRe.FindAllStringIndex(src, -1)
		for i, loc := range locs {
			end := len(src)
			if i+1 < len(locs) {
				end = locs[i+1][0]
			}
			seg := src[loc[0]:end] // one envelope's fields, up to the next tool_name
			if writeRe.MatchString(seg) && strings.Contains(seg, "new_string") {
				t.Errorf("%s: a Write tool payload carries new_string; a Write's content "+
					"must live in `content` (spec 0033 AC3 / the 0031 mis-simulation):\n%s",
					filepath.Base(f), strings.TrimSpace(seg))
			}
		}
	}
}

func Test_ConsolidateDeclineLeg_ImperativePrompt(t *testing.T) {
	dir := e2eDir(t)
	src := readFile(t, filepath.Join(dir, "spec_consolidate.sh"))

	// Isolate the [cons 1/3] decline run_claude prompt: it is the run_claude call
	// whose log argument is cons-01-decline.log.
	logIdx := strings.Index(src, "cons-01-decline.log")
	if logIdx < 0 {
		t.Fatal("cons-01-decline.log run_claude call not found in spec_consolidate.sh")
	}
	start := strings.LastIndex(src[:logIdx], "run_claude")
	if start < 0 {
		t.Fatal("run_claude for the [cons 1/3] decline leg not found")
	}
	prompt := src[start:logIdx]

	checks := []struct {
		name string
		re   *regexp.Regexp
	}{
		{"write the 0090 consolidation-skip marker", regexp.MustCompile(`consolidation-skip`)},
		{"do NOT move the directory", regexp.MustCompile(`(?i)not move`)},
		{"act WITHOUT asking for confirmation", regexp.MustCompile(`(?i)without (asking|confirmation)|do not ask|no confirmation`)},
	}
	for _, c := range checks {
		if !c.re.MatchString(prompt) {
			t.Errorf("[cons 1/3] decline prompt must imperatively instruct the model to: %s "+
				"(spec 0033 AC4). Prompt:\n%s", c.name, strings.TrimSpace(prompt))
		}
	}
}
