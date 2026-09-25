package main

// Spec 0048 T17/T19 (AC7, AC16) — what build-repair mode must NOT change.
//
// Repair mode is a carve-out in the guard's most load-bearing rule, so the two
// boundaries matter as much as the feature: only Go gets it, and every non-build-
// failure branch of the red-check behaves exactly as before. Both are PINS — they
// pass on arrival by construction — and they exist so a later change cannot widen
// the carve-out silently.

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
	"github.com/dcstolf/speccraft/tools/internal/speccraft/runner"
)

// unsupportedProberForLang mirrors production for a non-Go language: the factory
// IS consulted and answers "no prober". The returned fake counts Probe() calls so a
// test can assert the probe never RAN.
//
// Note what is asserted and what is not. An earlier version of this test required
// the factory never to be CONSULTED, and that was wrong: proberForLang is shaped
// exactly like runnerForLang, where resolving and checking `ok` IS the mechanism.
// Gating on language before resolving would duplicate the "only Go" knowledge at
// the branch instead of keeping it in productionDeps. Consulting a pure factory is
// not a behaviour change; RUNNING a probe would be.
func unsupportedProberForLang(p *fakeProber, resolutions *int) func(string, speccraft.SpeccraftConfig) (BuildProber, bool) {
	return func(string, speccraft.SpeccraftConfig) (BuildProber, bool) {
		*resolutions++
		return p, false
	}
}

// countingProberForLang resolves successfully and counts Probe() calls.
func countingProberForLang(p *fakeProber) func(string, speccraft.SpeccraftConfig) (BuildProber, bool) {
	return func(string, speccraft.SpeccraftConfig) (BuildProber, bool) { return p, true }
}

// probeTempEntries counts leftover probe scratch dirs, so "the prober never ran"
// can be checked by evidence rather than only by a counter the test controls.
func probeTempEntries(t *testing.T) int {
	t.Helper()
	entries, err := os.ReadDir(os.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "speccraft-build-probe-") {
			n++
		}
	}
	return n
}

// AC7 — Python, JS and TS keep today's exact refusal, and the prober is never
// resolved for them. Repair mode is not silently extended to a language whose
// probe has not been designed.
//
// The expected text is matched with a regexp built from the literal prefix and
// suffix around the `%s`, never a byte-compare: res.Stderr varies per invocation,
// and a byte-compare would either be brittle or would have to restate the whole
// message and drift from it.
func Test_BuildProbe_UnsupportedLanguages_FallBackToBlocking(t *testing.T) {
	want := regexp.MustCompile(`(?s)^red-check: build/collection failed \(not a valid RED state\):\n.*\n\nFix the build error so the just-added test can run and fail\.$`)

	for _, tc := range []struct {
		name     string
		prodRel  string
		testRel  string
		lang     string
		jsConfig bool
	}{
		{"python", "pkg/foo.py", "pkg/test_foo.py", "python", false},
		{"js", "pkg/foo.js", "pkg/foo.test.js", "js", true},
		{"ts", "pkg/foo.ts", "pkg/foo.test.ts", "ts", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root, prod := redCheckRepo(t, tc.prodRel, tc.testRel, []string{"someTest"})
			before := probeTempEntries(t)
			stateBefore, _ := os.ReadFile(filepath.Join(root, ".speccraft", "state.json"))

			resolutions := 0
			prober := &fakeProber{clean: true}
			fake := &fakeLangRunner{result: runner.Result{
				Outcome: runner.OutcomeBuildFailed,
				Stderr:  "syntax error near line 3",
			}}
			d := deps{
				runnerForLang: fixedRunnerForLang(fake, true),
				proberForLang: unsupportedProberForLang(prober, &resolutions),
			}

			var err error
			if tc.jsConfig {
				err = jsTsDispatch(prod, root, jsCfg(), d)
			} else {
				err = goPythonProdGuard(prod, root, speccraft.SpeccraftConfig{}, d)
			}
			if err == nil {
				t.Fatal("a build failure in an unsupported language must still block")
			}
			if !want.MatchString(err.Error()) {
				t.Errorf("refusal text changed for %s:\n%v", tc.name, err)
			}
			if prober.calls != 0 {
				t.Errorf("no probe may RUN for %s, got %d Probe() calls", tc.name, prober.calls)
			}
			if after := probeTempEntries(t); after != before {
				t.Errorf("no probe scratch dir may be created for %s: %d -> %d", tc.name, before, after)
			}
			stateAfter, _ := os.ReadFile(filepath.Join(root, ".speccraft", "state.json"))
			if string(stateBefore) != string(stateAfter) {
				t.Errorf("state.json must be untouched for %s", tc.name)
			}
		})
	}
}

// Rust never reaches siblingRedCheck at all — rustDispatch has its own pre-edit
// gate — so its refusal text is pinned separately and the prober must never be
// constructed on that path either.
func Test_RustDispatch_BuildFailed_Unchanged_NoProber(t *testing.T) {
	prober := &fakeProber{clean: true}
	root := makeTestRepo(t, "0048-guard-wedge-red-candidate-clobber", "in-progress")
	dir := filepath.Join(root, "src")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "Cargo.toml"), []byte("[package]\nname=\"p\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	prod := filepath.Join(dir, "lib.rs")
	if err := os.WriteFile(prod, []byte("pub fn f() {}\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	d := deps{
		exec:          func(context.Context, string, []string, string) ([]byte, []byte, int, error) { return nil, nil, 0, nil },
		runnerFor:     func(speccraft.SpeccraftConfig) runner.Runner { return &recordingRunner{} },
		proberForLang: countingProberForLang(prober),
	}
	// The outcome itself is not the subject here; no probe RUNNING on the Rust
	// path is.
	_ = rustDispatch(decodeEnvelope(t, "Write", prod, "pub fn f() { g() }\n", root), prod, root, speccraft.SpeccraftConfig{}, d)
	if prober.calls != 0 {
		t.Errorf("Rust must never run a build probe, got %d Probe() calls", prober.calls)
	}
}

// AC16 — every branch of siblingRedCheck OTHER than OutcomeBuildFailed must be
// untouched, and none of them may resolve a prober. A regression here would mean
// repair mode had leaked into the ordinary path, which is the one thing the
// carve-out must not do.
func Test_SiblingRedCheck_OrdinaryPaths_Unchanged_ZeroProberInvocations(t *testing.T) {
	for _, tc := range []struct {
		name       string
		candidates []string
		runnerOK   bool
		nilFactory bool
		result     runner.Result
		runErr     error
		wantErr    string // substring; "" means allow
	}{
		{
			name:       "all passed blocks",
			candidates: []string{"TestNew"},
			runnerOK:   true,
			result:     runner.Result{Outcome: runner.OutcomeAllPassed},
			wantErr:    "no failing test observed among the tests added this session",
		},
		{
			name:       "failure inside just-added allows",
			candidates: []string{"TestNew"},
			runnerOK:   true,
			result: runner.Result{
				Outcome: runner.OutcomeAtLeastOneFailed,
				Records: []runner.TestRecord{{TestName: "TestNew", Status: "failed"}},
			},
			wantErr: "",
		},
		{
			name:       "failure outside just-added blocks",
			candidates: []string{"TestNew"},
			runnerOK:   true,
			result: runner.Result{
				Outcome: runner.OutcomeAtLeastOneFailed,
				Records: []runner.TestRecord{{TestName: "TestUnrelated", Status: "failed"}},
			},
			wantErr: "no failing test observed among the tests added this session",
		},
		{
			name:       "adapter error blocks",
			candidates: []string{"TestNew"},
			runnerOK:   true,
			runErr:     errors.New("boom"),
			wantErr:    "red-check runner",
		},
		{
			name:       "empty just-added blocks",
			candidates: nil,
			runnerOK:   true,
			result:     runner.Result{Outcome: runner.OutcomeAllPassed},
			wantErr:    "add a failing test",
		},
		{
			name:       "nil runner factory blocks",
			candidates: []string{"TestNew"},
			nilFactory: true,
			wantErr:    "no language runner factory wired",
		},
		{
			name:       "unresolved runner fails closed",
			candidates: []string{"TestNew"},
			runnerOK:   false,
			wantErr:    "no test runner available",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root, prod := redCheckRepo(t, "pkg/foo.go", "pkg/foo_test.go", tc.candidates)
			prober := &fakeProber{clean: true}
			d := deps{proberForLang: countingProberForLang(prober)}
			if !tc.nilFactory {
				fake := &fakeLangRunner{result: tc.result, err: tc.runErr}
				d.runnerForLang = fixedRunnerForLang(fake, tc.runnerOK)
			}

			err := siblingRedCheck(prod, root, speccraft.SpeccraftConfig{}, "go", d)
			if tc.wantErr == "" {
				if err != nil {
					t.Fatalf("expected allow, got: %v", err)
				}
			} else {
				if err == nil {
					t.Fatalf("expected a block containing %q, got nil", tc.wantErr)
				}
				if !strings.Contains(err.Error(), tc.wantErr) {
					t.Errorf("error = %v, want it to contain %q", err, tc.wantErr)
				}
			}
			if prober.calls != 0 {
				t.Errorf("an ordinary red-check branch must not run a probe, got %d", prober.calls)
			}
		})
	}
}

// AC16 — the prober is reachable from exactly ONE place. More than one call site
// means more than one policy for entering repair mode, which is how a carve-out
// widens without anyone deciding to widen it.
func Test_Prober_ReachedFromExactlyOneCallSite(t *testing.T) {
	entries, err := os.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}
	re := regexp.MustCompile(`d\.proberForLang\(`)
	total := 0
	var where []string
	for _, e := range entries {
		n := e.Name()
		if e.IsDir() || !strings.HasSuffix(n, ".go") || strings.HasSuffix(n, "_test.go") {
			continue
		}
		b, readErr := os.ReadFile(n)
		if readErr != nil {
			t.Fatal(readErr)
		}
		if c := len(re.FindAll(b, -1)); c > 0 {
			total += c
			where = append(where, n)
		}
	}
	if total != 1 {
		t.Errorf("want exactly one `d.proberForLang(` call site, found %d in %v", total, where)
	}
}
