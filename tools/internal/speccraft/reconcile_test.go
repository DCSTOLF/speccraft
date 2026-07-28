package speccraft_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func mkLedger(designs ...speccraft.LedgerDesign) speccraft.Ledger {
	return speccraft.Ledger{Designs: designs}
}

// AC4: reconcile reports the RESOLVER's status, never the ledger pointer.
func Test_Reconcile_KeysOnResolver_NotLastCompletedPhase(t *testing.T) {
	l := mkLedger(speccraft.LedgerDesign{ID: "k", Members: []speccraft.LedgerMember{
		{Path: "./m", Spec: "s1", LastCompletedPhase: "closed"}, // a status-looking pointer value
	}})
	resolve := func(_, spec string) (string, bool) { return "draft", true } // authoritative says draft
	r := speccraft.Reconcile(l, "k", resolve)
	if len(r.Members) != 1 {
		t.Fatalf("members = %+v", r.Members)
	}
	if r.Members[0].Status != "draft" || r.Members[0].Class != "in-progress" || r.Done {
		t.Errorf("member=%+v Done=%v; want status=draft class=in-progress Done=false", r.Members[0], r.Done)
	}
}

// AC5: classification + precedence.
func Test_Reconcile_Classification_Table(t *testing.T) {
	l := mkLedger(speccraft.LedgerDesign{ID: "d", Members: []speccraft.LedgerMember{
		{Path: "./a", Spec: "closedspec"},
		{Path: "./b", Spec: "archspec"},
		{Path: "./c", Spec: "draftspec"},
		{Path: "./d", Spec: "gonespec"},                    // resolver not-found
		{Path: "./e", Spec: "closedspec", Blocked: "RED"},  // blocked overlay wins over resolved-closed
	}})
	resolve := func(_, spec string) (string, bool) {
		switch spec {
		case "closedspec":
			return "closed", true
		case "archspec":
			return "archived", true
		case "draftspec":
			return "draft", true
		default:
			return "", false
		}
	}
	r := speccraft.Reconcile(l, "d", resolve)
	wantClass := []string{"closed", "closed", "in-progress", "blocked", "blocked"}
	if len(r.Members) != len(wantClass) {
		t.Fatalf("members = %d, want %d", len(r.Members), len(wantClass))
	}
	for i, wc := range wantClass {
		if r.Members[i].Class != wc {
			t.Errorf("member[%d] %s: class=%q, want %q", i, r.Members[i].Member, r.Members[i].Class, wc)
		}
	}
	if r.Total != 5 || r.Closed != 2 || r.Blocked != 2 || r.InProgress != 1 {
		t.Errorf("counts = {T%d C%d B%d I%d}, want {T5 C2 B2 I1}", r.Total, r.Closed, r.Blocked, r.InProgress)
	}
	if r.Done {
		t.Error("Done must be false (not all Closed)")
	}
}

func Test_Reconcile_AllClosed_DoneTrue(t *testing.T) {
	l := mkLedger(speccraft.LedgerDesign{ID: "d", Members: []speccraft.LedgerMember{
		{Path: "./a", Spec: "x"}, {Path: "./b", Spec: "y"},
	}})
	resolve := func(_, spec string) (string, bool) {
		if spec == "y" {
			return "archived", true
		}
		return "closed", true
	}
	r := speccraft.Reconcile(l, "d", resolve)
	if !r.Done || r.Closed != 2 || r.Total != 2 {
		t.Errorf("rollup = %+v; want Done, Closed 2/Total 2", r)
	}
}

func Test_Reconcile_EmptyOrAbsentDesign_DoneTrue(t *testing.T) {
	empty := speccraft.Reconcile(mkLedger(speccraft.LedgerDesign{ID: "d"}), "d", func(_, _ string) (string, bool) { return "", false })
	if !empty.Done || empty.Total != 0 {
		t.Errorf("empty design must be Done with 0 members, got %+v", empty)
	}
	absent := speccraft.Reconcile(mkLedger(), "nope", func(_, _ string) (string, bool) { return "", false })
	if !absent.Done || absent.Total != 0 {
		t.Errorf("absent design must be Done with 0 members, got %+v", absent)
	}
}

// AC4 belt-and-suspenders: the Reconcile impl must not read the ledger pointer.
func Test_ReconcileImpl_NoLastCompletedPhaseReference(t *testing.T) {
	toolsDir := findRepoRoot(t)
	src, err := os.ReadFile(filepath.Join(toolsDir, "internal", "speccraft", "ledger.go"))
	if err != nil {
		t.Fatal(err)
	}
	i := strings.Index(string(src), "func Reconcile(")
	if i < 0 {
		t.Fatal("func Reconcile not found in ledger.go")
	}
	body := string(src)[i:]
	if strings.Contains(body, "LastCompletedPhase") || strings.Contains(body, "last_completed_phase") {
		t.Error("Reconcile must not reference the ledger's last_completed_phase pointer")
	}
}
