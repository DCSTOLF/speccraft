package speccraft_test

// Tests for SetField clear semantics on active_spec (spec 0012, AC1+AC2).
//
// The e2e assertion at tests/e2e/run.sh:281-282 expects state.json to be in
// a shape such that `jq -r '.active_spec // "null"' state.json` outputs the
// literal string "null" after /speccraft:spec:close. These tests pin that
// contract at the Go layer via a pure-Go replica of jq's `// "null"`
// default — no subprocess dependency on a jq binary in `go test`.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// jqStringNullDefault replicates `jq -r '.<field> // "null"' <file>`:
// returns the field value as a string, OR the literal string "null" if the
// field is absent, JSON null, or JSON false.
func jqStringNullDefault(t *testing.T, raw []byte, field string) string {
	t.Helper()
	var m map[string]json.RawMessage
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	v, ok := m[field]
	if !ok {
		return "null"
	}
	s := string(v)
	if s == "null" || s == "false" {
		return "null"
	}
	var str string
	if err := json.Unmarshal(v, &str); err == nil {
		return str
	}
	return s
}

// activeSpecOnDiskIsCleared returns true iff the active_spec field on disk
// is either absent or JSON null. This is the post-clear shape spec 0012 §What
// item 1 requires. jq's `// "null"` default would coincidentally also fire
// for the literal STRING "null" rendered through `jq -r`, masking the
// pre-fix bug at the bash layer — so the Go test asserts disk shape
// directly to catch that case.
func activeSpecOnDiskIsCleared(t *testing.T, raw []byte) bool {
	t.Helper()
	var m map[string]json.RawMessage
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	v, ok := m["active_spec"]
	if !ok {
		return true
	}
	return string(v) == "null"
}

func setupStateRepo(t *testing.T) string {
	t.Helper()
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	return tmp
}

func readStateJSON(t *testing.T, root string) []byte {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(root, ".speccraft", "state.json"))
	if err != nil {
		t.Fatalf("read state.json: %v", err)
	}
	return raw
}

func Test_SetField_ActiveSpec_NullArg_ClearsToJSONNull(t *testing.T) {
	tmp := setupStateRepo(t)

	// Seed with a real spec id so the clear has something to overwrite.
	if err := speccraft.SetField(tmp, "active_spec", "0011-code-intel"); err != nil {
		t.Fatal(err)
	}

	// Clear via the literal argument shape close.md:45 uses today.
	if err := speccraft.SetField(tmp, "active_spec", "null"); err != nil {
		t.Fatal(err)
	}

	raw := readStateJSON(t, tmp)
	got := jqStringNullDefault(t, raw, "active_spec")
	if got != "null" {
		t.Errorf("after SetField(active_spec, \"null\"): jq output = %q, want %q\nstate.json:\n%s",
			got, "null", raw)
	}
	if !activeSpecOnDiskIsCleared(t, raw) {
		t.Errorf("after SetField(active_spec, \"null\"): disk shape not cleared (active_spec present and not JSON null)\nstate.json:\n%s", raw)
	}
}

func Test_SetField_ActiveSpec_EmptyStringArg_ClearsToJSONNull(t *testing.T) {
	tmp := setupStateRepo(t)

	if err := speccraft.SetField(tmp, "active_spec", "0011-code-intel"); err != nil {
		t.Fatal(err)
	}

	// Clear via empty-string Go argument (no shell layer).
	if err := speccraft.SetField(tmp, "active_spec", ""); err != nil {
		t.Fatal(err)
	}

	raw := readStateJSON(t, tmp)
	got := jqStringNullDefault(t, raw, "active_spec")
	if got != "null" {
		t.Errorf("after SetField(active_spec, \"\"): jq output = %q, want %q\nstate.json:\n%s",
			got, "null", raw)
	}
	if !activeSpecOnDiskIsCleared(t, raw) {
		t.Errorf("after SetField(active_spec, \"\"): disk shape not cleared (active_spec present and not JSON null)\nstate.json:\n%s", raw)
	}
}

func Test_SetField_ActiveSpec_RealSpecId_RoundTrips(t *testing.T) {
	tmp := setupStateRepo(t)

	if err := speccraft.SetField(tmp, "active_spec", "0001-foo"); err != nil {
		t.Fatal(err)
	}

	got, err := speccraft.GetField(tmp, "active_spec")
	if err != nil {
		t.Fatal(err)
	}
	if got != "0001-foo" {
		t.Errorf("after SetField(active_spec, \"0001-foo\"): GetField = %q, want %q", got, "0001-foo")
	}

	// Disk shape sanity: jq returns the literal value, NOT "null".
	raw := readStateJSON(t, tmp)
	if v := jqStringNullDefault(t, raw, "active_spec"); v != "0001-foo" {
		t.Errorf("disk shape regressed: jq output = %q, want %q", v, "0001-foo")
	}
}
