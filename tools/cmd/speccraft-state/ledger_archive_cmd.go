package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// reconcileOutput produces the exact bytes reconcileCmd prints for a design, so the
// spec-0044 ledger-archive --expect fingerprint equals
// `speccraft-state reconcile <design> | sha256sum`.
func reconcileOutput(root, designID string) (string, error) {
	ledger, err := speccraft.ParseLedger(filepath.Join(root, ".speccraft", "ledger.md"))
	if err != nil {
		return "", err
	}
	resolve := func(memberPath, specRef string) (string, bool) {
		v, _, outcome, _ := resolveSpecStatus(filepath.Join(root, memberPath), specRef)
		return v, outcome == resolveResolved
	}
	r := speccraft.Reconcile(ledger, designID, resolve)
	var b strings.Builder
	fmt.Fprintf(&b, "done: %v\n", r.Done)
	for _, m := range r.Members {
		status := m.Status
		if m.Class == "blocked" {
			status = "blocked"
		}
		fmt.Fprintf(&b, "%s\t%s\t%s\n", status, m.Member, m.Spec)
	}
	return b.String(), nil
}

// designFingerprint is sha256 of reconcileOutput — the spec-0044 --expect fingerprint.
func designFingerprint(root, designID string) (string, error) {
	out, err := reconcileOutput(root, designID)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256([]byte(out))
	return hex.EncodeToString(sum[:]), nil
}

// designDone reports whether a design's members are all closed (reconcile Done) and
// names the not-closed members otherwise. Only meaningful for a design present in the
// live ledger (Reconcile is vacuously Done for an absent design — the caller gates on
// text-level presence first, so that never leaks here).
func designDone(root, designID string) (bool, []string, error) {
	ledger, err := speccraft.ParseLedger(filepath.Join(root, ".speccraft", "ledger.md"))
	if err != nil {
		return false, nil, err
	}
	resolve := func(memberPath, specRef string) (string, bool) {
		v, _, outcome, _ := resolveSpecStatus(filepath.Join(root, memberPath), specRef)
		return v, outcome == resolveResolved
	}
	r := speccraft.Reconcile(ledger, designID, resolve)
	var blockers []string
	for _, m := range r.Members {
		if m.Class != "closed" {
			blockers = append(blockers, m.Member)
		}
	}
	return r.Done, blockers, nil
}

// spliceDesignSection removes the `## design <id>` section from raw ledger text
// (keyed on the same heading grammar ParseLedger accepts). Returns the remainder
// (untouched sections byte-identical — a splice, not a re-serialize), the extracted
// section text, and whether it was found.
func spliceDesignSection(text, designID string) (remainder, section string, found bool) {
	lines := strings.SplitAfter(text, "\n")
	header := "## design " + designID
	start := -1
	for i, ln := range lines {
		if strings.TrimRight(ln, "\n") == header {
			start = i
			break
		}
	}
	if start == -1 {
		return text, "", false
	}
	end := len(lines)
	for i := start + 1; i < len(lines); i++ {
		t := strings.TrimRight(lines[i], "\n")
		if t == "## design" || strings.HasPrefix(t, "## design ") {
			end = i
			break
		}
	}
	section = strings.Join(lines[start:end], "")
	rem := append(append([]string{}, lines[:start]...), lines[end:]...)
	return strings.Join(rem, ""), section, true
}

func readFileOrEmpty(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(b)
}

// ledgerArchiveCmd implements `speccraft-state ledger-archive <design> [--expect <fp>]`
// (spec 0044): the sanctioned, single-read archival op that moves a done design's
// section from ledger.md to ledger.archive.md via a byte-level splice.
func ledgerArchiveCmd(designID, expect string, hasExpect bool, stdout, stderr io.Writer) int {
	root, err := speccraft.FindWorkspaceRoot("")
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	// Spec 0045: hold the exclusive ledger lock across the ENTIRE two-file
	// transaction — both-present recovery, --expect re-verify, archive
	// append+rename, and live remove+rename — so no concurrent writer can
	// interleave. Every authoritative read below happens under the lock.
	return withLedgerLock(root, stderr, func() int {
		livePath := filepath.Join(root, ".speccraft", "ledger.md")
		archivePath := filepath.Join(root, ".speccraft", "ledger.archive.md")

		// A parse-corrupt live ledger or archive aborts (never clobber). Validate both.
		if readFileOrEmpty(livePath) != "" {
			if _, e := speccraft.ParseLedger(livePath); e != nil {
				fmt.Fprintln(stderr, e)
				return 1
			}
		}
		archiveText := readFileOrEmpty(archivePath)
		if archiveText != "" {
			if _, e := speccraft.ParseLedger(archivePath); e != nil {
				fmt.Fprintln(stderr, e)
				return 1
			}
		}

		liveText := readFileOrEmpty(livePath)
		liveRemainder, liveSection, liveFound := spliceDesignSection(liveText, designID)
		_, archiveSection, archiveFound := spliceDesignSection(archiveText, designID)

		switch {
		case !liveFound && !archiveFound:
			fmt.Fprintf(stderr, "unknown design: %s\n", designID)
			return 1
		case !liveFound && archiveFound:
			return 0 // already archived — idempotent no-op
		case liveFound && archiveFound:
			// Crash residue: appended to the archive but the live copy was never removed.
			if strings.TrimRight(liveSection, "\n") != strings.TrimRight(archiveSection, "\n") {
				fmt.Fprintf(stderr, "conflict: %s present in both files with differing content\n", designID)
				return 1
			}
			if err := speccraft.AtomicWriteFile(livePath, []byte(liveRemainder), 0o644); err != nil {
				fmt.Fprintln(stderr, err)
				return 1
			}
			return 0
		}

		// liveFound && !archiveFound — the normal archive path.
		done, blockers, err := designDone(root, designID)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		if !done {
			fmt.Fprintf(stderr, "design not done: %s\n", strings.Join(blockers, ", "))
			return 1
		}
		if hasExpect {
			fp, err := designFingerprint(root, designID)
			if err != nil {
				fmt.Fprintln(stderr, err)
				return 1
			}
			if fp != expect {
				fmt.Fprintf(stderr, "conflict: %s changed\n", designID)
				return 1
			}
		}

		// Transactional: append to the archive FIRST, then remove from the live ledger.
		section := liveSection
		if !strings.HasSuffix(section, "\n") {
			section += "\n"
		}
		var newArchive string
		if archiveText == "" {
			newArchive = "# Ledger\n\n" + section
		} else {
			newArchive = strings.TrimRight(archiveText, "\n") + "\n\n" + section
		}
		if err := speccraft.AtomicWriteFile(archivePath, []byte(newArchive), 0o644); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		if err := speccraft.AtomicWriteFile(livePath, []byte(liveRemainder), 0o644); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return 0
	})
}
