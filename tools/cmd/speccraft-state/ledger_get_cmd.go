package main

import (
	"fmt"
	"io"
	"path/filepath"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// ledgerGetCmd implements `speccraft-state ledger-get [<design>]` (spec 0043 AC2):
// the raw-dump oracle. Unlike `reconcile` (which resolves each member's live spec
// status), this prints the *stored* ledger pointer fields, one tab-delimited line
// per member in ledger order —
// <design>\t<member>\t<spec>\t<last_completed_phase>\t<in_flight>\t<blocked>.
// An optional <design> filters to that design. A missing ledger.md yields zero
// lines + exit 0 (the spec-0038 lazy-ledger contract, since ParseLedger treats a
// missing file as an empty ledger); a parse-corrupt ledger exits non-zero with
// nothing on stdout (parity with reconcile). Readers are untouched — this is a new
// consumer of ParseLedger.
func ledgerGetCmd(designFilter string, stdout, stderr io.Writer) int {
	root, err := speccraft.FindWorkspaceRoot("")
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	ledger, perr := speccraft.ParseLedger(filepath.Join(root, ".speccraft", "ledger.md"))
	if perr != nil {
		fmt.Fprintln(stderr, perr)
		return 1
	}
	for _, d := range ledger.Designs {
		if designFilter != "" && d.ID != designFilter {
			continue
		}
		for _, m := range d.Members {
			fmt.Fprintf(stdout, "%s\t%s\t%s\t%s\t%s\t%s\n",
				d.ID, m.Path, m.Spec, m.LastCompletedPhase, m.InFlight, m.Blocked)
		}
	}
	return 0
}
