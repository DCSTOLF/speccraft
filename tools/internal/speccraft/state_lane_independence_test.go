package speccraft_test

// Lane-independence tests (spec 0022, AC6): clearing one active lane must
// never disturb the other two. This is the serialization-layer proof behind
// the Lifecycle "a close NEVER touches another lane" guarantee — pm:close
// clears only active_product, arch:close only active_design, spec:close only
// active_spec.

import (
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func seedAllLanes(t *testing.T, root string) {
	t.Helper()
	if err := speccraft.SetField(root, "active_spec", "0001-spec"); err != nil {
		t.Fatal(err)
	}
	if err := speccraft.SetField(root, "active_product", "0002-brief"); err != nil {
		t.Fatal(err)
	}
	if err := speccraft.SetField(root, "active_design", "0003-design"); err != nil {
		t.Fatal(err)
	}
}

func mustGet(t *testing.T, root, field string) string {
	t.Helper()
	v, err := speccraft.GetField(root, field)
	if err != nil {
		t.Fatal(err)
	}
	return v
}

func Test_LaneIndependence_ClearSpec_PreservesProductAndDesign(t *testing.T) {
	tmp := setupStateRepo(t)
	seedAllLanes(t, tmp)

	if err := speccraft.SetField(tmp, "active_spec", "null"); err != nil {
		t.Fatal(err)
	}

	if got := mustGet(t, tmp, "active_spec"); got != "" {
		t.Errorf("active_spec = %q, want cleared", got)
	}
	if got := mustGet(t, tmp, "active_product"); got != "0002-brief" {
		t.Errorf("active_product = %q, want %q (clobbered by spec clear)", got, "0002-brief")
	}
	if got := mustGet(t, tmp, "active_design"); got != "0003-design" {
		t.Errorf("active_design = %q, want %q (clobbered by spec clear)", got, "0003-design")
	}
}

func Test_LaneIndependence_ClearProduct_PreservesSpecAndDesign(t *testing.T) {
	tmp := setupStateRepo(t)
	seedAllLanes(t, tmp)

	if err := speccraft.SetField(tmp, "active_product", "null"); err != nil {
		t.Fatal(err)
	}

	if got := mustGet(t, tmp, "active_product"); got != "" {
		t.Errorf("active_product = %q, want cleared", got)
	}
	if got := mustGet(t, tmp, "active_spec"); got != "0001-spec" {
		t.Errorf("active_spec = %q, want %q (clobbered by product clear)", got, "0001-spec")
	}
	if got := mustGet(t, tmp, "active_design"); got != "0003-design" {
		t.Errorf("active_design = %q, want %q (clobbered by product clear)", got, "0003-design")
	}
}

func Test_LaneIndependence_ClearDesign_PreservesSpecAndProduct(t *testing.T) {
	tmp := setupStateRepo(t)
	seedAllLanes(t, tmp)

	if err := speccraft.SetField(tmp, "active_design", "null"); err != nil {
		t.Fatal(err)
	}

	if got := mustGet(t, tmp, "active_design"); got != "" {
		t.Errorf("active_design = %q, want cleared", got)
	}
	if got := mustGet(t, tmp, "active_spec"); got != "0001-spec" {
		t.Errorf("active_spec = %q, want %q (clobbered by design clear)", got, "0001-spec")
	}
	if got := mustGet(t, tmp, "active_product"); got != "0002-brief" {
		t.Errorf("active_product = %q, want %q (clobbered by design clear)", got, "0002-brief")
	}
}
