package speccraft

// Spec 0048 — build-repair mode and the red-candidate baseline.
//
// Two defects motivate this file, both in the spec-0018 red-check path:
//
//   A. A broken build makes the guard forbid its own repair. `OutcomeBuildFailed`
//      blocks the edit, so when the break is in PRODUCTION code every later
//      production edit in that package is refused — including the one that fixes
//      it. Spec 0047 stated an override budget of 0 and spent 5 on exactly this.
//   B. An edit to a test file that adds no new `func Test…` resets that file's
//      registered red candidates to `[]`, blocking a legitimately-RED production
//      edit. This one fired live while implementing spec 0049, and again while
//      implementing THIS spec.
//
// This file holds the STATE layer for both: a per-file `red_baseline` captured
// first-touch-only so a later no-new-test edit cannot shrink the candidate set,
// and an append-only `build_repair` log plus an attestation recording that
// repair mode was entered.
//
// BOUNDARY: everything here is state arithmetic under the `state.json`
// single-writer rule. The decision to ENTER repair mode — the build probe — lives
// in the guard's cmd package, where it can be fault-injected.

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// buildRepairMaxEdits bounds how many edits one session may make while the build
// is broken. It stays UNEXPORTED and lives here, not in the guard, because the
// cap must be enforced INSIDE the atomic record operation — that is the only
// placement where "recorded before allowed" is race-free. AC18's test reads the
// compiled value from an internal test file rather than a policy constant being
// exported for its benefit.
const (
	buildRepairMaxEdits    = 10
	buildRepairSummaryCap  = 4 << 10 // 4 KiB of error text kept in the log
	buildRepairTruncMarker = "\n…[truncated]"
)

// ErrBuildRepairBudgetExhausted is returned once the log already holds
// buildRepairMaxEdits entries. The guard maps it to the user-facing message that
// names /speccraft:spec:override, so the operator gets a way forward rather than
// a wall.
var ErrBuildRepairBudgetExhausted = errors.New("build-repair budget exhausted")

// BuildRepairEntry is one recorded edit made while the build was broken.
// Digest is the sha256 of the FULL pre-truncation error bytes, so truncating
// Summary for readability never weakens the audit trail.
type BuildRepairEntry struct {
	Seq     int    `json:"seq"`
	Path    string `json:"path"`
	Digest  string `json:"digest"`
	Summary string `json:"summary"`
	At      string `json:"at"`
}

// BuildRepairAttestation records that repair mode is currently open. It is audit
// metadata and gates nothing — deliberately carrying no edit counter, because the
// budget is derived from the log's length and a second counter could diverge
// from it.
type BuildRepairAttestation struct {
	At          string `json:"at"`
	Fingerprint string `json:"fingerprint"`
}

// BuildRepairState is the read shape for the attestation plus the log.
type BuildRepairState struct {
	Attestation *BuildRepairAttestation
	Log         []BuildRepairEntry
}

// NormalizeStateKey is the single canonical path normalizer for every state key
// this package writes (AC15). One shared function, because two normalizers that
// disagree produce two keys for one file — which is how a baseline gets lost.
//
// It must tolerate a file created in-session and therefore absent from disk, so
// symlink resolution is applied to the deepest EXISTING ancestor and the
// non-existent tail is rejoined.
func NormalizeStateKey(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return filepath.Clean(path)
	}
	// Walk up to the deepest ancestor that exists, remembering the tail.
	dir := abs
	var tail []string
	for {
		if _, err := os.Lstat(dir); err == nil {
			break
		}
		parent := filepath.Dir(dir)
		if parent == dir { // reached the root without finding anything
			return filepath.Clean(abs)
		}
		tail = append([]string{filepath.Base(dir)}, tail...)
		dir = parent
	}
	resolved, err := filepath.EvalSymlinks(dir)
	if err != nil {
		resolved = dir
	}
	return filepath.Clean(filepath.Join(append([]string{resolved}, tail...)...))
}

// CaptureRedCandidates is spec 0048 §B's one atomic operation, and the fix for
// defect B.
//
// baseline[file] is set from preIDs IFF ABSENT — first touch only. Candidates are
// then recomputed as postIDs minus that baseline. Because the baseline is never
// rewritten, a later edit that adds no new test recomputes the SAME candidate set
// instead of clearing it, while a genuine deletion still shrinks it.
//
// The whole read-modify-write happens under one lock and one save, following
// SetRedCandidates / ConsumeOverride: a partial write here would leave a baseline
// with no candidates, which reads as "this file never had a red test".
func CaptureRedCandidates(root, file string, preIDs, postIDs []string) ([]string, error) {
	key := NormalizeStateKey(file)

	mu.Lock()
	defer mu.Unlock()
	s, err := loadStateLocked(root)
	if err != nil {
		return nil, err
	}
	if s.Session.RedBaseline == nil {
		s.Session.RedBaseline = map[string][]string{}
	}
	if s.Session.RedCandidates == nil {
		s.Session.RedCandidates = map[string][]string{}
	}

	// First touch only. `_, ok :=` rather than a length check: a file whose
	// baseline is legitimately EMPTY (a brand-new test file) has been touched,
	// and re-deriving its baseline on the next edit would reintroduce defect B.
	if _, ok := s.Session.RedBaseline[key]; !ok {
		s.Session.RedBaseline[key] = dedupeIDs(preIDs)
	}
	baseline := s.Session.RedBaseline[key]

	candidates := subtractIDs(dedupeIDs(postIDs), baseline)
	s.Session.RedCandidates[key] = candidates

	// One save for both halves. A partial write would leave a baseline with no
	// candidates, which reads as "this file never had a red test".
	if err := saveStateLocked(root, s); err != nil {
		return nil, err
	}
	return candidates, nil
}

// dedupeIDs preserves first-seen order so the recorded sets stay diffable.
func dedupeIDs(ids []string) []string {
	seen := make(map[string]struct{}, len(ids))
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}

// subtractIDs returns ids − exclude, order-preserving.
func subtractIDs(ids, exclude []string) []string {
	drop := make(map[string]struct{}, len(exclude))
	for _, e := range exclude {
		drop[e] = struct{}{}
	}
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		if _, ok := drop[id]; ok {
			continue
		}
		out = append(out, id)
	}
	return out
}

// GetRedBaseline reads the per-file baseline. It is the oracle for AC13's
// "a later touch does not rewrite the baseline".
func GetRedBaseline(root string) (map[string][]string, error) {
	s, err := LoadState(root)
	if err != nil {
		return nil, err
	}
	if s.Session.RedBaseline == nil {
		return map[string][]string{}, nil
	}
	return s.Session.RedBaseline, nil
}

// RecordBuildRepair appends one entry to the build-repair log, opening the
// attestation if this is the first entry, and enforces the cap.
//
// Order is load-bearing: the entry is RECORDED before the guard allows the edit,
// so an allowed-but-unlogged edit is impossible. Returns
// ErrBuildRepairBudgetExhausted when the log already holds buildRepairMaxEdits.
func RecordBuildRepair(root, file, errText string) (BuildRepairEntry, error) {
	key := NormalizeStateKey(file)
	digest := buildRepairDigest(errText)

	mu.Lock()
	defer mu.Unlock()
	s, err := loadStateLocked(root)
	if err != nil {
		return BuildRepairEntry{}, err
	}

	// The cap is checked INSIDE the lock, before the append. Checking it outside
	// would let two concurrent guard invocations each see 9 entries and both
	// append, admitting an 11th edit against a bound of 10.
	if len(s.Session.BuildRepair) >= buildRepairMaxEdits {
		return BuildRepairEntry{}, buildRepairBudgetError()
	}

	now := buildRepairNow()
	// The attestation opens on the FIRST entry of a repair run. It reopens after
	// a clean probe closed it, but the log — and therefore the budget — carries
	// across, so reopening refunds nothing.
	if s.Session.BuildRepairAttestation == nil {
		s.Session.BuildRepairAttestation = &BuildRepairAttestation{At: now, Fingerprint: digest}
	}

	entry := BuildRepairEntry{
		Seq:     len(s.Session.BuildRepair) + 1,
		Path:    key,
		Digest:  digest,
		Summary: buildRepairSummary(errText),
		At:      now,
	}
	s.Session.BuildRepair = append(s.Session.BuildRepair, entry)

	// One save for the attestation and the entry together. A partial write could
	// leave an open attestation with no entry — an admitted edit with no audit
	// row, which is the one outcome "record before allow" exists to prevent.
	if err := saveStateLocked(root, s); err != nil {
		return BuildRepairEntry{}, err
	}
	return entry, nil
}

// ClearBuildRepairAttestation ends repair mode after a clean probe. It clears the
// attestation and NEVER the log: the log is the session's audit trail and is
// cleared only by ResetSession, so a clean probe cannot refund spent budget.
func ClearBuildRepairAttestation(root string) error {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadStateLocked(root)
	if err != nil {
		return err
	}
	if s.Session.BuildRepairAttestation == nil {
		return nil // idempotent: closing an already-closed run is not an error
	}
	s.Session.BuildRepairAttestation = nil
	return saveStateLocked(root, s)
}

// GetBuildRepair reads the attestation and log, for tests and for
// `speccraft-state build-repair-log`.
func GetBuildRepair(root string) (BuildRepairState, error) {
	s, err := LoadState(root)
	if err != nil {
		return BuildRepairState{}, err
	}
	return BuildRepairState{
		Attestation: s.Session.BuildRepairAttestation,
		Log:         s.Session.BuildRepair,
	}, nil
}

// buildRepairDigest is the sha256 hex of the full error bytes, computed before
// any truncation.
func buildRepairDigest(errText string) string {
	sum := sha256.Sum256([]byte(errText))
	return hex.EncodeToString(sum[:])
}

// buildRepairSummary caps the stored error text and makes the truncation VISIBLE,
// so a reader never mistakes a clipped message for the whole failure.
func buildRepairSummary(errText string) string {
	if len(errText) <= buildRepairSummaryCap {
		return errText
	}
	return errText[:buildRepairSummaryCap] + buildRepairTruncMarker
}

// buildRepairNow is the timestamp format shared by the entry and the attestation.
func buildRepairNow() string {
	return time.Now().UTC().Format(time.RFC3339)
}

// buildRepairBudgetError renders the sentinel with the cap named, so the guard's
// message can state the bound without importing the constant.
func buildRepairBudgetError() error {
	return fmt.Errorf("%w: %d edits already recorded this session", ErrBuildRepairBudgetExhausted, buildRepairMaxEdits)
}
