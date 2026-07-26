package speccraft

// Spec 0035 — diff-focused re-review. This file bootstraps the brand-new
// exported symbols the review-diff / review-snapshot path needs. They start as
// minimal zero-value stubs (the spec-0018-AC13 new-symbol build-failure
// limitation means their first test cannot compile until they exist, so a single
// recorded /speccraft:spec:override introduces them here). Every subsequent RED
// references these now-existing symbols and fails at RUNTIME on behaviour, or
// drives the compile-stable speccraft-state run() seam.
//
// Behaviour is filled in test-first across P1–P3:
//   - AtomicWriteFile      (T3)
//   - WriteReviewSnapshot  (T5)
//   - ReviewDiff envelope  (T9), --promote (T11), changed_sections (T17)
//   - WriteReviewFile       (T15)

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
)

// atomicRename is a package-level seam so fault-injection tests (AC2) can force
// a rename failure and assert the prior target file is left byte-unchanged.
var (
	atomicRename = os.Rename
)

// ChangedSection is one structured anchor in a ReviewEnvelope.ChangedSections
// list (spec 0035 Anchor scheme). Kind is "section" | "frontmatter" | "preamble";
// Heading/Ordinal are meaningful only for Kind=="section"; Side is
// "added" | "removed" | "modified".
type ChangedSection struct {
	Kind    string `json:"kind"`
	Heading string `json:"heading,omitempty"`
	Ordinal int    `json:"ordinal,omitempty"`
	Side    string `json:"side"`
}

// ReviewEnvelope is the versioned JSON envelope emitted by `speccraft-state
// review-diff` (spec 0035 AC3). BaseFingerprint is a pointer so it can serialise
// as JSON null on the first-review (no-prior-snapshot) case.
type ReviewEnvelope struct {
	Schema          int              `json:"schema"`
	Snapshot        bool             `json:"snapshot"`
	Changed         bool             `json:"changed"`
	ChangedSections []ChangedSection `json:"changed_sections"`
	Diff            string           `json:"diff"`
	Fingerprint     string           `json:"fingerprint"`
	BaseFingerprint *string          `json:"base_fingerprint"`
}

// AtomicWriteFile writes data to path atomically: it writes a same-directory
// temp file (path+".tmp", so the rename is a true atomic swap on one filesystem,
// never a cross-device copy), then renames it over path. On any failure before
// the rename, path is left byte-unchanged and the temp file is cleaned up. This
// is the shared seam behind the review-snapshot write (AC1) and the review.md
// atomic commit (AC2); it mirrors the existing state.json write path.
func AtomicWriteFile(path string, data []byte, perm os.FileMode) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, perm); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	if err := atomicRename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

// WriteReviewSnapshot copies <specDir>/spec.md to <specDir>/review-snapshot.md
// and returns the sha256 (hex) of the RAW spec.md bytes — no CRLF/LF, BOM, or
// trailing-newline normalization (spec 0035 AC1). It is a true no-op when the
// on-disk snapshot is already byte-identical: it does not rewrite the file or
// touch its mtime, and returns the same fingerprint. A missing/unreadable
// spec.md is an error.
func WriteReviewSnapshot(specDir string) (fingerprint string, err error) {
	specBytes, err := os.ReadFile(filepath.Join(specDir, "spec.md"))
	if err != nil {
		return "", err
	}
	fingerprint = fingerprintBytes(specBytes)
	snapPath := filepath.Join(specDir, "review-snapshot.md")
	if prior, err := os.ReadFile(snapPath); err == nil && bytes.Equal(prior, specBytes) {
		// Byte-identical snapshot already on disk: no rewrite, no mtime touch.
		return fingerprint, nil
	}
	if err := AtomicWriteFile(snapPath, specBytes, 0o644); err != nil {
		return "", err
	}
	return fingerprint, nil
}

// fingerprintBytes is the shared sha256(hex) fingerprint over raw bytes used for
// both the snapshot fingerprint (AC1) and reviewed_sha256 (AC2).
func fingerprintBytes(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

// ReviewDiff reads <specDir>/spec.md ONCE, compares it against the prior
// review-snapshot.md, and returns the versioned envelope (spec 0035
// AC3/AC4/AC5/AC6). fingerprint is the sha256 of the CURRENT spec bytes;
// base_fingerprint is the sha256 of the OLD snapshot (captured before any
// promote), or nil when there is no prior snapshot. With promote, the same
// captured bytes are written as the new snapshot AFTER the envelope is computed
// (read-before-overwrite; AC11). An unreadable spec.md is an error; an
// unreadable-but-present snapshot is also an error (distinct from absent).
func ReviewDiff(specDir string, promote bool) (ReviewEnvelope, error) {
	specBytes, err := os.ReadFile(filepath.Join(specDir, "spec.md"))
	if err != nil {
		return ReviewEnvelope{}, err
	}
	env := ReviewEnvelope{
		Schema:          1,
		Fingerprint:     fingerprintBytes(specBytes),
		ChangedSections: []ChangedSection{},
	}
	snapPath := filepath.Join(specDir, "review-snapshot.md")
	snapBytes, serr := os.ReadFile(snapPath)
	switch {
	case serr == nil:
		env.Snapshot = true
		base := fingerprintBytes(snapBytes)
		env.BaseFingerprint = &base
		if !bytes.Equal(snapBytes, specBytes) {
			env.Changed = true
			env.Diff, env.ChangedSections = diffSections(snapBytes, specBytes)
		}
	case os.IsNotExist(serr):
		// No prior snapshot: resolvable first-review state.
		env.Snapshot = false
		env.BaseFingerprint = nil
	default:
		// Snapshot present but unreadable (truncation/permissions): unresolvable.
		return ReviewEnvelope{}, serr
	}
	if promote {
		if err := AtomicWriteFile(snapPath, specBytes, 0o644); err != nil {
			return ReviewEnvelope{}, err
		}
	}
	return env, nil
}

// diffSections is the changed_sections determinism engine (spec 0035 AC5). It is
// a pure function of (old bytes, new bytes): sections are matched by
// (heading, ordinal) independently per document; a matched pair is emitted only
// when its body bytes differ (side:modified), and an occurrence present on only
// one side is emitted as added (new-doc ordinal) or removed (old-doc ordinal). A
// byte-identical body is NEVER emitted, even under an ordinal shift; there is no
// blanket over-report. Frontmatter/preamble changes are their own reserved kinds.
func diffSections(oldBytes, newBytes []byte) (string, []ChangedSection) {
	oldDoc := parseSpecDoc(string(oldBytes))
	newDoc := parseSpecDoc(string(newBytes))

	type skey struct {
		h string
		o int
	}
	oldBody := make(map[skey]string, len(oldDoc.sections))
	for _, s := range oldDoc.sections {
		oldBody[skey{s.heading, s.ordinal}] = s.body
	}
	newSeen := make(map[skey]bool, len(newDoc.sections))
	for _, s := range newDoc.sections {
		newSeen[skey{s.heading, s.ordinal}] = true
	}

	var out []ChangedSection
	if oldDoc.frontmatter != newDoc.frontmatter {
		out = append(out, ChangedSection{Kind: "frontmatter", Side: "modified"})
	}
	if oldDoc.preamble != newDoc.preamble {
		out = append(out, ChangedSection{Kind: "preamble", Side: "modified"})
	}
	// new-side pass: added + modified, in new-document order.
	for _, s := range newDoc.sections {
		k := skey{s.heading, s.ordinal}
		if body, ok := oldBody[k]; ok {
			if body != s.body {
				out = append(out, ChangedSection{Kind: "section", Heading: s.heading, Ordinal: s.ordinal, Side: "modified"})
			}
		} else {
			out = append(out, ChangedSection{Kind: "section", Heading: s.heading, Ordinal: s.ordinal, Side: "added"})
		}
	}
	// old-side pass: removed, in old-document order.
	for _, s := range oldDoc.sections {
		if !newSeen[skey{s.heading, s.ordinal}] {
			out = append(out, ChangedSection{Kind: "section", Heading: s.heading, Ordinal: s.ordinal, Side: "removed"})
		}
	}
	if len(out) == 0 {
		return "", []ChangedSection{}
	}
	return renderDiff(out), out
}

// WriteReviewFile commits review.md at path as a SINGLE atomic operation
// (spec 0035 AC2): it constructs the complete file — the review body with any
// pre-existing reviewed_sha256 lines stripped and exactly one canonical
// `reviewed_sha256: <fingerprint>` line appended — then writes it via
// AtomicWriteFile (same-dir temp + rename). There is never an intermediate
// fingerprint-free write; on any failure before the rename the prior review.md is
// left byte-unchanged.
func WriteReviewFile(path string, body []byte, fingerprint string) error {
	var b strings.Builder
	for _, ln := range strings.Split(string(body), "\n") {
		if strings.HasPrefix(strings.TrimSpace(ln), "reviewed_sha256:") {
			continue // strip any prior fingerprint line
		}
		b.WriteString(ln)
		b.WriteByte('\n')
	}
	content := strings.TrimRight(b.String(), "\n")
	if content != "" {
		content += "\n"
	}
	content += "reviewed_sha256: " + fingerprint + "\n"
	return AtomicWriteFile(path, []byte(content), 0o644)
}
