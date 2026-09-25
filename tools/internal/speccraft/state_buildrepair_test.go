package speccraft_test

// Spec 0048 T1 (AC13) — the three new Session keys survive a state round-trip.
//
// WHY THESE ARE WRITTEN AS RAW-JSON ROUND-TRIPS rather than as Go field
// assignments: this file must COMPILE before `Session` has the fields. A test
// that wrote `s.Session.RedBaseline = …` would be a build failure, and per
// spec-0018 AC13 the guard cannot observe a build failure as a RED — it would
// force an override for the very bootstrap step this anchor exists to make free
// (plan §Override budget: budget 1, spent only if this anchor does not carry
// T2). By going through literal JSON and `LoadState`/`SaveState`, the package
// stays compilable and the failure is a genuine RUNTIME one: the unknown keys
// are discarded by `json.Unmarshal` and written away by `SaveState`.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// seedRawState writes a literal state.json under a fresh root and returns the root.
func seedRawState(t *testing.T, raw string) string {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, ".speccraft")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "state.json"), []byte(raw), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

// roundTrip loads and saves through the sanctioned writer, then returns the raw
// bytes on disk. A key that Session does not model is dropped here.
func roundTrip(t *testing.T, root string) []byte {
	t.Helper()
	s, err := speccraft.LoadState(root)
	if err != nil {
		t.Fatalf("LoadState: %v", err)
	}
	if err := speccraft.SaveState(root, s); err != nil {
		t.Fatalf("SaveState: %v", err)
	}
	b, err := os.ReadFile(filepath.Join(root, ".speccraft", "state.json"))
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	return b
}

// sessionKey returns the raw JSON of session.<key>, and whether it was present.
func sessionKey(t *testing.T, raw []byte, key string) (string, bool) {
	t.Helper()
	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		t.Fatalf("unmarshal top: %v\n%s", err, raw)
	}
	sess, ok := top["session"]
	if !ok {
		return "", false
	}
	var inner map[string]json.RawMessage
	if err := json.Unmarshal(sess, &inner); err != nil {
		t.Fatalf("unmarshal session: %v", err)
	}
	v, ok := inner[key]
	return string(v), ok
}

func Test_Session_RedBaseline_SurvivesLoadSaveRoundTrip(t *testing.T) {
	root := seedRawState(t, `{"version":1,"session":{"red_baseline":{"/a/foo_test.go":["TestAlpha"]}}}`)
	got := roundTrip(t, root)
	v, ok := sessionKey(t, got, "red_baseline")
	if !ok {
		t.Fatalf("red_baseline did not survive the round-trip; got %s", got)
	}
	var m map[string][]string
	if err := json.Unmarshal([]byte(v), &m); err != nil {
		t.Fatalf("red_baseline is not map[string][]string: %v (%s)", err, v)
	}
	if ids := m["/a/foo_test.go"]; len(ids) != 1 || ids[0] != "TestAlpha" {
		t.Errorf("red_baseline = %v, want {/a/foo_test.go: [TestAlpha]}", m)
	}
}

func Test_Session_BuildRepairLog_SurvivesLoadSaveRoundTrip(t *testing.T) {
	root := seedRawState(t, `{"version":1,"session":{"build_repair":[`+
		`{"seq":1,"path":"/a/x.go","digest":"abc123","summary":"undefined: foo","at":"2026-08-07T00:00:00Z"}`+
		`]}}`)
	got := roundTrip(t, root)
	v, ok := sessionKey(t, got, "build_repair")
	if !ok {
		t.Fatalf("build_repair did not survive the round-trip; got %s", got)
	}
	var entries []struct {
		Seq     int    `json:"seq"`
		Path    string `json:"path"`
		Digest  string `json:"digest"`
		Summary string `json:"summary"`
		At      string `json:"at"`
	}
	if err := json.Unmarshal([]byte(v), &entries); err != nil {
		t.Fatalf("build_repair is not a list of entries: %v (%s)", err, v)
	}
	if len(entries) != 1 {
		t.Fatalf("build_repair len = %d, want 1", len(entries))
	}
	e := entries[0]
	if e.Seq != 1 || e.Path != "/a/x.go" || e.Digest != "abc123" ||
		e.Summary != "undefined: foo" || e.At != "2026-08-07T00:00:00Z" {
		t.Errorf("build_repair entry lost a field: %+v", e)
	}
}

// Test_Session_BuildRepairLog_PreservesEntryOrder — the log is an append-only
// audit trail and `/speccraft:spec:close` reports it (AC17), so entry ORDER is
// part of the contract, not an accident of serialisation. A round-trip that kept
// the entries but reordered them would still read as "clean" to the three tests
// above, so this is asserted separately.
func Test_Session_BuildRepairLog_PreservesEntryOrder(t *testing.T) {
	root := seedRawState(t, `{"version":1,"session":{"build_repair":[`+
		`{"seq":1,"path":"/a/one.go","digest":"d1","summary":"first","at":"2026-08-07T00:00:01Z"},`+
		`{"seq":2,"path":"/a/two.go","digest":"d2","summary":"second","at":"2026-08-07T00:00:02Z"}`+
		`]}}`)
	got := roundTrip(t, root)
	v, ok := sessionKey(t, got, "build_repair")
	if !ok {
		t.Fatalf("build_repair did not survive the round-trip; got %s", got)
	}
	var entries []struct {
		Seq  int    `json:"seq"`
		Path string `json:"path"`
	}
	if err := json.Unmarshal([]byte(v), &entries); err != nil {
		t.Fatalf("build_repair shape: %v (%s)", err, v)
	}
	if len(entries) != 2 {
		t.Fatalf("build_repair len = %d, want 2", len(entries))
	}
	if entries[0].Seq != 1 || entries[0].Path != "/a/one.go" ||
		entries[1].Seq != 2 || entries[1].Path != "/a/two.go" {
		t.Errorf("entry order not preserved: %+v", entries)
	}
}

// The attestation is `{at, fingerprint}` per plan §Design — audit metadata only,
// gating nothing. Note there is deliberately NO edit counter here: the repair
// budget is enforced against the LENGTH OF THE LOG inside the atomic record op,
// which is the only placement where "recorded before allowed" is race-free. A
// counter on the attestation would be a second, divergeable source of truth.
func Test_Session_BuildRepairAttestation_SurvivesLoadSaveRoundTrip(t *testing.T) {
	root := seedRawState(t, `{"version":1,"session":{"build_repair_attestation":`+
		`{"at":"2026-08-07T00:00:00Z","fingerprint":"deadbeef"}}}`)
	got := roundTrip(t, root)
	v, ok := sessionKey(t, got, "build_repair_attestation")
	if !ok {
		t.Fatalf("build_repair_attestation did not survive the round-trip; got %s", got)
	}
	var att struct {
		At          string `json:"at"`
		Fingerprint string `json:"fingerprint"`
	}
	if err := json.Unmarshal([]byte(v), &att); err != nil {
		t.Fatalf("build_repair_attestation shape: %v (%s)", err, v)
	}
	if att.At != "2026-08-07T00:00:00Z" || att.Fingerprint != "deadbeef" {
		t.Errorf("attestation lost a field: %+v", att)
	}
}

// Test_Session_NewKeys_AreOmittedWhenUnset pins the `,omitempty` half of the
// contract: a state with none of the three set must not grow empty keys, which
// would churn state.json on every unrelated save.
func Test_Session_NewKeys_AreOmittedWhenUnset(t *testing.T) {
	root := seedRawState(t, `{"version":1,"session":{}}`)
	got := roundTrip(t, root)
	for _, key := range []string{"red_baseline", "build_repair", "build_repair_attestation"} {
		if _, ok := sessionKey(t, got, key); ok {
			t.Errorf("%s must be omitted when unset; got %s", key, got)
		}
	}
}
