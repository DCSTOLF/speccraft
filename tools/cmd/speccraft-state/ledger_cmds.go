package main

import (
	"fmt"
	"io"
	"path/filepath"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// ledgerSetCmd implements `speccraft-state ledger-set <design> <member> <field>
// <value>` (spec 0038 AC6): resolve the workspace root and upsert
// <root>/.speccraft/ledger.md. An invalid field (incl. conductor-managed
// `updated`) surfaces non-zero and writes nothing.
func ledgerSetCmd(designID, memberPath, field, value string, stdout, stderr io.Writer) int {
	root, err := speccraft.FindWorkspaceRoot("")
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	ledger := filepath.Join(root, ".speccraft", "ledger.md")
	if err := speccraft.SetLedgerField(ledger, designID, memberPath, field, value); err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}

// reconcileCmd implements `speccraft-state reconcile <design>` (spec 0038 AC6):
// read the workspace ledger, resolve each member's child-spec status from that
// member repo (dual live/.archive), and print `done: <bool>` plus one
// `<status>\t<member>\t<spec-ref>` line per member (in ledger order). A
// malformed ledger exits non-zero with nothing on stdout.
func reconcileCmd(designID string, stdout, stderr io.Writer) int {
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
	resolve := func(memberPath, specRef string) (string, bool) {
		v, _, outcome, _ := resolveSpecStatus(filepath.Join(root, memberPath), specRef)
		return v, outcome == resolveResolved
	}
	r := speccraft.Reconcile(ledger, designID, resolve)
	fmt.Fprintf(stdout, "done: %v\n", r.Done)
	for _, m := range r.Members {
		status := m.Status
		if m.Class == "blocked" {
			status = "blocked"
		}
		fmt.Fprintf(stdout, "%s\t%s\t%s\n", status, m.Member, m.Spec)
	}
	return 0
}
