package main

// Spec 0048 T23 (AC17) — the build-repair log's reader.
//
// The log is only worth keeping if something reads it. `/speccraft:spec:close`
// runs this alongside the tasks-verify gate so a session that admitted edits
// against a broken build says so at close, rather than leaving an audit trail
// nobody looks at.
//
// INFORMATIONAL BY CONTRACT: this always exits 0. A report that could fail the
// close would make an honest multi-step repair look like a failure, and the
// rational response would be to avoid repair mode rather than use it — which
// would put the wedge back.

import (
	"fmt"
	"io"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func buildRepairLogCmd(root string, stdout, stderr io.Writer) int {
	br, err := speccraft.GetBuildRepair(root)
	if err != nil {
		// Even a read failure does not gate the close; it is reported and the
		// caller continues.
		fmt.Fprintf(stderr, "build-repair-log: could not read state: %v\n", err)
		return 0
	}

	if len(br.Log) == 0 {
		fmt.Fprintln(stdout, "no build-repair edits recorded this session")
		return 0
	}

	open := "closed"
	if br.Attestation != nil {
		open = "OPEN (the build was still broken at the last probe)"
	}
	fmt.Fprintf(stdout, "build-repair log: %d edit(s) admitted while the build was broken; repair mode %s\n",
		len(br.Log), open)
	fmt.Fprintln(stdout, "(informational — this does not gate the close)")
	for _, e := range br.Log {
		fmt.Fprintf(stdout, "  %d. %s\n     %s\n", e.Seq, e.Path, e.Summary)
	}
	return 0
}
