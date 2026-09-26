package main

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"
)

// Spec 0050 AC11 — `speccraft-state design-fingerprint <design>`.
//
// WHY A SUBCOMMAND AND NOT A PORTABLE SHELL FALLBACK. `sync_design_fingerprint`
// in commands/sync.lib.sh computed `speccraft-state reconcile <design> | sha256sum`.
// `sha256sum` is GNU coreutils only — macOS ships `shasum -a 256` — so the helper,
// and every caller of it, died with `sha256sum: command not found` on BSD userland.
// That was five of the eleven failures in the first-ever run of the bats suite on
// macOS.
//
// The obvious fix is a `command -v sha256sum || shasum -a 256` shim in the shell.
// It was rejected: `designFingerprint` in ledger_archive_cmd.go ALREADY computes
// this exact value for `ledger-archive --expect`, so the shell copy was a second
// implementation of one value. Porting it in place would have kept two things that
// can silently drift apart — and the whole point of the fingerprint is that the
// shell's idea of it and the binary's idea of it are the same. Exposing the Go
// value and deleting the shell arithmetic removes the divergence as well as the
// portability defect.
//
// RED before implementation: the subcommand is unknown, so run() returns non-zero.

func Test_DesignFingerprint_EqualsSha256OfReconcileOutput(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")

	code, stdout, stderr := runCmd(t, ws, "design-fingerprint", "D")
	if code != 0 {
		t.Fatalf("design-fingerprint should succeed; code=%d stderr=%s", code, stderr)
	}

	// Asserted against an INDEPENDENT computation over `reconcile`'s bytes, not
	// against designFingerprint itself: the contract this subcommand exists to
	// honour is "equal to sha256 of the reconcile output", and comparing the
	// implementation to itself would assert nothing.
	_, recon, _ := runCmd(t, ws, "reconcile", "D")
	sum := sha256.Sum256([]byte(recon))
	want := hex.EncodeToString(sum[:])

	if got := strings.TrimSpace(stdout); got != want {
		t.Errorf("fingerprint mismatch:\n got %q\nwant %q", got, want)
	}
}

// It must agree with the value `ledger-archive --expect` compares against, or the
// shell would compute a fingerprint that can never match the binary's gate.
func Test_DesignFingerprint_MatchesLedgerArchiveExpect(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")

	_, fp, _ := runCmd(t, ws, "design-fingerprint", "D")
	code, _, stderr := runCmd(t, ws, "ledger-archive", "D", "--expect", strings.TrimSpace(fp))
	if code != 0 {
		t.Fatalf("the fingerprint this command prints must satisfy --expect; code=%d stderr=%s", code, stderr)
	}
}

// Exactly one trailing newline and nothing else on stdout: the shell captures this
// with `$(…)`, and any extra field would be silently folded into the value.
func Test_DesignFingerprint_PrintsBareHexLine(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")

	_, stdout, _ := runCmd(t, ws, "design-fingerprint", "D")
	if strings.Count(stdout, "\n") != 1 || !strings.HasSuffix(stdout, "\n") {
		t.Errorf("expected exactly one trailing newline, got %q", stdout)
	}
	body := strings.TrimSpace(stdout)
	if len(body) != 64 {
		t.Errorf("expected 64 hex chars, got %d: %q", len(body), body)
	}
	if strings.ContainsAny(body, " \t") {
		t.Errorf("no whitespace inside the value (this is why `| awk '{print $1}'` was needed before): %q", body)
	}
}

func Test_DesignFingerprint_UsageWithoutDesign(t *testing.T) {
	ws := mkWorkspace(t, "")
	code, _, stderr := runCmd(t, ws, "design-fingerprint")
	if code == 0 {
		t.Error("a missing design argument must not exit 0")
	}
	if !strings.Contains(stderr, "design-fingerprint") {
		t.Errorf("usage must name the subcommand, got %q", stderr)
	}
}
