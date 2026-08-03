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
	// reconcileOutput (spec 0044) produces the exact reconcile bytes and surfaces a
	// malformed-ledger parse error identically to the prior inline path.
	out, oerr := reconcileOutput(root, designID)
	if oerr != nil {
		fmt.Fprintln(stderr, oerr)
		return 1
	}
	fmt.Fprint(stdout, out)
	return 0
}
