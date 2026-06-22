package speccraft_test

// Tests for the additive PM/Architect state lanes (spec 0022, AC2/AC7).
//
// active_product and active_design are sibling top-level keys added alongside
// active_spec. Each mirrors active_spec's ,omitempty + clear-to-empty
// semantics: SetField(field, "null"|"") drops the key from the serialised
// JSON so `jq -r '.<field> // "null"'` yields the literal "null" when cleared.
// active_spec itself must stay byte-identical (asserted in state_clear_test.go
// and the e2e regression suite); these tests cover only the new lanes.

import (
	"encoding/json"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// fieldOnDiskIsCleared returns true iff the named field on disk is either
// absent or JSON null — the post-clear shape required for an ,omitempty
// string lane. Mirrors activeSpecOnDiskIsCleared (state_clear_test.go) but
// parameterised over the field name for the new lanes.
func fieldOnDiskIsCleared(t *testing.T, raw []byte, field string) bool {
	t.Helper()
	var m map[string]json.RawMessage
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	v, ok := m[field]
	if !ok {
		return true
	}
	return string(v) == "null"
}

func Test_SetField_ActiveProduct_RoundTrips(t *testing.T) {
	tmp := setupStateRepo(t)

	if err := speccraft.SetField(tmp, "active_product", "0001-onboarding"); err != nil {
		t.Fatal(err)
	}

	got, err := speccraft.GetField(tmp, "active_product")
	if err != nil {
		t.Fatal(err)
	}
	if got != "0001-onboarding" {
		t.Errorf("GetField(active_product) = %q, want %q", got, "0001-onboarding")
	}

	raw := readStateJSON(t, tmp)
	if v := jqStringNullDefault(t, raw, "active_product"); v != "0001-onboarding" {
		t.Errorf("disk shape: jq active_product = %q, want %q", v, "0001-onboarding")
	}
}

func Test_SetField_ActiveDesign_RoundTrips(t *testing.T) {
	tmp := setupStateRepo(t)

	if err := speccraft.SetField(tmp, "active_design", "0007-auth-model"); err != nil {
		t.Fatal(err)
	}

	got, err := speccraft.GetField(tmp, "active_design")
	if err != nil {
		t.Fatal(err)
	}
	if got != "0007-auth-model" {
		t.Errorf("GetField(active_design) = %q, want %q", got, "0007-auth-model")
	}

	raw := readStateJSON(t, tmp)
	if v := jqStringNullDefault(t, raw, "active_design"); v != "0007-auth-model" {
		t.Errorf("disk shape: jq active_design = %q, want %q", v, "0007-auth-model")
	}
}

func Test_SetField_ActiveProduct_NullArg_ClearsToOmitempty(t *testing.T) {
	tmp := setupStateRepo(t)

	if err := speccraft.SetField(tmp, "active_product", "0001-onboarding"); err != nil {
		t.Fatal(err)
	}
	if err := speccraft.SetField(tmp, "active_product", "null"); err != nil {
		t.Fatal(err)
	}

	raw := readStateJSON(t, tmp)
	if got := jqStringNullDefault(t, raw, "active_product"); got != "null" {
		t.Errorf("after clear: jq active_product = %q, want %q\nstate.json:\n%s", got, "null", raw)
	}
	if !fieldOnDiskIsCleared(t, raw, "active_product") {
		t.Errorf("after clear: active_product present and not JSON null\nstate.json:\n%s", raw)
	}
}

func Test_SetField_ActiveDesign_EmptyStringArg_ClearsToOmitempty(t *testing.T) {
	tmp := setupStateRepo(t)

	if err := speccraft.SetField(tmp, "active_design", "0007-auth-model"); err != nil {
		t.Fatal(err)
	}
	if err := speccraft.SetField(tmp, "active_design", ""); err != nil {
		t.Fatal(err)
	}

	raw := readStateJSON(t, tmp)
	if got := jqStringNullDefault(t, raw, "active_design"); got != "null" {
		t.Errorf("after clear: jq active_design = %q, want %q\nstate.json:\n%s", got, "null", raw)
	}
	if !fieldOnDiskIsCleared(t, raw, "active_design") {
		t.Errorf("after clear: active_design present and not JSON null\nstate.json:\n%s", raw)
	}
}
