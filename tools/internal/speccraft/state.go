package speccraft

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

// State is the contents of .speccraft/state.json.
type State struct {
	Version    int     `json:"version"`
	ActiveSpec string  `json:"active_spec"`
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
		s.ActiveSpec = value
	}
	return saveStateLocked(root, s)
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
	if s.ActiveSpec == "" || s.ActiveSpec == "null" {
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
