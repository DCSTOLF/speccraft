package runner

import (
	"context"
	"errors"
	"fmt"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// ExecFunc is the exported shape of the process-runner seam used by
// RunPreEditGate. Tests inject a recording fake to assert subprocess
// invocations.
type ExecFunc = execFn

// RunPreEditGate is the pre-edit gate primitive (spec 0005 §What.4, AC #10).
//
// Behavior:
//
//  1. Compute the current crate fingerprint via ComputeCrateFingerprint.
//  2. Load the stored fingerprint via speccraft.GetRustFingerprint.
//  3. If they match → CACHE HIT: return nil. The exec function MUST NOT
//     be called.
//  4. Otherwise → CACHE MISS: invoke `cargo check --tests` via exec.
//     - On exit 0: persist the freshly-computed fingerprint via
//       speccraft.SetRustFingerprint, return nil.
//     - On non-zero exit: return an error citing build failure. The
//       stored fingerprint is NOT updated, so the next invocation will
//       still see a cache miss until the breakage is fixed.
//
// The contract is asserted behaviorally by gate_test.go using a
// recording shim (no real cargo required).
func RunPreEditGate(root string, exec ExecFunc) error {
	current, err := ComputeCrateFingerprint(root)
	if err != nil {
		return fmt.Errorf("compute crate fingerprint: %w", err)
	}
	stored, err := speccraft.GetRustFingerprint(root)
	if err != nil {
		return fmt.Errorf("load stored fingerprint: %w", err)
	}
	if stored == current {
		// Cache hit. Zero subprocesses.
		return nil
	}
	// Cache miss. Run `cargo check --tests`.
	if exec == nil {
		exec = execCmd
	}
	_, stderr, exitCode, runErr := exec(context.Background(), "cargo", []string{"check", "--tests"}, root)
	if runErr != nil {
		return fmt.Errorf("invoke cargo check: %w", runErr)
	}
	if exitCode != 0 {
		return fmt.Errorf("pre-edit gate: cargo check --tests failed (exit %d): %s", exitCode, string(stderr))
	}
	if err := speccraft.SetRustFingerprint(root, current); err != nil {
		return fmt.Errorf("persist fingerprint: %w", err)
	}
	return nil
}

// Sentinel error for callers who want to identify gate-level build
// failures specifically (vs. general exec errors). Not currently used
// internally; exported for downstream consumers.
var ErrGateBuildFailed = errors.New("pre-edit gate: build failed")
