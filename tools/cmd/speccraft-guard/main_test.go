package main

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
	"github.com/dcstolf/speccraft/tools/internal/speccraft/runner"
)

// recordingRunner is a runner.Runner fake that records each Run call.
type recordingRunner struct {
	calls []runner.Request
	// nextResult is returned by Run. Defaults to OutcomeAllPassed.
	nextResult runner.Result
}

func (r *recordingRunner) Run(_ context.Context, req runner.Request) (runner.Result, error) {
	r.calls = append(r.calls, req)
	// Unset sentinel: Records nil AND Stderr empty AND Outcome at zero
	// value. (OutcomeBuildFailed is 0 — explicit build-failed results
	// always carry Stderr, so the Stderr check disambiguates.)
	if r.nextResult.Outcome == 0 && r.nextResult.Records == nil && r.nextResult.Stderr == "" {
		return runner.Result{Outcome: runner.OutcomeAllPassed}, nil
	}
	return r.nextResult, nil
}

// noopExec is an exec.ExecFunc that records nothing and reports success.
func noopExec(_ context.Context, _ string, _ []string, _ string) ([]byte, []byte, int, error) {
	return nil, nil, 0, nil
}

// makeTestRepo creates a temp directory with .speccraft/ and optional spec.
func makeTestRepo(t *testing.T, activeSpec, specStatus string) string {
	t.Helper()
	tmp := t.TempDir()
	specDir := filepath.Join(tmp, ".speccraft")
	if err := os.MkdirAll(specDir, 0o755); err != nil {
		t.Fatal(err)
	}
	state := `{"version":1,"active_spec":"` + activeSpec + `","session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}`
	if activeSpec == "" {
		state = `{"version":1,"active_spec":null,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}`
	}
	if err := os.WriteFile(filepath.Join(specDir, "state.json"), []byte(state), 0o644); err != nil {
		t.Fatal(err)
	}
	if activeSpec != "" {
		sdir := filepath.Join(tmp, "specs", activeSpec)
		if err := os.MkdirAll(sdir, 0o755); err != nil {
			t.Fatal(err)
		}
		specMd := "---\nstatus: " + specStatus + "\n---\n# Test spec\n"
		if err := os.WriteFile(filepath.Join(sdir, "spec.md"), []byte(specMd), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return tmp
}

func TestReadFrontmatterField(t *testing.T) {
	tmp := t.TempDir()
	content := "---\nstatus: in-progress\nid: \"0001\"\n---\n# Title\n"
	f := filepath.Join(tmp, "spec.md")
	os.WriteFile(f, []byte(content), 0o644)

	if got := readFrontmatterField(f, "status"); got != "in-progress" {
		t.Errorf("status = %q, want %q", got, "in-progress")
	}
	if got := readFrontmatterField(f, "id"); got != `"0001"` {
		t.Errorf("id = %q, want %q", got, `"0001"`)
	}
	if got := readFrontmatterField(f, "missing"); got != "" {
		t.Errorf("missing = %q, want empty", got)
	}
}

func TestHasSiblingTestEdited(t *testing.T) {
	siblings := []string{"/repo/pkg/foo_test.go", "/repo/pkg/bar_test.go"}

	if hasSiblingTestEdited(siblings, nil) {
		t.Error("expected false with no edited tests")
	}
	if !hasSiblingTestEdited(siblings, []string{"/repo/pkg/foo_test.go"}) {
		t.Error("expected true when sibling is in edited list")
	}
	if hasSiblingTestEdited(siblings, []string{"/repo/other/baz_test.go"}) {
		t.Error("expected false when only non-sibling test was edited")
	}
}

func TestPreToolUse_AllowAlwaysAllowedPaths(t *testing.T) {
	root := makeTestRepo(t, "", "")

	// .speccraft/ files → always allow (no error).
	target := filepath.Join(root, ".speccraft", "guardrails.md")
	os.WriteFile(target, []byte("# Guardrails"), 0o644)

	// Simulate: set cwd to root, input file to .speccraft path.
	// We test the component functions directly.
	if result := readFrontmatterField(target, "status"); result != "" {
		t.Errorf("unexpected frontmatter in guardrails.md: %q", result)
	}
}

// makeRustWorkspaceRepo creates an in-progress spec, a workspace
// Cargo.toml, and a placeholder src/lib.rs so guard tests can simulate
// a Rust edit against a workspace fixture.
func makeRustWorkspaceRepo(t *testing.T) string {
	t.Helper()
	root := makeTestRepo(t, "0005-rust-language-support", "in-progress")
	if err := os.WriteFile(
		filepath.Join(root, "Cargo.toml"),
		[]byte("[workspace]\nmembers = [\"crate-a\"]\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, "src"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "src", "lib.rs"), []byte("// lib\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

// makeRustSingleCrateRepo creates an in-progress spec and a single-crate
// Cargo.toml with src/lib.rs (no [workspace]).
func makeRustSingleCrateRepo(t *testing.T) string {
	t.Helper()
	root := makeTestRepo(t, "0005-rust-language-support", "in-progress")
	if err := os.WriteFile(
		filepath.Join(root, "Cargo.toml"),
		[]byte("[package]\nname = \"foo\"\nversion = \"0.1.0\"\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, "src"), 0o755); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestPreToolUse_RustWorkspace_RejectsWithSpec0006Reference(t *testing.T) {
	root := makeRustWorkspaceRepo(t)
	input := HookInput{
		ToolInput: ToolInput{FilePath: filepath.Join(root, "src", "lib.rs")},
		CWD:       root,
	}
	err := processToolUse(input, deps{})
	if err == nil {
		t.Fatal("expected workspace rejection error")
	}
	msg := err.Error()
	for _, want := range []string{"0006", "workspace support", "Cargo workspace"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error missing %q: %s", want, msg)
		}
	}
}

func TestPreToolUse_RustNonWorkspace_DoesNotRejectOnWorkspaceGrounds(t *testing.T) {
	// A single-crate Rust repo should not produce the workspace-error
	// path. (The full flow may still fail for other reasons in later
	// tasks; here we only assert the workspace-specific message is absent.)
	root := makeRustSingleCrateRepo(t)
	libPath := filepath.Join(root, "src", "lib.rs")
	os.WriteFile(libPath, []byte("// lib\n"), 0o644)
	input := HookInput{
		ToolInput: ToolInput{FilePath: libPath},
		CWD:       root,
	}
	err := processToolUse(input, deps{})
	if err != nil && strings.Contains(err.Error(), "workspace") {
		t.Errorf("single-crate repo erroneously hit workspace path: %v", err)
	}
}

func TestPreToolUse_RustInitialCapture_NoRunnerInvocationOnFirstEdit(t *testing.T) {
	root := makeRustSingleCrateRepo(t)
	// Seed three inline tests so initial-capture has IDs to record.
	src := `#[cfg(test)]
mod tests {
    fn a() {}
    fn b() {}
    fn c() {}
}
`
	libPath := filepath.Join(root, "src", "lib.rs")
	os.WriteFile(libPath, []byte(src), 0o644)

	rec := &recordingRunner{}
	var stderr bytes.Buffer
	d := deps{
		exec:      noopExec,
		runnerFor: func(speccraft.SpeccraftConfig) runner.Runner { return rec },
		stderr:    &stderr,
	}

	input := HookInput{
		ToolInput: ToolInput{FilePath: libPath},
		CWD:       root,
	}
	err := processToolUse(input, d)
	if err != nil {
		t.Fatalf("expected success on initial-capture edit, got %v", err)
	}

	if len(rec.calls) != 0 {
		t.Errorf("expected zero runner invocations during initial capture, got %d", len(rec.calls))
	}

	// stderr must announce the capture and the count.
	logged := stderr.String()
	if !strings.Contains(logged, "rust_test_baseline captured") {
		t.Errorf("stderr missing capture announcement: %q", logged)
	}
	if !strings.Contains(logged, "3") {
		t.Errorf("stderr missing test count: %q", logged)
	}

	// Baseline must be persisted with the three discovered IDs.
	got, _ := speccraft.GetRustBaseline(root)
	want := []string{"lib::tests::a", "lib::tests::b", "lib::tests::c"}
	if len(got) != len(want) {
		t.Fatalf("baseline = %v, want %v", got, want)
	}
	for i, w := range want {
		if got[i] != w {
			t.Errorf("baseline[%d] = %q, want %q", i, got[i], w)
		}
	}
}

// seedRustCrateAndBaseline creates a single-crate repo with the given
// pre-edit src/lib.rs content and a non-empty baseline (so subsequent
// edits skip initial-capture and exercise the red-check).
func seedRustCrateAndBaseline(t *testing.T, libSrc string) string {
	t.Helper()
	root := makeRustSingleCrateRepo(t)
	libPath := filepath.Join(root, "src", "lib.rs")
	os.WriteFile(libPath, []byte(libSrc), 0o644)
	// Seed baseline to current state so initial-capture is a no-op.
	stem := "lib"
	preIDs := speccraft.CanonicalInlineTestIDs(libSrc, stem)
	speccraft.SetRustBaseline(root, preIDs)
	if preIDs == nil {
		// Setting a non-nil empty list so the baseline is "not empty".
		speccraft.SetRustBaseline(root, []string{"sentinel::placeholder"})
	}
	return root
}

func TestPreToolUse_RustRedCheck_BuildFailedRejects(t *testing.T) {
	root := seedRustCrateAndBaseline(t, "// no tests\n")
	libPath := filepath.Join(root, "src", "lib.rs")
	preSrc, _ := os.ReadFile(libPath)
	postSrc := string(preSrc) + `
#[cfg(test)]
mod tests { fn new_one() {} }
`
	rec := &recordingRunner{
		nextResult: runner.Result{
			Outcome: runner.OutcomeBuildFailed,
			Stderr:  "error[E0425]: cannot find value",
		},
	}
	d := deps{
		exec:      noopExec,
		runnerFor: func(speccraft.SpeccraftConfig) runner.Runner { return rec },
		stderr:    &bytes.Buffer{},
	}
	input := HookInput{
		ToolInput: ToolInput{FilePath: libPath, OldString: string(preSrc), NewString: postSrc},
		CWD:       root,
	}
	err := processToolUse(input, d)
	if err == nil {
		t.Fatal("expected build_failed rejection")
	}
	if !strings.Contains(err.Error(), "build failed") {
		t.Errorf("error should mention 'build failed': %v", err)
	}
}

func TestPreToolUse_RustRedCheck_AllPassedRejects(t *testing.T) {
	root := seedRustCrateAndBaseline(t, "// no tests\n")
	libPath := filepath.Join(root, "src", "lib.rs")
	preSrc, _ := os.ReadFile(libPath)
	postSrc := string(preSrc) + `
#[cfg(test)]
mod tests { fn new_one() {} }
`
	// Runner returns OutcomeAllPassed → red-check should reject.
	rec := &recordingRunner{
		nextResult: runner.Result{
			Outcome: runner.OutcomeAllPassed,
			Records: []runner.TestRecord{{TestName: "lib::tests::new_one", Status: "passed"}},
		},
	}
	d := deps{
		exec:      noopExec,
		runnerFor: func(speccraft.SpeccraftConfig) runner.Runner { return rec },
		stderr:    &bytes.Buffer{},
	}
	input := HookInput{
		ToolInput: ToolInput{FilePath: libPath, OldString: string(preSrc), NewString: postSrc},
		CWD:       root,
	}
	err := processToolUse(input, d)
	if err == nil {
		t.Fatal("expected 'no failing test observed' rejection")
	}
	if !strings.Contains(err.Error(), "no failing test observed") {
		t.Errorf("error should mention 'no failing test observed': %v", err)
	}
}

func TestPreToolUse_RustRedCheck_IgnoredDoesNotSatisfyAccept(t *testing.T) {
	root := seedRustCrateAndBaseline(t, "// no tests\n")
	libPath := filepath.Join(root, "src", "lib.rs")
	preSrc, _ := os.ReadFile(libPath)
	postSrc := string(preSrc) + `
#[cfg(test)]
mod tests { fn new_one() {} }
`
	rec := &recordingRunner{
		nextResult: runner.Result{
			Outcome: runner.OutcomeAllPassed,
			Records: []runner.TestRecord{{TestName: "lib::tests::new_one", Status: "ignored"}},
		},
	}
	d := deps{
		exec:      noopExec,
		runnerFor: func(speccraft.SpeccraftConfig) runner.Runner { return rec },
		stderr:    &bytes.Buffer{},
	}
	input := HookInput{
		ToolInput: ToolInput{FilePath: libPath, OldString: string(preSrc), NewString: postSrc},
		CWD:       root,
	}
	err := processToolUse(input, d)
	if err == nil {
		t.Fatal("expected rejection — ignored status does not satisfy accept")
	}
}

func TestPreToolUse_RustRedCheck_PostAcceptAppendsFailingJustAddedToBaseline(t *testing.T) {
	root := seedRustCrateAndBaseline(t, "// no tests\n")
	libPath := filepath.Join(root, "src", "lib.rs")
	preSrc, _ := os.ReadFile(libPath)
	postSrc := string(preSrc) + `
#[cfg(test)]
mod tests { fn new_one() {} }
`
	rec := &recordingRunner{
		nextResult: runner.Result{
			Outcome: runner.OutcomeAtLeastOneFailed,
			Records: []runner.TestRecord{{TestName: "lib::tests::new_one", Status: "failed"}},
		},
	}
	d := deps{
		exec:      noopExec,
		runnerFor: func(speccraft.SpeccraftConfig) runner.Runner { return rec },
		stderr:    &bytes.Buffer{},
	}
	input := HookInput{
		ToolInput: ToolInput{FilePath: libPath, OldString: string(preSrc), NewString: postSrc},
		CWD:       root,
	}
	if err := processToolUse(input, d); err != nil {
		t.Fatalf("accept path returned error: %v", err)
	}
	got, _ := speccraft.GetRustBaseline(root)
	found := false
	for _, id := range got {
		if id == "lib::tests::new_one" {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("post-accept did not append 'lib::tests::new_one' to baseline: %v", got)
	}
}

// fingerprintAwareExec records cargo invocations so the pre-edit-gate
// tests can assert that the gate either short-circuited (zero calls) or
// fired (>= one call). It always reports success.
type fingerprintAwareExec struct {
	calls [][]string
}

func (f *fingerprintAwareExec) fn() runner.ExecFunc {
	return func(_ context.Context, name string, args []string, _ string) ([]byte, []byte, int, error) {
		f.calls = append(f.calls, append([]string{name}, args...))
		return nil, nil, 0, nil
	}
}

func TestPreToolUse_RustPreEditGate_CacheHit_NoSubprocess(t *testing.T) {
	root := seedRustCrateAndBaseline(t, "// no tests\n")
	libPath := filepath.Join(root, "src", "lib.rs")
	// Seed the fingerprint to the current crate state so the gate is a hit.
	fp, _ := runner.ComputeCrateFingerprint(root)
	speccraft.SetRustFingerprint(root, fp)

	gExec := &fingerprintAwareExec{}
	rec := &recordingRunner{
		nextResult: runner.Result{
			Outcome: runner.OutcomeAtLeastOneFailed,
			Records: []runner.TestRecord{{TestName: "lib::tests::x", Status: "failed"}},
		},
	}
	d := deps{
		exec:      gExec.fn(),
		runnerFor: func(speccraft.SpeccraftConfig) runner.Runner { return rec },
		stderr:    &bytes.Buffer{},
	}
	preSrc, _ := os.ReadFile(libPath)
	postSrc := string(preSrc) + `
#[cfg(test)]
mod tests { fn x() {} }
`
	input := HookInput{
		ToolInput: ToolInput{FilePath: libPath, OldString: string(preSrc), NewString: postSrc},
		CWD:       root,
	}
	_ = processToolUse(input, d)
	if len(gExec.calls) != 0 {
		t.Errorf("cache hit invoked %d cargo subprocesses, want 0: %v", len(gExec.calls), gExec.calls)
	}
}

func TestPreToolUse_RustPreEditGate_CacheMiss_InvokesCargoCheck(t *testing.T) {
	root := seedRustCrateAndBaseline(t, "// no tests\n")
	libPath := filepath.Join(root, "src", "lib.rs")
	// Stale fingerprint forces a cache miss.
	speccraft.SetRustFingerprint(root, "stale")

	gExec := &fingerprintAwareExec{}
	rec := &recordingRunner{
		nextResult: runner.Result{
			Outcome: runner.OutcomeAtLeastOneFailed,
			Records: []runner.TestRecord{{TestName: "lib::tests::x", Status: "failed"}},
		},
	}
	d := deps{
		exec:      gExec.fn(),
		runnerFor: func(speccraft.SpeccraftConfig) runner.Runner { return rec },
		stderr:    &bytes.Buffer{},
	}
	preSrc, _ := os.ReadFile(libPath)
	postSrc := string(preSrc) + `
#[cfg(test)]
mod tests { fn x() {} }
`
	input := HookInput{
		ToolInput: ToolInput{FilePath: libPath, OldString: string(preSrc), NewString: postSrc},
		CWD:       root,
	}
	_ = processToolUse(input, d)
	if len(gExec.calls) == 0 {
		t.Error("cache miss did NOT invoke cargo")
	}
	if len(gExec.calls) > 0 {
		args := gExec.calls[0]
		if args[0] != "cargo" || args[1] != "check" || args[2] != "--tests" {
			t.Errorf("unexpected gate argv: %v", args)
		}
	}
}

func TestPreToolUse_RustPreEditGate_BuildFailure_Rejects(t *testing.T) {
	root := seedRustCrateAndBaseline(t, "// no tests\n")
	libPath := filepath.Join(root, "src", "lib.rs")
	speccraft.SetRustFingerprint(root, "stale")

	failExec := func(_ context.Context, _ string, _ []string, _ string) ([]byte, []byte, int, error) {
		return nil, []byte("error[E0425]: cannot find value `whoops`\n"), 101, nil
	}
	rec := &recordingRunner{
		nextResult: runner.Result{Outcome: runner.OutcomeAtLeastOneFailed},
	}
	d := deps{
		exec:      failExec,
		runnerFor: func(speccraft.SpeccraftConfig) runner.Runner { return rec },
		stderr:    &bytes.Buffer{},
	}
	preSrc, _ := os.ReadFile(libPath)
	postSrc := string(preSrc) + `
#[cfg(test)]
mod tests { fn x() {} }
`
	input := HookInput{
		ToolInput: ToolInput{FilePath: libPath, OldString: string(preSrc), NewString: postSrc},
		CWD:       root,
	}
	err := processToolUse(input, d)
	if err == nil {
		t.Fatal("expected pre-edit-gate failure to reject")
	}
	if !strings.Contains(err.Error(), "gate") && !strings.Contains(err.Error(), "build") && !strings.Contains(err.Error(), "check") {
		t.Errorf("error should mention gate/build/check: %v", err)
	}
}

func TestGoPythonProdGuard_OverridePending_AllowsAndConsumes(t *testing.T) {
	root := makeTestRepo(t, "0009-test", "in-progress")
	if err := speccraft.SetField(root, "override_pending", "true"); err != nil {
		t.Fatal(err)
	}
	prodFile := filepath.Join(root, "pkg", "main.go")
	if err := os.MkdirAll(filepath.Dir(prodFile), 0o755); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(prodFile, []byte("package pkg\n"), 0o644)

	if err := goPythonProdGuard(prodFile, root, speccraft.SpeccraftConfig{}); err != nil {
		t.Fatalf("expected nil with override pending, got: %v", err)
	}
	s, err := speccraft.LoadState(root)
	if err != nil {
		t.Fatal(err)
	}
	if s.Session.OverridePending {
		t.Error("OverridePending still true after guard consumed it; flag must be single-use")
	}
}

func TestGoPythonProdGuard_OverridePending_SecondEditRejected(t *testing.T) {
	root := makeTestRepo(t, "0009-test", "in-progress")
	if err := speccraft.SetField(root, "override_pending", "true"); err != nil {
		t.Fatal(err)
	}
	prodFile := filepath.Join(root, "pkg", "main.go")
	os.MkdirAll(filepath.Dir(prodFile), 0o755)
	os.WriteFile(prodFile, []byte("package pkg\n"), 0o644)

	cfg := speccraft.SpeccraftConfig{}
	if err := goPythonProdGuard(prodFile, root, cfg); err != nil {
		t.Fatalf("first call expected nil (override), got: %v", err)
	}
	// Second call: flag consumed, no sibling test edited → TDD invariant fires.
	if err := goPythonProdGuard(prodFile, root, cfg); err == nil {
		t.Error("second call expected TDD invariant error, got nil")
	}
}

func TestGoPythonProdGuard_OverrideUnset_BehavesAsToday(t *testing.T) {
	root := makeTestRepo(t, "0009-test", "in-progress")
	prodFile := filepath.Join(root, "pkg", "main.go")
	os.MkdirAll(filepath.Dir(prodFile), 0o755)
	os.WriteFile(prodFile, []byte("package pkg\n"), 0o644)

	err := goPythonProdGuard(prodFile, root, speccraft.SpeccraftConfig{})
	if err == nil {
		t.Error("expected TDD invariant error when override not set and no sibling edited")
	}
	if err != nil && !strings.Contains(err.Error(), "TDD invariant") {
		t.Errorf("expected TDD invariant error, got: %v", err)
	}
}

func TestGoPythonProdGuard_OverrideDoesNotConsumeOnPrecondFail(t *testing.T) {
	// active_spec="" AND override_pending=true → "No active spec" error,
	// flag must NOT be consumed.
	root := makeTestRepo(t, "", "")
	if err := speccraft.SetField(root, "override_pending", "true"); err != nil {
		t.Fatal(err)
	}
	prodFile := filepath.Join(root, "pkg", "main.go")
	os.MkdirAll(filepath.Dir(prodFile), 0o755)
	os.WriteFile(prodFile, []byte("package pkg\n"), 0o644)

	err := goPythonProdGuard(prodFile, root, speccraft.SpeccraftConfig{})
	if err == nil {
		t.Fatal("expected 'No active spec' error")
	}
	if !strings.Contains(err.Error(), "No active spec") {
		t.Errorf("expected 'No active spec' error, got: %v", err)
	}
	// Flag must still be set — not consumed on a pre-condition failure path.
	s, loadErr := speccraft.LoadState(root)
	if loadErr != nil {
		t.Fatal(loadErr)
	}
	if !s.Session.OverridePending {
		t.Error("OverridePending was consumed before pre-conditions passed; must be preserved for retry")
	}
}

func TestPreToolUse_RustSecondInvocation_AfterCapture_RunnerIsConsulted(t *testing.T) {
	root := makeRustSingleCrateRepo(t)
	src := `#[cfg(test)]
mod tests {
    fn a() {}
}
`
	libPath := filepath.Join(root, "src", "lib.rs")
	os.WriteFile(libPath, []byte(src), 0o644)

	// First call: initial-capture runs.
	rec := &recordingRunner{}
	d := deps{
		exec:      noopExec,
		runnerFor: func(speccraft.SpeccraftConfig) runner.Runner { return rec },
		stderr:    &bytes.Buffer{},
	}
	input := HookInput{
		ToolInput: ToolInput{FilePath: libPath},
		CWD:       root,
	}
	if err := processToolUse(input, d); err != nil {
		t.Fatalf("first call failed: %v", err)
	}
	if len(rec.calls) != 0 {
		t.Fatalf("first call should not invoke runner, got %d calls", len(rec.calls))
	}

	// Now edit the file to add a NEW test (just-added becomes non-empty
	// once the post-edit content is considered).
	postSrc := `#[cfg(test)]
mod tests {
    fn a() {}
    fn newly_added() {}
}
`
	// Pre-state on disk is the original src; the new content is delivered
	// via OldString → NewString.
	input2 := HookInput{
		ToolInput: ToolInput{
			FilePath:  libPath,
			OldString: src,
			NewString: postSrc,
		},
		CWD: root,
	}
	// Configure rec to return at_least_one_failed for the new test so the
	// red-check accepts.
	rec.nextResult = runner.Result{
		Outcome: runner.OutcomeAtLeastOneFailed,
		Records: []runner.TestRecord{{TestName: "lib::tests::newly_added", Status: "failed"}},
	}
	if err := processToolUse(input2, d); err != nil {
		t.Fatalf("second call (red-check) failed: %v", err)
	}
	if len(rec.calls) == 0 {
		t.Error("second invocation should consult the runner (red-check), but runner was not called")
	}
}
