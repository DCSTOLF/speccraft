package speccraft_test

// Tests for ActiveSpecDir (spec 0013 AC2).
//
// Pins the post-0012 cleared-state semantics for the helper:
//
//   - empty argv (cleared/unset) returns ""
//   - real spec id round-trips through filepath.Join
//   - the literal string "null" is treated as an ordinary id, NOT as
//     a cleared sentinel. This is the load-bearing behavior change
//     spec 0013 introduces by removing the dead null-equality
//     disjunct at root.go:45 — that disjunct was a defensive
//     fallback for a pre-0012 disk shape that no production path
//     produces anymore.

import (
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func TestActiveSpecDir_EmptyReturnsEmpty(t *testing.T) {
	got := speccraft.ActiveSpecDir("/repo", "")
	if got != "" {
		t.Errorf("ActiveSpecDir(/repo, \"\") = %q, want %q", got, "")
	}
}

func TestActiveSpecDir_RealSpecIdReturnsJoinedPath(t *testing.T) {
	want := filepath.Join("/repo", "specs", "0001-foo")
	got := speccraft.ActiveSpecDir("/repo", "0001-foo")
	if got != want {
		t.Errorf("ActiveSpecDir(/repo, \"0001-foo\") = %q, want %q", got, want)
	}
}

// TestActiveSpecDir_LiteralNullReturnsJoinedPath pins the intentional
// behavior change of spec 0013: the literal string "null" is no longer
// treated as a cleared sentinel. Post-0012 the only path that could ever
// have produced "null" as a real ActiveSpec value (the buggy
// `speccraft-state set active_spec null` call) is fixed, so this case
// is unreachable in practice — but pinning it as a hard assertion locks
// out any future reintroduction of the sentinel branch.
func TestActiveSpecDir_LiteralNullReturnsJoinedPath(t *testing.T) {
	want := filepath.Join("/repo", "specs", "null")
	got := speccraft.ActiveSpecDir("/repo", "null")
	if got != want {
		t.Errorf("ActiveSpecDir(/repo, \"null\") = %q, want %q (must NOT be \"\")", got, want)
	}
}
