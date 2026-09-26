package main

import (
	"fmt"
	"io"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// designFingerprintCmd prints the spec-0044 design fingerprint — sha256 of the
// `reconcile <design>` output — as a bare hex line.
//
// It exists so shell callers never have to compute a sha256 themselves.
// `commands/sync.lib.sh` used to pipe `reconcile` into `sha256sum`, which is GNU
// coreutils only: on macOS (`shasum -a 256`) that failed with "command not found"
// and took `sync_design_fingerprint` and every caller of it with it, including
// `sync_consolidate_design`. Spec 0050 AC11.
//
// Deliberately NOT under the ledger lock, unlike ledgerArchiveCmd. This is a
// single read-only computation with no write to serialise against, and taking the
// exclusive lock would make an informational read contend with real writers. A
// concurrent write can of course change the answer, which is precisely why the
// fingerprint exists: `ledger-archive --expect` re-verifies it under the lock, and
// a value that went stale in between is rejected there.
func designFingerprintCmd(designID string, stdout, stderr io.Writer) int {
	root, err := speccraft.FindWorkspaceRoot("")
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	fp, err := designFingerprint(root, designID)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	fmt.Fprintln(stdout, fp)
	return 0
}
