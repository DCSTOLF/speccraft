package runner_test

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
	"github.com/dcstolf/speccraft/tools/internal/speccraft/runner"
)

// gateRepo prepares a tempdir with .speccraft/ + a minimal crate layout.
// It seeds the fingerprint to the current crate state so the next call
// to RunPreEditGate is a cache hit unless tests mutate something.
func gateRepo(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	write(t, root, "Cargo.toml", "[package]\n")
	write(t, root, "src/lib.rs", "// lib\n")
	return root
}

// captureExec records invocations so tests can assert how many times
// (and with what args) the gate shelled out.
type captureExec struct {
	calls [][]string
}

func (c *captureExec) fn() runner.ExecFunc {
	return func(_ context.Context, name string, args []string, workDir string) ([]byte, []byte, int, error) {
		c.calls = append(c.calls, append([]string{name}, args...))
		return nil, nil, 0, nil
	}
}

func TestPreEditGate_CacheHit_NoSubprocess(t *testing.T) {
	root := gateRepo(t)
	// Seed the stored fingerprint to the current crate state.
	fp, _ := runner.ComputeCrateFingerprint(root)
	if err := speccraft.SetRustFingerprint(root, fp); err != nil {
		t.Fatal(err)
	}
	cap := &captureExec{}
	if err := runner.RunPreEditGate(root, cap.fn()); err != nil {
		t.Fatalf("gate: %v", err)
	}
	if len(cap.calls) != 0 {
		t.Errorf("cache hit invoked %d subprocesses, want 0: %v", len(cap.calls), cap.calls)
	}
}

func TestPreEditGate_TouchedFileChange_Invalidates(t *testing.T) {
	root := gateRepo(t)
	fp, _ := runner.ComputeCrateFingerprint(root)
	speccraft.SetRustFingerprint(root, fp)

	// Mutate src/lib.rs.
	libPath := filepath.Join(root, "src", "lib.rs")
	os.WriteFile(libPath, []byte("// changed\n"), 0o644)
	os.Chtimes(libPath, time.Now().Add(3*time.Second), time.Now().Add(3*time.Second))

	cap := &captureExec{}
	if err := runner.RunPreEditGate(root, cap.fn()); err != nil {
		t.Fatalf("gate: %v", err)
	}
	if len(cap.calls) != 1 {
		t.Fatalf("expected 1 subprocess call, got %d: %v", len(cap.calls), cap.calls)
	}
	args := cap.calls[0]
	if args[0] != "cargo" || !contains(args, "check") || !contains(args, "--tests") {
		t.Errorf("unexpected gate argv: %v", args)
	}
}

func TestPreEditGate_UnrelatedRsChange_Invalidates(t *testing.T) {
	root := gateRepo(t)
	bPath := write(t, root, "src/b.rs", "// b\n")
	fp, _ := runner.ComputeCrateFingerprint(root)
	speccraft.SetRustFingerprint(root, fp)

	os.WriteFile(bPath, []byte("// b changed\n"), 0o644)
	os.Chtimes(bPath, time.Now().Add(3*time.Second), time.Now().Add(3*time.Second))

	cap := &captureExec{}
	runner.RunPreEditGate(root, cap.fn())
	if len(cap.calls) != 1 {
		t.Errorf("expected cargo invocation on unrelated change, got %v", cap.calls)
	}
}

func TestPreEditGate_CargoTomlChange_Invalidates(t *testing.T) {
	root := gateRepo(t)
	fp, _ := runner.ComputeCrateFingerprint(root)
	speccraft.SetRustFingerprint(root, fp)

	cargoPath := filepath.Join(root, "Cargo.toml")
	os.WriteFile(cargoPath, []byte("[package]\nname = \"foo\"\n"), 0o644)
	os.Chtimes(cargoPath, time.Now().Add(3*time.Second), time.Now().Add(3*time.Second))

	cap := &captureExec{}
	runner.RunPreEditGate(root, cap.fn())
	if len(cap.calls) != 1 {
		t.Errorf("expected cargo invocation on Cargo.toml change, got %v", cap.calls)
	}
}

func TestPreEditGate_TargetDirChange_DoesNotInvalidate(t *testing.T) {
	root := gateRepo(t)
	fp, _ := runner.ComputeCrateFingerprint(root)
	speccraft.SetRustFingerprint(root, fp)

	// Drop a file under target/ — must not invalidate.
	write(t, root, "target/debug/some-output", "binary contents\n")

	cap := &captureExec{}
	if err := runner.RunPreEditGate(root, cap.fn()); err != nil {
		t.Fatalf("gate: %v", err)
	}
	if len(cap.calls) != 0 {
		t.Errorf("target/ change incorrectly triggered cargo: %v", cap.calls)
	}
}

func TestPreEditGate_SuccessUpdatesFingerprint(t *testing.T) {
	root := gateRepo(t)
	speccraft.SetRustFingerprint(root, "stale-value")

	cap := &captureExec{}
	if err := runner.RunPreEditGate(root, cap.fn()); err != nil {
		t.Fatalf("gate: %v", err)
	}
	if len(cap.calls) != 1 {
		t.Fatalf("expected cargo invocation, got %v", cap.calls)
	}
	stored, _ := speccraft.GetRustFingerprint(root)
	want, _ := runner.ComputeCrateFingerprint(root)
	if stored != want {
		t.Errorf("fingerprint not updated: stored=%q, want=%q", stored, want)
	}
}

func TestPreEditGate_CargoFailure_DoesNotUpdateFingerprint(t *testing.T) {
	root := gateRepo(t)
	speccraft.SetRustFingerprint(root, "before")

	failExec := func(_ context.Context, _ string, _ []string, _ string) ([]byte, []byte, int, error) {
		return nil, []byte("error[E0425]: cannot find value `whoops`\n"), 101, nil
	}
	err := runner.RunPreEditGate(root, failExec)
	if err == nil {
		t.Fatal("expected non-nil error from failing cargo check")
	}
	if !strings.Contains(err.Error(), "build") && !strings.Contains(err.Error(), "check") {
		t.Errorf("error should mention build/check: %v", err)
	}
	stored, _ := speccraft.GetRustFingerprint(root)
	if stored != "before" {
		t.Errorf("fingerprint changed after failure: %q", stored)
	}
}

func contains(args []string, want string) bool {
	for _, a := range args {
		if a == want {
			return true
		}
	}
	return false
}
