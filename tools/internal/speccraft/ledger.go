package speccraft

import (
	"os"
	"strings"
	"time"
)

// Conductor ledger primitives (spec 0038). ledger.md is a history.md-class
// markdown memory file at <workspace-root>/.speccraft/ledger.md, written
// directly by the conductor (Spec 0039) — deliberately OUTSIDE the single-writer
// rule that governs the session-state file.

// ledgerNow is the injectable clock seam for the `updated` stamp; tests override
// it and restore with t.Cleanup.
var ledgerNow = time.Now

// ledgerErr carries a stable "ledger.md: " prefix so cmd/consumer assertions can
// match parse-error classes reliably.
type ledgerErr string

func (e ledgerErr) Error() string { return string(e) }

func lErr(class string) error { return ledgerErr("ledger.md: " + class) }

// LedgerMember is one member row under a design. Every field is a verbatim
// string ("" = unset). Blocked is a conductor-owned overlay; Updated is
// auto-stamped by SetLedgerField (never a settable field).
type LedgerMember struct {
	Path               string
	Spec               string
	LastCompletedPhase string
	InFlight           string
	Blocked            string
	Updated            string
}

// LedgerDesign is a design section: an id and its ordered members.
type LedgerDesign struct {
	ID      string
	Members []LedgerMember
}

// Ledger is the whole ledger.md, ordered by design then member.
type Ledger struct {
	Designs []LedgerDesign
}

// MemberStatus is one member's reconcile classification. Class is one of
// "closed" | "blocked" | "in-progress"; Status is the resolved frontmatter
// status ("" when unresolved).
type MemberStatus struct {
	Member string
	Spec   string
	Class  string
	Status string
}

// Rollup is a design's reconcile result.
type Rollup struct {
	DesignID   string
	Members    []MemberStatus
	Total      int
	Closed     int
	Blocked    int
	InProgress int
	Done       bool
}

var ledgerFieldKeys = map[string]bool{
	"spec": true, "last_completed_phase": true, "in_flight": true,
	"blocked": true, "updated": true,
}

func isLedgerKey(k string) bool { return ledgerFieldKeys[k] }

func setMemberField(m *LedgerMember, key, val string) {
	switch key {
	case "spec":
		m.Spec = val
	case "last_completed_phase":
		m.LastCompletedPhase = val
	case "in_flight":
		m.InFlight = val
	case "blocked":
		m.Blocked = val
	case "updated":
		m.Updated = val
	}
}

// ParseLedger reads ledger.md into ordered designs→members. A missing file is
// not an error (empty Ledger). Grammar per spec 0038 §What.
func ParseLedger(path string) (Ledger, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return Ledger{}, nil
		}
		return Ledger{}, err
	}

	var l Ledger
	seenDesign := map[string]bool{}
	var curDesign *LedgerDesign
	var curMember *LedgerMember
	seenMember := map[string]bool{}
	seenField := map[string]bool{}

	for _, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimPrefix(strings.TrimRight(raw, "\r"), "\ufeff")
		if strings.TrimSpace(line) == "" {
			continue // blank
		}

		switch {
		case line == "## design" || strings.HasPrefix(line, "## design "):
			id := strings.TrimSpace(strings.TrimPrefix(line, "## design"))
			if id == "" {
				return Ledger{}, lErr("empty design id")
			}
			if seenDesign[id] {
				return Ledger{}, lErr("duplicate design " + id)
			}
			seenDesign[id] = true
			l.Designs = append(l.Designs, LedgerDesign{ID: id})
			curDesign = &l.Designs[len(l.Designs)-1]
			curMember = nil
			seenMember = map[string]bool{}
			seenField = map[string]bool{}

		case line == "###" || strings.HasPrefix(line, "### "):
			if curDesign == nil {
				return Ledger{}, lErr("member before design")
			}
			mp := strings.TrimSpace(strings.TrimPrefix(line, "###"))
			if mp == "" {
				return Ledger{}, lErr("empty member path")
			}
			if seenMember[mp] {
				return Ledger{}, lErr("duplicate member " + mp)
			}
			seenMember[mp] = true
			curDesign.Members = append(curDesign.Members, LedgerMember{Path: mp})
			curMember = &curDesign.Members[len(curDesign.Members)-1]
			seenField = map[string]bool{}

		case strings.HasPrefix(line, "#"):
			// A leading "# " title before the first design is a tolerated preamble.
			if curDesign == nil && strings.HasPrefix(line, "# ") {
				continue
			}
			return Ledger{}, lErr("unexpected heading: " + line)

		default: // field line or junk
			if curDesign == nil {
				return Ledger{}, lErr("content before first design: " + line)
			}
			if curMember == nil {
				return Ledger{}, lErr("content before first member: " + line)
			}
			idx := strings.Index(line, ":")
			if idx < 0 {
				return Ledger{}, lErr("junk line in block: " + line)
			}
			key := line[:idx]
			if !isLedgerKey(key) {
				return Ledger{}, lErr("unknown key: " + key)
			}
			if seenField[key] {
				continue // first-wins
			}
			seenField[key] = true
			setMemberField(curMember, key, strings.TrimPrefix(line[idx+1:], " "))
		}
	}
	return l, nil
}

var ledgerSettableFields = map[string]bool{
	"spec": true, "last_completed_phase": true, "in_flight": true, "blocked": true,
}

func getMemberField(m *LedgerMember, key string) string {
	switch key {
	case "spec":
		return m.Spec
	case "last_completed_phase":
		return m.LastCompletedPhase
	case "in_flight":
		return m.InFlight
	case "blocked":
		return m.Blocked
	case "updated":
		return m.Updated
	}
	return ""
}

// SetLedgerField idempotently upserts one settable field of a member, stamping
// `updated` via ledgerNow, through the canonical writer. `updated` and unknown
// fields are rejected (nothing written). A same-value set is a byte-identical
// no-op.
func SetLedgerField(path, designID, memberPath, field, value string) error {
	if !ledgerSettableFields[field] {
		return lErr("field not settable: " + field)
	}
	l, err := ParseLedger(path)
	if err != nil {
		return err
	}

	di := -1
	for i := range l.Designs {
		if l.Designs[i].ID == designID {
			di = i
			break
		}
	}
	designExisted := di >= 0
	if !designExisted {
		l.Designs = append(l.Designs, LedgerDesign{ID: designID})
		di = len(l.Designs) - 1
	}
	d := &l.Designs[di]

	mi := -1
	for i := range d.Members {
		if d.Members[i].Path == memberPath {
			mi = i
			break
		}
	}
	memberExisted := mi >= 0
	if !memberExisted {
		d.Members = append(d.Members, LedgerMember{Path: memberPath})
		mi = len(d.Members) - 1
	}
	m := &d.Members[mi]

	if designExisted && memberExisted && getMemberField(m, field) == value {
		return nil // no-op: byte-identical, updated unchanged
	}
	setMemberField(m, field, value)
	m.Updated = ledgerNow().Format("2006-01-02")
	return AtomicWriteFile(path, []byte(serializeLedger(l)), 0o644)
}

// serializeLedger renders the canonical, deterministic ledger.md layout.
func serializeLedger(l Ledger) string {
	var b strings.Builder
	b.WriteString("# Ledger\n\n")
	for _, d := range l.Designs {
		b.WriteString("## design " + d.ID + "\n\n")
		for _, m := range d.Members {
			b.WriteString("### " + m.Path + "\n")
			writeLedgerField(&b, "spec", m.Spec)
			writeLedgerField(&b, "last_completed_phase", m.LastCompletedPhase)
			writeLedgerField(&b, "in_flight", m.InFlight)
			writeLedgerField(&b, "blocked", m.Blocked)
			writeLedgerField(&b, "updated", m.Updated)
			b.WriteString("\n")
		}
	}
	return strings.TrimRight(b.String(), "\n") + "\n"
}

func writeLedgerField(b *strings.Builder, key, val string) {
	if val == "" {
		b.WriteString(key + ":\n")
	} else {
		b.WriteString(key + ": " + val + "\n")
	}
}

// Reconcile aggregates a design's members using the injected status resolver
// (which keys on the member's spec.md frontmatter). It reads the ledger's
// Blocked overlay for the blocked class but NEVER treats the ledger pointer as a
// status. Pure: never errors, and an empty/absent design is vacuously Done.
func Reconcile(ws Ledger, designID string, resolve func(memberRoot, specRef string) (string, bool)) Rollup {
	r := Rollup{DesignID: designID, Done: true}
	var members []LedgerMember
	for _, d := range ws.Designs {
		if d.ID == designID {
			members = d.Members
			break
		}
	}
	for _, m := range members {
		r.Total++
		status, found := resolve(m.Path, m.Spec)
		ms := MemberStatus{Member: m.Path, Spec: m.Spec, Status: status}
		switch {
		case m.Blocked != "" || !found:
			// Blocked wins over a resolved-closed (a stale flag keeps it Blocked).
			ms.Class = "blocked"
			r.Blocked++
			r.Done = false
		case status == "closed" || status == "archived":
			ms.Class = "closed"
			r.Closed++
		default:
			ms.Class = "in-progress"
			r.InProgress++
			r.Done = false
		}
		r.Members = append(r.Members, ms)
	}
	return r
}
