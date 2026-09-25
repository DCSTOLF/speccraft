package main

// Spec 0048 T12 (AC1, AC2) — build-repair mode, driven through the real
// `processToolUse` seam.
//
// Defect A: `OutcomeBuildFailed` blocks the edit. That rule is right — a build
// failure is not an observable RED — but its blast radius is wrong. When the break
// is in PRODUCTION code, every later production edit in the package hits
// OutcomeBuildFailed, INCLUDING the edit that repairs the break. The tree is
// unbuildable and the guard forbids making it buildable. Spec 0047 stated an
// override budget of 0 and spent 5 on exactly this.
//
// The fix: on OutcomeBuildFailed, probe whether the PROPOSED edit would leave the
// module building, using a `go build -overlay` of the post-edit content. Clean →
// allow silently and end repair mode. Still broken → allow, but RECORD the edit in
// a bounded, append-only log first.
//
// These tests were FIRST written naming no new symbol, so they compiled against
// pre-0048 code and their REDs were runtime failures — a test referencing
// `deps{proberForLang: …}` before that field existed would have been a build
// failure, which per spec-0018 AC13 the guard cannot observe as a RED, and would
// have forced an override for the wiring step. Once the field landed they were
// updated to inject a FAKE prober, for two reasons: this package treats a nil
// factory as an error rather than a default (see siblingRedCheck's nil
// runnerForLang), so a nil prober must not silently mean "use production"; and a
// fake keeps these tests hermetic and fast instead of shelling out to a real
// `go build`. The real goBuildProber is exercised separately.

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
	"github.com/dcstolf/speccraft/tools/internal/speccraft/runner"
)

// goModuleFixture builds a hermetic module: .speccraft/ with an in-progress spec,
// a real go.mod, and pkg/ holding a production file plus a sibling test file with
// a registered red candidate (so the red-check reaches the adapter rather than
// stopping at the empty-just-added branch).
//
// `broken` decides whether the production file on disk currently compiles.
func goModuleFixture(t *testing.T, broken bool) (root, prodFile, testFile string) {
	t.Helper()
	root = makeTestRepo(t, "0048-guard-wedge-red-candidate-clobber", "in-progress")
	if err := os.WriteFile(filepath.Join(root, "go.mod"), []byte("module probe\n\ngo 1.22\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(root, "pkg")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	prodFile = filepath.Join(dir, "foo.go")
	body := "package pkg\n\nfunc Foo() int { return 1 }\n"
	if broken {
		// A forward reference to a function that does not exist — the exact shape
		// that wedged spec 0047.
		body = "package pkg\n\nfunc Foo() int { return missingHelper() }\n"
	}
	if err := os.WriteFile(prodFile, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	testFile = filepath.Join(dir, "foo_test.go")
	if err := os.WriteFile(testFile, []byte("package pkg\n\nfunc TestFoo(t *testing.T) {}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := speccraft.CaptureRedCandidates(root, testFile, nil, []string{"TestFoo"}); err != nil {
		t.Fatal(err)
	}
	return root, prodFile, testFile
}

// fakeProber reports a fixed verdict, so the repair-mode BRANCHING is tested
// without invoking the Go toolchain.
type fakeProber struct {
	clean  bool
	output string
	err    error
	calls  int
}

func (f *fakeProber) Probe(_ context.Context, _ buildProbeRequest) (buildProbeResult, error) {
	f.calls++
	if f.err != nil {
		return buildProbeResult{}, f.err
	}
	return buildProbeResult{Clean: f.clean, Output: f.output}, nil
}

func fixedProberForLang(p BuildProber, ok bool) func(string, speccraft.SpeccraftConfig) (BuildProber, bool) {
	return func(string, speccraft.SpeccraftConfig) (BuildProber, bool) { return p, ok }
}

// buildFailedRunner reports OutcomeBuildFailed, which is what a real adapter does
// against an unbuildable module.
func buildFailedRunner(stderr string) *fakeLangRunner {
	return &fakeLangRunner{result: runner.Result{
		Outcome: runner.OutcomeBuildFailed,
		Stderr:  stderr,
	}}
}

// AC1 — the repair edit itself. The module is broken; the proposed edit fixes it;
// the overlay therefore builds clean. The edit must be allowed SILENTLY: no log
// entry, no attestation. Repair mode is not entered for an edit that repairs.
func Test_BuildProbe_CleanOverlay_AllowsEditSilently(t *testing.T) {
	root, prodFile, _ := goModuleFixture(t, true)
	prober := &fakeProber{clean: true}
	d := deps{
		runnerForLang: fixedRunnerForLang(buildFailedRunner("undefined: missingHelper"), true),
		proberForLang: fixedProberForLang(prober, true),
	}

	// The proposed content repairs the module.
	fixed := "package pkg\n\nfunc Foo() int { return 1 }\n"
	in := decodeEnvelope(t, "Write", prodFile, fixed, root)

	if err := processToolUse(in, d); err != nil {
		t.Fatalf("an edit that REPAIRS the build must be allowed: %v", err)
	}
	br, err := speccraft.GetBuildRepair(root)
	if err != nil {
		t.Fatal(err)
	}
	if br.Attestation != nil {
		t.Errorf("a clean probe must not open repair mode: %+v", br.Attestation)
	}
	if len(br.Log) != 0 {
		t.Errorf("a clean probe must record nothing: %+v", br.Log)
	}
}

// AC1 — a clean probe ENDS repair mode, and the ordinary red-check is re-armed
// afterwards. Without the clear, a session would stay in repair mode forever and
// every later production edit would be admitted-and-logged rather than checked.
func Test_BuildProbe_CleanOverlay_ClearsAttestationAndReArmsRedCheck(t *testing.T) {
	root, prodFile, _ := goModuleFixture(t, true)

	// Repair mode already open from an earlier broken edit.
	if _, err := speccraft.RecordBuildRepair(root, prodFile, "undefined: missingHelper"); err != nil {
		t.Fatal(err)
	}
	if br, _ := speccraft.GetBuildRepair(root); br.Attestation == nil {
		t.Fatal("fixture should have opened the attestation")
	}

	d := deps{
		runnerForLang: fixedRunnerForLang(buildFailedRunner("undefined: missingHelper"), true),
		proberForLang: fixedProberForLang(&fakeProber{clean: true}, true),
	}
	fixed := "package pkg\n\nfunc Foo() int { return 1 }\n"
	if err := processToolUse(decodeEnvelope(t, "Write", prodFile, fixed, root), d); err != nil {
		t.Fatalf("the repairing edit must be allowed: %v", err)
	}

	br, _ := speccraft.GetBuildRepair(root)
	if br.Attestation != nil {
		t.Errorf("a clean probe must CLOSE repair mode: %+v", br.Attestation)
	}
	if len(br.Log) != 1 {
		t.Errorf("closing repair mode must not erase the log: got %d entries, want 1", len(br.Log))
	}

	// Re-armed: with the module now buildable on disk and the adapter reporting
	// all-passed, the ordinary red-check blocks again (no observed RED).
	if err := os.WriteFile(prodFile, []byte(fixed), 0o644); err != nil {
		t.Fatal(err)
	}
	d2 := deps{
		runnerForLang: fixedRunnerForLang(
			&fakeLangRunner{result: runner.Result{Outcome: runner.OutcomeAllPassed}}, true),
		proberForLang: fixedProberForLang(&fakeProber{clean: true}, true),
	}
	next := "package pkg\n\nfunc Foo() int { return 2 }\n"
	if err := processToolUse(decodeEnvelope(t, "Write", prodFile, next, root), d2); err == nil {
		t.Error("after repair mode ends the ordinary red-check must apply again")
	}
}

// AC2 — the edit that does NOT repair the build. It is still admitted (otherwise
// multi-step repairs are impossible), but recorded first: one entry, sequence 1, a
// normalized absolute path, a digest over the full error bytes, and a summary.
func Test_BuildProbe_StillBrokenOverlay_AllowsAndRecordsEntry(t *testing.T) {
	root, prodFile, _ := goModuleFixture(t, true)
	const buildErr = "pkg/foo.go:3:23: undefined: missingHelper"
	d := deps{
		runnerForLang: fixedRunnerForLang(buildFailedRunner(buildErr), true),
		proberForLang: fixedProberForLang(&fakeProber{clean: false, output: buildErr}, true),
	}

	// Still references the missing helper: a partial step of a multi-edit repair.
	stillBroken := "package pkg\n\nfunc Foo() int { return missingHelper() + 1 }\n"
	if err := processToolUse(decodeEnvelope(t, "Write", prodFile, stillBroken, root), d); err != nil {
		t.Fatalf("a mid-repair edit must be admitted, not blocked: %v", err)
	}

	br, err := speccraft.GetBuildRepair(root)
	if err != nil {
		t.Fatal(err)
	}
	if br.Attestation == nil {
		t.Fatal("a still-broken probe must OPEN repair mode")
	}
	if len(br.Log) != 1 {
		t.Fatalf("want exactly one log entry, got %d", len(br.Log))
	}
	e := br.Log[0]
	if e.Seq != 1 {
		t.Errorf("Seq = %d, want 1", e.Seq)
	}
	if want := speccraft.NormalizeStateKey(prodFile); e.Path != want {
		t.Errorf("Path = %q, want the normalized key %q", e.Path, want)
	}
	if e.Digest == "" {
		t.Error("Digest must be recorded")
	}
	if e.Summary == "" {
		t.Error("Summary must be recorded")
	}
}

// Correction C1 (plan §Corrections) — a production file that compiles while its
// SIBLING TEST file is broken.
//
// `go build ./...` does not compile _test.go files, so a probe using only `go
// build` would call this overlay CLEAN and allow the edit silently — reopening the
// hole the review spent three rounds closing, because the tree is still
// untestable. The probe therefore also runs `go test -run '^$'`, which compiles
// tests without running them. The edit is still admitted (repair must be
// possible), but through bounded, LOGGED repair mode rather than silently.
func Test_BuildProbe_ProductionCleanTestBroken_IsDetectedAndLogged(t *testing.T) {
	root, prodFile, testFile := goModuleFixture(t, false)

	// Break the TEST file only. Production compiles fine.
	if err := os.WriteFile(testFile,
		[]byte("package pkg\n\nfunc TestFoo(t *testing.T) { missingTestHelper() }\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	// The probe's `go test -run '^$'` half is what sees a broken _test.go, so the
	// fake reports still-broken with the test-compile error as its output.
	d := deps{
		runnerForLang: fixedRunnerForLang(buildFailedRunner("undefined: missingTestHelper"), true),
		proberForLang: fixedProberForLang(
			&fakeProber{clean: false, output: "pkg/foo_test.go:3:27: undefined: missingTestHelper"}, true),
	}
	next := "package pkg\n\nfunc Foo() int { return 3 }\n"
	if err := processToolUse(decodeEnvelope(t, "Write", prodFile, next, root), d); err != nil {
		t.Fatalf("the edit must be admitted through repair mode: %v", err)
	}

	br, err := speccraft.GetBuildRepair(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(br.Log) != 1 {
		t.Fatalf("a broken sibling TEST file must be detected and LOGGED, not silently allowed: got %d entries", len(br.Log))
	}
	if !strings.Contains(br.Log[0].Summary, "missingTestHelper") {
		t.Errorf("the logged summary should name the test-compile failure, got %q", br.Log[0].Summary)
	}
}
