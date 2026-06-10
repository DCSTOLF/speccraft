package speccraft

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

// State is the contents of .speccraft/state.json.
//
// ActiveSpec carries ,omitempty so that clearing the field on close
// (SetField with value "null" or "") produces a state.json that satisfies
// the e2e assertion at tests/e2e/run.sh:281-282 — i.e. `jq -r '.active_spec
// // "null"' state.json` outputs the literal string "null" because the key
// is absent. See spec 0012 AC1/AC2.
type State struct {
	Version    int     `json:"version"`
	ActiveSpec string  `json:"active_spec,omitempty"`
	Session    Session `json:"session"`
}

// Session holds per-session edit tracking (reset on SessionStart).
type Session struct {
	ID              string   `json:"id"`
	EditedTestFiles []string `json:"edited_test_files"`
	EditedProdFiles []string `json:"edited_prod_files"`

	// RustTestBaseline is the set of canonical Rust test IDs known at the
	// most recent baseline-capture point. Used by speccraft-guard to compute
	// the "just-added" set for red-check (spec 0005 AC #8, AC #12).
	// Mutations route exclusively through speccraft-state per AC #8/#12(e).
	RustTestBaseline []string `json:"rust_test_baseline,omitempty"`

	// RustGateFingerprint is the SHA-256 of the crate fingerprint defined
	// in spec 0005 §What.4 — recorded after the last successful pre-edit
	// gate run. Updated only by speccraft-state on cache-miss success.
	RustGateFingerprint string `json:"rust_gate_fingerprint,omitempty"`

	// RustBaselineCaptured records whether initial-capture has ever run
	// against this crate. Distinguishes "baseline empty because we
	// haven't captured" from "baseline empty because no tests existed at
	// capture time" — both have RustTestBaseline=[], only the former
	// should re-trigger initial-capture.
	RustBaselineCaptured bool `json:"rust_baseline_captured,omitempty"`

	// OverridePending grants a one-time bypass of the TDD sibling-test
	// invariant. ConsumeOverride atomically reads and clears it so the
	// bypass fires exactly once per /speccraft:spec:override invocation.
	OverridePending bool `json:"override_pending,omitempty"`
}

var mu sync.Mutex

// LoadState reads state.json from root. Returns a zero State if file absent.
func LoadState(root string) (State, error) {
	mu.Lock()
	defer mu.Unlock()
	return loadStateLocked(root)
}

func loadStateLocked(root string) (State, error) {
	path := StateFile(root)
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return State{Version: 1}, nil
	}
	if err != nil {
		return State{}, err
	}
	var s State
	if err := json.Unmarshal(data, &s); err != nil {
		return State{}, err
	}
	return s, nil
}

// SaveState writes state.json atomically.
func SaveState(root string, s State) error {
	mu.Lock()
	defer mu.Unlock()
	return saveStateLocked(root, s)
}

func saveStateLocked(root string, s State) error {
	path := StateFile(root)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	// Atomic write via temp file.
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// GetField reads a top-level string field from state.json.
func GetField(root, field string) (string, error) {
	s, err := LoadState(root)
	if err != nil {
		return "", err
	}
	switch field {
	case "active_spec":
		return s.ActiveSpec, nil
	case "version":
		return "1", nil
	case "override_pending":
		if s.Session.OverridePending {
			return "true", nil
		}
		return "false", nil
	default:
		return "", nil
	}
}

// SetField sets a top-level string field in state.json.
func SetField(root, field, value string) error {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadStateLocked(root)
	if err != nil {
		return err
	}
	switch field {
	case "active_spec":
		// Treat the literal arg "null" and "" as a clear, so that
		// `speccraft-state set active_spec null` (as instructed by
		// commands/spec/close.md) writes a state.json the e2e
		// assertion at tests/e2e/run.sh:281-282 accepts as cleared.
		// Combined with the ,omitempty tag on ActiveSpec, an empty
		// value drops the key from the serialised JSON entirely.
		// See spec 0012 AC1/AC2.
		if value == "null" {
			value = ""
		}
		s.ActiveSpec = value
	case "override_pending":
		s.Session.OverridePending = (value == "true")
	}
	return saveStateLocked(root, s)
}

// InitState writes the canonical empty state.json shape if no state file
// exists yet, and is a no-op if one is already present. Idempotent so that
// re-running /speccraft:init never silently nukes session state. Spec 0012
// AC4 §What item 3: this is the sanctioned creation path that
// commands/init.md was migrated to, since the new PreToolUse hook blocks
// any direct Edit/Write/MultiEdit/NotebookEdit on .speccraft/state.json.
//
// EditedTestFiles and EditedProdFiles are initialised as empty, non-nil
// slices so that json.MarshalIndent produces "[]" rather than "null",
// matching the literal shape commands/init.md used to inline.
func InitState(root string) error {
	mu.Lock()
	defer mu.Unlock()
	path := StateFile(root)
	if _, err := os.Stat(path); err == nil {
		return nil
	} else if !os.IsNotExist(err) {
		return err
	}
	s := State{
		Version: 1,
		Session: Session{
			EditedTestFiles: []string{},
			EditedProdFiles: []string{},
		},
	}
	return saveStateLocked(root, s)
}

// ConsumeOverride atomically reads and clears the OverridePending flag.
// Returns true exactly once if the flag was set, then clears it on disk so
// the bypass fires for a single guarded edit. Uses a single mu.Lock()
// acquisition to avoid racing with concurrent TrackEdit calls.
func ConsumeOverride(root string) (bool, error) {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadStateLocked(root)
	if err != nil {
		return false, fmt.Errorf("consume override: %w", err)
	}
	was := s.Session.OverridePending
	if was {
		s.Session.OverridePending = false
		if err := saveStateLocked(root, s); err != nil {
			return false, fmt.Errorf("consume override: %w", err)
		}
	}
	return was, nil
}

// GetRustBaseline returns the Rust test baseline list. Empty slice if unset.
func GetRustBaseline(root string) ([]string, error) {
	s, err := LoadState(root)
	if err != nil {
		return nil, err
	}
	if s.Session.RustTestBaseline == nil {
		return []string{}, nil
	}
	return s.Session.RustTestBaseline, nil
}

// SetRustBaseline overwrites the Rust test baseline. Also sets the
// RustBaselineCaptured sentinel so subsequent initial-capture checks
// know capture has occurred (even when ids is empty).
func SetRustBaseline(root string, ids []string) error {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadStateLocked(root)
	if err != nil {
		return err
	}
	s.Session.RustTestBaseline = append([]string(nil), ids...)
	s.Session.RustBaselineCaptured = true
	return saveStateLocked(root, s)
}

// IsRustBaselineCaptured reports whether initial-capture has ever run
// against this crate. Used by CaptureInitialRustBaseline to avoid
// re-capturing when the baseline is empty due to a no-test crate state.
func IsRustBaselineCaptured(root string) (bool, error) {
	s, err := LoadState(root)
	if err != nil {
		return false, err
	}
	return s.Session.RustBaselineCaptured, nil
}

// AppendRustBaseline merges new IDs into the baseline, deduplicating and
// preserving sorted order.
func AppendRustBaseline(root string, ids []string) error {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadStateLocked(root)
	if err != nil {
		return err
	}
	set := map[string]struct{}{}
	for _, v := range s.Session.RustTestBaseline {
		set[v] = struct{}{}
	}
	for _, v := range ids {
		set[v] = struct{}{}
	}
	merged := make([]string, 0, len(set))
	for v := range set {
		merged = append(merged, v)
	}
	sortStrings(merged)
	s.Session.RustTestBaseline = merged
	return saveStateLocked(root, s)
}

// GetRustFingerprint returns the recorded crate fingerprint, or "" if unset.
func GetRustFingerprint(root string) (string, error) {
	s, err := LoadState(root)
	if err != nil {
		return "", err
	}
	return s.Session.RustGateFingerprint, nil
}

// SetRustFingerprint overwrites the recorded crate fingerprint.
func SetRustFingerprint(root, fp string) error {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadStateLocked(root)
	if err != nil {
		return err
	}
	s.Session.RustGateFingerprint = fp
	return saveStateLocked(root, s)
}

// sortStrings sorts a string slice in-place using a simple comparison.
func sortStrings(s []string) {
	for i := 1; i < len(s); i++ {
		for j := i; j > 0 && s[j-1] > s[j]; j-- {
			s[j-1], s[j] = s[j], s[j-1]
		}
	}
}

// TrackEdit records a file edit in the session, deduplicating.
func TrackEdit(root, file string) error {
	if file == "" {
		return nil
	}
	abs, _ := filepath.Abs(file)
	mu.Lock()
	defer mu.Unlock()
	s, err := loadStateLocked(root)
	if err != nil {
		return err
	}
	if IsTestFile(abs) {
		s.Session.EditedTestFiles = dedup(s.Session.EditedTestFiles, abs)
	} else {
		s.Session.EditedProdFiles = dedup(s.Session.EditedProdFiles, abs)
	}
	return saveStateLocked(root, s)
}

// ResetSession clears session.* fields in state.json.
func ResetSession(root string) error {
	mu.Lock()
	defer mu.Unlock()
	s, err := loadStateLocked(root)
	if err != nil {
		return err
	}
	s.Session = Session{}
	return saveStateLocked(root, s)
}

// TasksDonePct returns percentage of completed tasks in the active spec's tasks.md.
func TasksDonePct(root string) (int, error) {
	s, err := LoadState(root)
	if err != nil {
		return 0, err
	}
	if s.ActiveSpec == "" {
		return 0, nil
	}
	tasksFile := filepath.Join(root, "specs", s.ActiveSpec, "tasks.md")
	data, err := os.ReadFile(tasksFile)
	if os.IsNotExist(err) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	total, done := 0, 0
	for _, line := range splitLines(string(data)) {
		if len(line) >= 5 && line[:3] == "- [" {
			total++
			if line[3] == 'x' {
				done++
			}
		}
	}
	if total == 0 {
		return 0, nil
	}
	return done * 100 / total, nil
}

func dedup(slice []string, val string) []string {
	for _, v := range slice {
		if v == val {
			return slice
		}
	}
	return append(slice, val)
}

func splitLines(s string) []string {
	var lines []string
	start := 0
	for i, c := range s {
		if c == '\n' {
			lines = append(lines, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}
