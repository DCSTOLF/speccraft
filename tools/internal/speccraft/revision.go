package speccraft

// Spec 0036 — revision-counter & artifact-numbering contract. This file
// bootstraps the brand-new EXPORTED symbols the contract needs (RevisionState,
// ComputeRevisionState, SetStatus, SetRevision). Per the spec-0018-AC13 new-symbol
// build-failure limitation their first test cannot compile until they exist, so a
// single recorded /speccraft:spec:override introduces them here as minimal stubs.
// Behaviour is filled in test-first across T2+ (each later RED references these
// now-existing symbols and fails at RUNTIME on behaviour, never a build failure).

import (
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// archiveNameRe matches an archived artifact file name spec-r<N>.md /
// review-r<N>.md / plan-r<N>.md / tasks-r<N>.md; a non-numeric -r<x>.md suffix
// simply does not match (ignored, not an error). spec-r<N>.md is scanned only
// defensively for out-of-band files — this contract never archives spec.md.
var archiveNameRe = regexp.MustCompile(`^(?:spec|review|plan|tasks)-r(\d+)\.md$`)

// frontmatterDoc is the parsed result of parseFrontmatterBlock (the AC13 shared
// grammar entrypoint). T2 minimal: block presence + the raw in-block lines with
// trailing CR stripped for matching. Byte offsets / per-line terminators for the
// writer are added test-first in later tasks.
type frontmatterDoc struct {
	found bool     // a complete `---`…`---` block exists
	lines []string // lines strictly inside the block (trailing CR stripped)
}

// parseFrontmatterBlock is the SINGLE shared frontmatter grammar entrypoint
// (AC13): reader and writer both route through it so a check and a write can
// never disagree. The block is delimited by the first line equal to `---` and the
// next line equal to `---` (trailing CR tolerated for mixed-EOL); only lines
// strictly inside are returned. No closing fence ⇒ not found.
func parseFrontmatterBlock(b []byte) frontmatterDoc {
	lines := strings.Split(string(b), "\n")
	if len(lines) == 0 {
		return frontmatterDoc{found: false}
	}
	trim := func(x string) string { return strings.TrimRight(x, "\r") }
	// A leading UTF-8 BOM on the opening delimiter is tolerated (AC13); the writer
	// preserves it (AC6) since it operates on raw bytes.
	if strings.TrimPrefix(trim(lines[0]), "\ufeff") != "---" {
		return frontmatterDoc{found: false}
	}
	for i := 1; i < len(lines); i++ {
		if trim(lines[i]) == "---" {
			inner := make([]string, 0, i-1)
			for j := 1; j < i; j++ {
				inner = append(inner, trim(lines[j]))
			}
			return frontmatterDoc{found: true, lines: inner}
		}
	}
	return frontmatterDoc{found: false}
}

// frontmatterValue returns the trimmed value of the first column-0 `<key>:` line
// inside the frontmatter block (AC7 first-wins; body occurrences and `# key:`
// comments do not match because they are not a column-0 `<key>:` prefix).
func frontmatterValue(b []byte, key string) (string, bool) {
	doc := parseFrontmatterBlock(b)
	prefix := key + ":"
	for _, ln := range doc.lines {
		if strings.HasPrefix(ln, prefix) {
			return strings.TrimSpace(ln[len(prefix):]), true
		}
	}
	return "", false
}

// listArchivedOrdinals scans specDir for archived-artifact ordinals across all
// kinds (AC1). Non-numeric -r<x>.md suffixes are ignored, not errors.
func listArchivedOrdinals(specDir string) ([]uint64, error) {
	entries, err := os.ReadDir(specDir)
	if err != nil {
		return nil, err
	}
	var ords []uint64
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		m := archiveNameRe.FindStringSubmatch(e.Name())
		if m == nil {
			continue
		}
		n, err := strconv.ParseUint(m[1], 10, 64)
		if err != nil {
			continue // overflowing/oversized ordinal suffix ignored by the scan
		}
		ords = append(ords, n)
	}
	return ords, nil
}

// RevisionState is the reconciled revision view of a spec dir (spec 0036 AC1).
// Effective is the canonical live revision:
//
//	Effective = HasArchived ? max(FrontmatterRevision, MaxArchived+1) : FrontmatterRevision
//
// which is >= FrontmatterRevision and, by construction, strictly greater than
// every archived ordinal whenever HasArchived (the Authority-model invariant).
type RevisionState struct {
	FrontmatterRevision uint64
	MaxArchived         uint64
	Effective           uint64
	HasArchived         bool
}

// parseRevisionValue reads the frontmatter revision: value per the AC1/AC14
// classification matrix: absent or syntactically non-numeric ⇒ 0 (no error); a
// numeric (all-ASCII-digit) literal that overflows uint64 ⇒ error (held distinct
// from malformed).
func parseRevisionValue(specBytes []byte) (uint64, error) {
	v, ok := frontmatterValue(specBytes, "revision")
	if !ok || v == "" {
		return 0, nil
	}
	n, perr := strconv.ParseUint(v, 10, 64)
	if perr == nil {
		return n, nil
	}
	if isAllDigits(v) {
		return 0, perr // reuse strconv's range error; over-domain ≠ malformed
	}
	return 0, nil // non-numeric ⇒ 0
}

// isAllDigits reports whether s is a non-empty run of ASCII digits.
func isAllDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// ComputeRevisionState reconciles <specDir>/spec.md's revision: counter against
// the on-disk *-r<N>.md archive ordinals (spec 0036 AC1). Effective heals the
// counter forward only: max(fmRev, maxArchived+1) when archives exist, else fmRev.
func ComputeRevisionState(specDir string) (RevisionState, error) {
	specBytes, err := os.ReadFile(filepath.Join(specDir, "spec.md"))
	if err != nil {
		return RevisionState{}, err
	}
	fmRev, err := parseRevisionValue(specBytes)
	if err != nil {
		return RevisionState{}, err
	}
	ords, err := listArchivedOrdinals(specDir)
	if err != nil {
		return RevisionState{}, err
	}
	st := RevisionState{FrontmatterRevision: fmRev, Effective: fmRev}
	for _, o := range ords {
		st.HasArchived = true
		if o > st.MaxArchived {
			st.MaxArchived = o
		}
	}
	if st.HasArchived && st.MaxArchived+1 > st.Effective {
		st.Effective = st.MaxArchived + 1
	}
	return st, nil
}

// revErr is a lightweight string error so this file needs no fmt/errors import
// (keeping guard-gated edits free of the unused-import two-step).
type revErr string

func (e revErr) Error() string { return string(e) }

// validStatuses is the allowed set for SetStatus (AC8).
var validStatuses = map[string]bool{
	"draft": true, "reviewed": true, "planned": true,
	"in-progress": true, "blocked": true, "closed": true,
}

// rawLine is one source line split into its text (terminator stripped) and its
// own terminator ("\n", "\r\n", or "" for a final line with no newline), so the
// writer can preserve each line's own EOL byte-for-byte (AC6, mixed-EOL safe).
type rawLine struct{ text, term string }

func splitRawLines(s string) []rawLine {
	var out []rawLine
	for i := 0; i < len(s); {
		j := strings.IndexByte(s[i:], '\n')
		if j < 0 {
			out = append(out, rawLine{text: s[i:], term: ""})
			break
		}
		text, term := s[i:i+j], "\n"
		if strings.HasSuffix(text, "\r") {
			text, term = text[:len(text)-1], "\r\n"
		}
		out = append(out, rawLine{text: text, term: term})
		i += j + 1
	}
	return out
}

func joinRawLines(ls []rawLine) string {
	var b strings.Builder
	for _, l := range ls {
		b.WriteString(l.text)
		b.WriteString(l.term)
	}
	return b.String()
}

// setFrontmatterField is the unexported, byte-safe writer behind SetStatus /
// SetRevision (AC6/AC7). It rewrites the FIRST column-0 `<key>:` line inside the
// frontmatter block (later duplicates untouched), preserving every other byte —
// field order, body, per-line terminators, a leading BOM, the EOF newline — and
// never writes a .bak sibling. When the key is absent it inserts a line before
// the closing `---`, inheriting the terminator of the line above it. Setting a
// field to its current value is a skip-write no-op. A file with no frontmatter
// block is an error (never a silent body edit).
func setFrontmatterField(specMd, key, value string) error {
	b, err := os.ReadFile(specMd)
	if err != nil {
		return err
	}
	if !parseFrontmatterBlock(b).found {
		return revErr("setFrontmatterField: " + specMd + " has no frontmatter block")
	}
	lines := splitRawLines(string(b))
	openIdx := -1
	for i, l := range lines {
		if strings.TrimPrefix(l.text, "\ufeff") == "---" {
			openIdx = i
			break
		}
	}
	closeIdx := -1
	for i := openIdx + 1; i < len(lines); i++ {
		if lines[i].text == "---" {
			closeIdx = i
			break
		}
	}
	newText := key + ": " + value
	keyIdx := -1
	prefix := key + ":"
	for i := openIdx + 1; i < closeIdx; i++ {
		if strings.HasPrefix(lines[i].text, prefix) {
			keyIdx = i
			break
		}
	}
	if keyIdx >= 0 {
		lines[keyIdx].text = newText // keep this line's own terminator
	} else {
		term := lines[closeIdx].term // empty-block fallback: closing --- terminator
		if closeIdx-1 > openIdx {
			term = lines[closeIdx-1].term // inherit the line above the closing ---
		}
		ins := rawLine{text: newText, term: term}
		lines = append(lines[:closeIdx:closeIdx], append([]rawLine{ins}, lines[closeIdx:]...)...)
	}
	out := joinRawLines(lines)
	if out == string(b) {
		return nil // skip-write: byte-identical, no rewrite, no mtime churn
	}
	return AtomicWriteFile(specMd, []byte(out), 0o644)
}

// currentStatusClosed reports whether specMd's current status: is well-formed
// "closed". A malformed/absent status reads as not-closed (AC9 leniency).
func currentStatusClosed(specMd string) (bool, error) {
	b, err := os.ReadFile(specMd)
	if err != nil {
		return false, err
	}
	v, ok := frontmatterValue(b, "status")
	return ok && v == "closed", nil
}

// SetStatus is the sanctioned writer for the status: frontmatter field: it
// validates the value (AC8) and refuses an already-closed spec (AC9) before
// delegating to the byte-safe writer.
func SetStatus(specMd, status string) error {
	if !validStatuses[status] {
		return revErr("SetStatus: invalid status " + status)
	}
	closed, err := currentStatusClosed(specMd)
	if err != nil {
		return err
	}
	if closed {
		return revErr("SetStatus: " + specMd + " is closed; corrections go in a follow-up spec")
	}
	return setFrontmatterField(specMd, "status", status)
}

// SetRevision is the sanctioned, monotonic-forward writer for the revision:
// frontmatter field: it refuses an already-closed spec (AC9) and any demotion
// below the current counter (§C); the uint64 arg type bounds the domain (AC14).
func SetRevision(specMd string, n uint64) error {
	closed, err := currentStatusClosed(specMd)
	if err != nil {
		return err
	}
	if closed {
		return revErr("SetRevision: " + specMd + " is closed; corrections go in a follow-up spec")
	}
	b, err := os.ReadFile(specMd)
	if err != nil {
		return err
	}
	cur, err := parseRevisionValue(b)
	if err != nil {
		return err
	}
	if n < cur {
		return revErr("SetRevision: refusing to demote revision " +
			strconv.FormatUint(cur, 10) + "→" + strconv.FormatUint(n, 10) + " (monotonic-forward)")
	}
	return setFrontmatterField(specMd, "revision", strconv.FormatUint(n, 10))
}
