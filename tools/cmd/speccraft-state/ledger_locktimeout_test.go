package main

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// Spec 0045 AC4/AC7: the ledger.lock sidecar is git-ignored like state.json —
// it is machine state, never committed, and the only new on-disk artifact.
func Test_Gitignore_IgnoresLedgerLock(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	// tools/cmd/speccraft-state/<file> → repo root is three levels up from tools/.
	repoRoot := filepath.Join(filepath.Dir(thisFile), "..", "..", "..")
	b, err := os.ReadFile(filepath.Join(repoRoot, ".gitignore"))
	if err != nil {
		t.Fatalf("read .gitignore: %v", err)
	}
	if !strings.Contains(string(b), ".speccraft/ledger.lock") {
		t.Errorf(".gitignore must ignore .speccraft/ledger.lock (like state.json); got:\n%s", b)
	}
}

// Spec 0045 AC3 (codex S2): the acquisition timeout is read from
// SPECCRAFT_LEDGER_LOCK_TIMEOUT as a Go duration; unset/empty/invalid/zero/
// negative all fall back to the 10s default, and only a strictly-positive
// value wins. These are observable-contract regression pins.
func Test_ParseLockTimeout_FallsBackTo10s(t *testing.T) {
	cases := []struct {
		raw  string
		want time.Duration
	}{
		{"", defaultLockTimeout},        // unset / empty
		{"garbage", defaultLockTimeout}, // unparseable
		{"0s", defaultLockTimeout},      // zero
		{"-5s", defaultLockTimeout},     // negative
		{"20ms", 20 * time.Millisecond}, // valid sub-default
		{"5s", 5 * time.Second},         // valid
		{"1m", time.Minute},             // valid larger
	}
	for _, c := range cases {
		if got := parseLockTimeout(c.raw); got != c.want {
			t.Errorf("parseLockTimeout(%q) = %v, want %v", c.raw, got, c.want)
		}
	}
	if defaultLockTimeout != 10*time.Second {
		t.Errorf("defaultLockTimeout = %v, want 10s", defaultLockTimeout)
	}
}
