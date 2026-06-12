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

	if err := goPythonProdGuard(prodFile, root, speccraft.SpeccraftConfig{}, deps{}); err != nil {
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
	if err := goPythonProdGuard(prodFile, root, cfg, deps{}); err != nil {
		t.Fatalf("first call expected nil (override), got: %v", err)
	}
	// Second call: flag consumed, no sibling test edited → TDD invariant fires.
	if err := goPythonProdGuard(prodFile, root, cfg, deps{}); err == nil {
		t.Error("second call expected TDD invariant error, got nil")
	}
}

func TestGoPythonProdGuard_OverrideUnset_BehavesAsToday(t *testing.T) {
	root := makeTestRepo(t, "0009-test", "in-progress")
	prodFile := filepath.Join(root, "pkg", "main.go")
	os.MkdirAll(filepath.Dir(prodFile), 0o755)
	os.WriteFile(prodFile, []byte("package pkg\n"), 0o644)

	err := goPythonProdGuard(prodFile, root, speccraft.SpeccraftConfig{}, deps{})
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

	err := goPythonProdGuard(prodFile, root, speccraft.SpeccraftConfig{}, deps{})
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

// --- Step 13: prodGuardPrologue tests ---

func TestProdGuardPrologue_ReturnsActiveSpecError(t *testing.T) {
	root := makeTestRepo(t, "", "")
	prodFile := filepath.Join(root, "pkg", "main.go")
	os.MkdirAll(filepath.Dir(prodFile), 0o755)
	os.WriteFile(prodFile, []byte("package pkg\n"), 0o644)

	dec, err := prodGuardPrologue(prodFile, root)
	if dec != prologueBlock {
		t.Errorf("expected prologueBlock, got %v", dec)
	}
	if err == nil || !strings.Contains(err.Error(), "No active spec") {
		t.Errorf("expected 'No active spec' error, got: %v", err)
	}
}

func TestProdGuardPrologue_ReturnsStatusError(t *testing.T) {
	root := makeTestRepo(t, "0010-test", "draft")
	prodFile := filepath.Join(root, "pkg", "main.go")
	os.MkdirAll(filepath.Dir(prodFile), 0o755)
	os.WriteFile(prodFile, []byte("package pkg\n"), 0o644)

	dec, err := prodGuardPrologue(prodFile, root)
	if dec != prologueBlock {
		t.Errorf("expected prologueBlock, got %v", dec)
	}
	if err == nil || !strings.Contains(err.Error(), "in status") {
		t.Errorf("expected 'in status' error, got: %v", err)
	}
}

func TestProdGuardPrologue_ConsumesOverrideReturnsAllow(t *testing.T) {
	root := makeTestRepo(t, "0010-test", "in-progress")
	if err := speccraft.SetField(root, "override_pending", "true"); err != nil {
		t.Fatal(err)
	}
	prodFile := filepath.Join(root, "pkg", "main.go")
	os.MkdirAll(filepath.Dir(prodFile), 0o755)
	os.WriteFile(prodFile, []byte("package pkg\n"), 0o644)

	dec, err := prodGuardPrologue(prodFile, root)
	if dec != prologueAllow {
		t.Errorf("expected prologueAllow, got %v", dec)
	}
	if err != nil {
		t.Errorf("expected nil error, got: %v", err)
	}
	s, _ := speccraft.LoadState(root)
	if s.Session.OverridePending {
		t.Error("OverridePending must be consumed")
	}
}

func TestProdGuardPrologue_PassThroughReturnsContinue(t *testing.T) {
	root := makeTestRepo(t, "0010-test", "in-progress")
	prodFile := filepath.Join(root, "pkg", "main.go")
	os.MkdirAll(filepath.Dir(prodFile), 0o755)
	os.WriteFile(prodFile, []byte("package pkg\n"), 0o644)

	dec, err := prodGuardPrologue(prodFile, root)
	if dec != prologueContinue {
		t.Errorf("expected prologueContinue, got %v", dec)
	}
	if err != nil {
		t.Errorf("expected nil error, got: %v", err)
	}
}

// --- Step 15: jsTsDispatch tests ---

func TestJsTsDispatch_ReusesPrologueGates(t *testing.T) {
	root := makeTestRepo(t, "", "")
	srcDir := filepath.Join(root, "src")
	os.MkdirAll(srcDir, 0o755)
	prodFile := filepath.Join(srcDir, "foo.ts")
	os.WriteFile(prodFile, []byte("export const x = 1;\n"), 0o644)

	input := HookInput{
		ToolInput: ToolInput{FilePath: prodFile},
		CWD:       root,
	}
	err := processToolUse(input, deps{})
	if err == nil {
		t.Fatal("expected 'No active spec' error for JS/TS file")
	}
	if !strings.Contains(err.Error(), "No active spec") {
		t.Errorf("expected 'No active spec' from shared prologue, got: %v", err)
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

// Test_ProdGuardPrologue_MissingActiveSpecKeyBlocks pins the cleared-shape
// path through prodGuardPrologue for the omitempty-cleared state.json shape
// introduced by spec 0012. The active_spec key is absent entirely (distinct
// from makeTestRepo's "active_spec":null shape) and the guard must still
// emit prologueBlock + "No active spec" via Go's empty-string zero value
// for the missing JSON field.
//
// This is an assertion-pinning refactor test (spec 0013 plan §Framing,
// Site B): it passes both before and after the removal of the dead
// null-equality disjunct at main.go:353. It locks in the cleared-shape
// path so a future redesign of prodGuardPrologue cannot silently regress
// it.
func Test_ProdGuardPrologue_MissingActiveSpecKeyBlocks(t *testing.T) {
	root := t.TempDir()
	specDir := filepath.Join(root, ".speccraft")
	if err := os.MkdirAll(specDir, 0o755); err != nil {
		t.Fatal(err)
	}
	// AC3 fixture-setup (pinned): write the omitempty-cleared shape
	// verbatim — no active_spec key at all. Distinct from the
	// makeTestRepo("","") shape which writes "active_spec":null.
	state := `{"version":1,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}`
	if err := os.WriteFile(filepath.Join(specDir, "state.json"), []byte(state), 0o644); err != nil {
		t.Fatal(err)
	}

	absPath := filepath.Join(root, "pkg", "foo.go")

	dec, err := prodGuardPrologue(absPath, root)
	if dec != prologueBlock {
		t.Errorf("dec = %v, want prologueBlock", dec)
	}
	if err == nil {
		t.Fatal("err = nil, want non-nil")
	}
	if !strings.Contains(err.Error(), "No active spec") {
		t.Errorf("err = %q, want substring %q", err.Error(), "No active spec")
	}
}

// --- Spec 0018 T6: capture red-candidates on sibling test-file edit (RED→GREEN) ---

// captureCase drives processToolUse with an edit to a test file and returns
// the captured just-added id set for that file.
func captureCase(t *testing.T, root, testFile, diskContent, newContent string) []string {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(testFile), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(testFile, []byte(diskContent), 0o644); err != nil {
		t.Fatal(err)
	}
	input := HookInput{
		// OldString empty ⇒ Write semantics: NewString is the whole post-edit file.
		ToolInput: ToolInput{FilePath: testFile, NewString: newContent},
		CWD:       root,
	}
	if err := processToolUse(input, deps{}); err != nil {
		t.Fatalf("test-file edit should be allowed, got: %v", err)
	}
	abs, _ := filepath.Abs(testFile)
	got, err := speccraft.GetRedCandidates(root)
	if err != nil {
		t.Fatal(err)
	}
	return got[abs]
}

func Test_TestFileEdit_CapturesRedCandidates_Go(t *testing.T) {
	root := makeTestRepo(t, "0018-technical-review", "in-progress")
	disk := "package pkg\n\nfunc TestExisting(t *testing.T) {}\n"
	post := "package pkg\n\nfunc TestExisting(t *testing.T) {}\n\nfunc TestNew(t *testing.T) {}\n"
	got := captureCase(t, root, filepath.Join(root, "pkg", "foo_test.go"), disk, post)
	if !containsStr(got, "TestNew") {
		t.Errorf("expected captured candidates to include TestNew, got %v", got)
	}
	if containsStr(got, "TestExisting") {
		t.Errorf("pre-existing TestExisting must NOT be just-added, got %v", got)
	}
}

func Test_TestFileEdit_BlankLineEdit_CapturesEmptyForGo(t *testing.T) {
	root := makeTestRepo(t, "0018-technical-review", "in-progress")
	disk := "package pkg\n\nfunc TestExisting(t *testing.T) {}\n"
	post := "package pkg\n\nfunc TestExisting(t *testing.T) {}\n\n" // only a blank line added
	got := captureCase(t, root, filepath.Join(root, "pkg", "foo_test.go"), disk, post)
	if len(got) != 0 {
		t.Errorf("blank-line edit must capture NO just-added ids, got %v", got)
	}
}

func Test_TestFileEdit_CapturesRedCandidates_Python(t *testing.T) {
	root := makeTestRepo(t, "0018-technical-review", "in-progress")
	disk := "def test_existing():\n    assert True\n"
	post := "def test_existing():\n    assert True\n\ndef test_new():\n    assert False\n"
	got := captureCase(t, root, filepath.Join(root, "pkg", "test_foo.py"), disk, post)
	if !containsStr(got, "test_new") {
		t.Errorf("expected captured candidates to include test_new, got %v", got)
	}
}

func Test_TestFileEdit_CapturesRedCandidates_JSTS(t *testing.T) {
	root := makeTestRepo(t, "0018-technical-review", "in-progress")
	disk := "test('existing', () => {})\n"
	post := "test('existing', () => {})\ntest('brandnew', () => {})\n"
	got := captureCase(t, root, filepath.Join(root, "src", "foo.test.ts"), disk, post)
	if !containsStr(got, "brandnew") {
		t.Errorf("expected captured candidates to include brandnew, got %v", got)
	}
}

func containsStr(s []string, v string) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}

// --- Spec 0018 T14: siblingRedCheck (empty-blocks / runner-absent / timeout) ---

// fakeLangRunner is a runner.Runner that records calls, the presence of a
// context deadline, and returns a configured result/error.
type fakeLangRunner struct {
	calls       []runner.Request
	hadDeadline bool
	result      runner.Result
	err         error
}

func (f *fakeLangRunner) Run(ctx context.Context, req runner.Request) (runner.Result, error) {
	_, f.hadDeadline = ctx.Deadline()
	f.calls = append(f.calls, req)
	return f.result, f.err
}

func fixedRunnerForLang(r runner.Runner, ok bool) func(string, speccraft.SpeccraftConfig) (runner.Runner, bool) {
	return func(string, speccraft.SpeccraftConfig) (runner.Runner, bool) { return r, ok }
}

// goRedCheckRepo sets up an in-progress repo with pkg/foo.go + pkg/foo_test.go
// on disk and (optionally) seeds RedCandidates for the sibling test file.
func goRedCheckRepo(t *testing.T, justAdded []string) (root, prodFile string) {
	t.Helper()
	root = makeTestRepo(t, "0018-technical-review", "in-progress")
	dir := filepath.Join(root, "pkg")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	prodFile = filepath.Join(dir, "foo.go")
	os.WriteFile(prodFile, []byte("package pkg\n"), 0o644)
	sib := filepath.Join(dir, "foo_test.go")
	os.WriteFile(sib, []byte("package pkg\n"), 0o644)
	if justAdded != nil {
		if err := speccraft.SetRedCandidates(root, sib, justAdded); err != nil {
			t.Fatal(err)
		}
	}
	return root, prodFile
}

func Test_SiblingRedCheck_EmptyJustAdded_Blocks_NoRunnerInvoked(t *testing.T) {
	root, prodFile := goRedCheckRepo(t, nil) // no captured candidates
	fake := &fakeLangRunner{result: runner.Result{Outcome: runner.OutcomeAllPassed}}
	d := deps{runnerForLang: fixedRunnerForLang(fake, true)}

	err := siblingRedCheck(prodFile, root, speccraft.SpeccraftConfig{}, "go", d)
	if err == nil {
		t.Fatal("expected block when no test was just-added")
	}
	if !strings.Contains(err.Error(), "add a failing test") {
		t.Errorf("error should prompt to add a failing test, got: %v", err)
	}
	if len(fake.calls) != 0 {
		t.Errorf("runner must NOT be invoked on empty just-added set, got %d calls", len(fake.calls))
	}
}

func Test_SiblingRedCheck_RunnerAbsent_FailsClosed(t *testing.T) {
	root, prodFile := goRedCheckRepo(t, []string{"TestNew"})
	d := deps{runnerForLang: fixedRunnerForLang(nil, false)} // unresolved runner

	err := siblingRedCheck(prodFile, root, speccraft.SpeccraftConfig{}, "go", d)
	if err == nil {
		t.Fatal("expected fail-closed block when runner is absent (D2)")
	}
	if !strings.Contains(err.Error(), "no test runner available") {
		t.Errorf("error should say 'no test runner available', got: %v", err)
	}
}

func Test_SiblingRedCheck_TimeoutError_Blocks(t *testing.T) {
	root, prodFile := goRedCheckRepo(t, []string{"TestNew"})
	fake := &fakeLangRunner{err: context.DeadlineExceeded}
	d := deps{runnerForLang: fixedRunnerForLang(fake, true)}

	err := siblingRedCheck(prodFile, root, speccraft.SpeccraftConfig{}, "go", d)
	if err == nil {
		t.Fatal("expected block (not allow) when the runner errors/times out")
	}
	if !fake.hadDeadline {
		t.Error("siblingRedCheck must invoke the runner with a deadline-bounded context (AC9)")
	}
}

// --- Spec 0018 T16: Go/Python prod-guard red-check (AC1/2/3/4/6/7/10) ---

// redCheckRepo builds an in-progress repo with a production file and a sibling
// test file, optionally seeding RedCandidates for the sibling.
func redCheckRepo(t *testing.T, prodRel, sibRel string, justAdded []string) (root, prodFile string) {
	t.Helper()
	root = makeTestRepo(t, "0018-technical-review", "in-progress")
	prodFile = filepath.Join(root, filepath.FromSlash(prodRel))
	sib := filepath.Join(root, filepath.FromSlash(sibRel))
	if err := os.MkdirAll(filepath.Dir(prodFile), 0o755); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(prodFile, []byte("// prod\n"), 0o644)
	os.WriteFile(sib, []byte("// test\n"), 0o644)
	if justAdded != nil {
		if err := speccraft.SetRedCandidates(root, sib, justAdded); err != nil {
			t.Fatal(err)
		}
	}
	return root, prodFile
}

func depsWithRunner(r runner.Runner) deps {
	return deps{runnerForLang: fixedRunnerForLang(r, true)}
}

func Test_GoProdGuard_GreenSibling_Blocks(t *testing.T) {
	root, prod := redCheckRepo(t, "pkg/foo.go", "pkg/foo_test.go", []string{"TestNew"})
	fake := &fakeLangRunner{result: runner.Result{
		Outcome: runner.OutcomeAllPassed,
		Records: []runner.TestRecord{{TestName: "TestNew", Status: "passed"}},
	}}
	err := goPythonProdGuard(prod, root, speccraft.SpeccraftConfig{}, depsWithRunner(fake))
	if err == nil || !strings.Contains(err.Error(), "no failing test observed") {
		t.Fatalf("green sibling must block with 'no failing test observed', got: %v", err)
	}
}

func Test_GoProdGuard_NoTargetedTest_Blocks(t *testing.T) {
	root, prod := redCheckRepo(t, "pkg/foo.go", "pkg/foo_test.go", nil)
	fake := &fakeLangRunner{}
	err := goPythonProdGuard(prod, root, speccraft.SpeccraftConfig{}, depsWithRunner(fake))
	if err == nil || !strings.Contains(err.Error(), "add a failing test") {
		t.Fatalf("no just-added test must block, got: %v", err)
	}
	if len(fake.calls) != 0 {
		t.Errorf("runner must not be invoked when nothing was just-added, got %d", len(fake.calls))
	}
}

func Test_GoProdGuard_FailingJustAdded_Allows(t *testing.T) {
	root, prod := redCheckRepo(t, "pkg/foo.go", "pkg/foo_test.go", []string{"TestNew"})
	fake := &fakeLangRunner{result: runner.Result{
		Outcome: runner.OutcomeAtLeastOneFailed,
		Records: []runner.TestRecord{{TestName: "TestNew", Status: "failed"}},
	}}
	if err := goPythonProdGuard(prod, root, speccraft.SpeccraftConfig{}, depsWithRunner(fake)); err != nil {
		t.Fatalf("failing just-added test must allow, got: %v", err)
	}
}

func Test_GoProdGuard_UnrelatedFailure_Blocks(t *testing.T) {
	root, prod := redCheckRepo(t, "pkg/foo.go", "pkg/foo_test.go", []string{"TestNew"})
	fake := &fakeLangRunner{result: runner.Result{
		Outcome: runner.OutcomeAtLeastOneFailed,
		Records: []runner.TestRecord{{TestName: "TestUnrelated", Status: "failed"}},
	}}
	err := goPythonProdGuard(prod, root, speccraft.SpeccraftConfig{}, depsWithRunner(fake))
	if err == nil || !strings.Contains(err.Error(), "no failing test observed") {
		t.Fatalf("a failure outside the just-added set must block (D1/AC7), got: %v", err)
	}
}

func Test_GoProdGuard_BuildFailed_Blocks(t *testing.T) {
	root, prod := redCheckRepo(t, "pkg/foo.go", "pkg/foo_test.go", []string{"TestNew"})
	fake := &fakeLangRunner{result: runner.Result{
		Outcome: runner.OutcomeBuildFailed,
		Stderr:  "syntax error",
	}}
	err := goPythonProdGuard(prod, root, speccraft.SpeccraftConfig{}, depsWithRunner(fake))
	if err == nil || !strings.Contains(err.Error(), "build/collection failed") {
		t.Fatalf("build failure must block and be distinguished from missing RED, got: %v", err)
	}
}

func Test_PythonProdGuard_GreenBlocks_FailingAllows(t *testing.T) {
	// Green → block.
	root, prod := redCheckRepo(t, "pkg/foo.py", "pkg/test_foo.py", []string{"test_new"})
	green := &fakeLangRunner{result: runner.Result{
		Outcome: runner.OutcomeAllPassed,
		Records: []runner.TestRecord{{TestName: "test_new", Status: "passed"}},
	}}
	if err := goPythonProdGuard(prod, root, speccraft.SpeccraftConfig{}, depsWithRunner(green)); err == nil {
		t.Fatal("python green sibling must block")
	}
	// Failing just-added → allow.
	root2, prod2 := redCheckRepo(t, "pkg/foo.py", "pkg/test_foo.py", []string{"test_new"})
	red := &fakeLangRunner{result: runner.Result{
		Outcome: runner.OutcomeAtLeastOneFailed,
		Records: []runner.TestRecord{{TestName: "test_new", Status: "failed"}},
	}}
	if err := goPythonProdGuard(prod2, root2, speccraft.SpeccraftConfig{}, depsWithRunner(red)); err != nil {
		t.Fatalf("python failing just-added must allow, got: %v", err)
	}
}

func Test_GoProdGuard_BlankLineBypassClosed(t *testing.T) {
	// Edit the sibling test file with a blank-line-only change (captures an
	// empty just-added set), then attempt the production edit → must block.
	root := makeTestRepo(t, "0018-technical-review", "in-progress")
	dir := filepath.Join(root, "pkg")
	os.MkdirAll(dir, 0o755)
	prod := filepath.Join(dir, "foo.go")
	sib := filepath.Join(dir, "foo_test.go")
	os.WriteFile(prod, []byte("package pkg\n"), 0o644)
	os.WriteFile(sib, []byte("package pkg\n\nfunc TestExisting(t *testing.T) {}\n"), 0o644)

	fake := &fakeLangRunner{}
	d := depsWithRunner(fake)

	// Blank-line-only edit to the sibling test file.
	testEdit := HookInput{
		ToolInput: ToolInput{FilePath: sib, NewString: "package pkg\n\nfunc TestExisting(t *testing.T) {}\n\n"},
		CWD:       root,
	}
	if err := processToolUse(testEdit, d); err != nil {
		t.Fatalf("test-file edit should be allowed: %v", err)
	}
	// Now the production edit must be blocked (P0-1 regression, Go path).
	prodEdit := HookInput{ToolInput: ToolInput{FilePath: prod, NewString: "package pkg\nvar X = 1\n"}, CWD: root}
	err := processToolUse(prodEdit, d)
	if err == nil || !strings.Contains(err.Error(), "no failing test observed") {
		t.Fatalf("blank-line test touch must NOT unlock the Go production edit, got: %v", err)
	}
	if len(fake.calls) != 0 {
		t.Errorf("runner must not run for an empty just-added set, got %d calls", len(fake.calls))
	}
}

// --- Spec 0018 T18: JS/TS dispatch red-check (AC1/2/3/5/6/7/8/10) ---

func jsCfg() speccraft.SpeccraftConfig {
	var cfg speccraft.SpeccraftConfig
	cfg.TDD.JavaScript.Command = "vitest run --reporter=tap"
	cfg.TDD.TypeScript.Command = "vitest run --reporter=tap"
	return cfg
}

// jsTsRedRepo builds an in-progress repo with src/foo.ts + src/foo.test.ts and
// optionally seeds RedCandidates for the test file.
func jsTsRedRepo(t *testing.T, justAdded []string) (root, prodFile string) {
	t.Helper()
	root = makeTestRepo(t, "0018-technical-review", "in-progress")
	dir := filepath.Join(root, "src")
	os.MkdirAll(dir, 0o755)
	prodFile = filepath.Join(dir, "foo.ts")
	sib := filepath.Join(dir, "foo.test.ts")
	os.WriteFile(prodFile, []byte("export const x = 1;\n"), 0o644)
	os.WriteFile(sib, []byte("test('x', () => {})\n"), 0o644)
	if justAdded != nil {
		if err := speccraft.SetRedCandidates(root, sib, justAdded); err != nil {
			t.Fatal(err)
		}
	}
	return root, prodFile
}

func Test_JSTSDispatch_GreenSibling_Blocks(t *testing.T) {
	root, prod := jsTsRedRepo(t, []string{"x"})
	fake := &fakeLangRunner{result: runner.Result{
		Outcome: runner.OutcomeAllPassed,
		Records: []runner.TestRecord{{TestName: "x", Status: "passed"}},
	}}
	err := jsTsDispatch(prod, root, jsCfg(), depsWithRunner(fake))
	if err == nil || !strings.Contains(err.Error(), "no failing test observed") {
		t.Fatalf("green JS/TS sibling must block, got: %v", err)
	}
}

func Test_JSTSDispatch_NoTargetedTest_Blocks(t *testing.T) {
	root, prod := jsTsRedRepo(t, nil)
	fake := &fakeLangRunner{}
	err := jsTsDispatch(prod, root, jsCfg(), depsWithRunner(fake))
	if err == nil || !strings.Contains(err.Error(), "add a failing test") {
		t.Fatalf("no just-added JS/TS test must block, got: %v", err)
	}
	if len(fake.calls) != 0 {
		t.Errorf("runner must not run on empty just-added, got %d", len(fake.calls))
	}
}

func Test_JSTSDispatch_FailingJustAdded_Allows(t *testing.T) {
	root, prod := jsTsRedRepo(t, []string{"x"})
	fake := &fakeLangRunner{result: runner.Result{
		Outcome: runner.OutcomeAtLeastOneFailed,
		Records: []runner.TestRecord{{TestName: "x", Status: "failed"}},
	}}
	if err := jsTsDispatch(prod, root, jsCfg(), depsWithRunner(fake)); err != nil {
		t.Fatalf("failing just-added JS/TS test must allow, got: %v", err)
	}
}

func Test_JSTSDispatch_UnrelatedFailure_Blocks(t *testing.T) {
	root, prod := jsTsRedRepo(t, []string{"x"})
	fake := &fakeLangRunner{result: runner.Result{
		Outcome: runner.OutcomeAtLeastOneFailed,
		Records: []runner.TestRecord{{TestName: "y", Status: "failed"}},
	}}
	err := jsTsDispatch(prod, root, jsCfg(), depsWithRunner(fake))
	if err == nil || !strings.Contains(err.Error(), "no failing test observed") {
		t.Fatalf("unrelated JS/TS failure must block (AC7), got: %v", err)
	}
}

func Test_JSTSDispatch_BuildFailed_Blocks(t *testing.T) {
	root, prod := jsTsRedRepo(t, []string{"x"})
	fake := &fakeLangRunner{result: runner.Result{Outcome: runner.OutcomeBuildFailed, Stderr: "SyntaxError"}}
	err := jsTsDispatch(prod, root, jsCfg(), depsWithRunner(fake))
	if err == nil || !strings.Contains(err.Error(), "build/collection failed") {
		t.Fatalf("JS/TS build failure must block distinctly, got: %v", err)
	}
}

func Test_JSTSDispatch_RunnerAbsent_FailsClosed(t *testing.T) {
	root, prod := jsTsRedRepo(t, []string{"x"})
	// Empty configured command + real factory ⇒ unresolved runner ⇒ fail closed.
	var emptyCfg speccraft.SpeccraftConfig
	d := deps{runnerForLang: runner.AdapterForLanguage}
	err := jsTsDispatch(prod, root, emptyCfg, d)
	if err == nil || !strings.Contains(err.Error(), "no test runner available") {
		t.Fatalf("unconfigured JS/TS runner must fail closed (D2/AC8), got: %v", err)
	}
}

func Test_JSTSDispatch_BlankLineBypassClosed(t *testing.T) {
	root := makeTestRepo(t, "0018-technical-review", "in-progress")
	dir := filepath.Join(root, "src")
	os.MkdirAll(dir, 0o755)
	prod := filepath.Join(dir, "foo.ts")
	sib := filepath.Join(dir, "foo.test.ts")
	os.WriteFile(prod, []byte("export const x = 1;\n"), 0o644)
	os.WriteFile(sib, []byte("test('existing', () => {})\n"), 0o644)

	fake := &fakeLangRunner{}
	d := deps{runnerForLang: fixedRunnerForLang(fake, true)}

	testEdit := HookInput{ToolInput: ToolInput{FilePath: sib, NewString: "test('existing', () => {})\n\n"}, CWD: root}
	if err := processToolUse(testEdit, d); err != nil {
		t.Fatalf("test-file edit should be allowed: %v", err)
	}
	prodEdit := HookInput{ToolInput: ToolInput{FilePath: prod, NewString: "export const x = 2;\n"}, CWD: root}
	err := processToolUse(prodEdit, d)
	if err == nil || !strings.Contains(err.Error(), "no failing test observed") {
		t.Fatalf("blank-line test touch must NOT unlock the JS/TS production edit (AC10), got: %v", err)
	}
}

// --- Spec 0018 T20: productionDeps wires the language runner factory ---

func Test_ProductionDeps_HasRunnerForLang(t *testing.T) {
	d := productionDeps()
	if d.runnerForLang == nil {
		t.Fatal("productionDeps must wire runnerForLang (AdapterForLanguage)")
	}
	if _, ok := d.runnerForLang("go", speccraft.SpeccraftConfig{}); !ok {
		t.Error("productionDeps runnerForLang should resolve a Go adapter")
	}
}
