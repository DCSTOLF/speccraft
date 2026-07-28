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
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// writeKind writes .speccraft/speccraft.toml with the given kind at root
// (spec 0037 helper).
func writeKind(t *testing.T, root, kind string) {
	t.Helper()
	dir := filepath.Join(root, ".speccraft")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "speccraft.toml"), []byte("kind = \""+kind+"\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func Test_FindWorkspaceRoot_RepoUnderWorkspace_ReturnsWorkspace(t *testing.T) {
	ws := t.TempDir()
	writeKind(t, ws, "workspace")
	repo := filepath.Join(ws, "api")
	if err := os.MkdirAll(filepath.Join(repo, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	got, err := speccraft.FindWorkspaceRoot(repo)
	if err != nil {
		t.Fatalf("FindWorkspaceRoot: %v", err)
	}
	if got != ws {
		t.Errorf("FindWorkspaceRoot(%q) = %q, want workspace root %q", repo, got, ws)
	}
}

// mkRepoDir creates dir with an empty .speccraft/ (a default repo-kind root).
func mkRepoDir(t *testing.T, dir string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(dir, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
}

func Test_FindWorkspaceRoot_Cases(t *testing.T) {
	t.Run("WorkspaceRootItself_ReturnsItself", func(t *testing.T) {
		ws := t.TempDir()
		writeKind(t, ws, "workspace")
		got, err := speccraft.FindWorkspaceRoot(ws)
		if err != nil || got != ws {
			t.Errorf("got (%q, %v), want (%q, nil)", got, err, ws)
		}
	})

	t.Run("LoneRepo_FallsBackToFindRoot", func(t *testing.T) {
		repo := t.TempDir()
		mkRepoDir(t, repo)
		got, err := speccraft.FindWorkspaceRoot(repo)
		want, wantErr := speccraft.FindRoot(repo)
		if got != want || (err == nil) != (wantErr == nil) {
			t.Errorf("got (%q, %v), want FindRoot parity (%q, %v)", got, err, want, wantErr)
		}
	})

	t.Run("NoSpeccraft_ReturnsFindRootError", func(t *testing.T) {
		bare := t.TempDir() // no .speccraft anywhere up-tree
		got, err := speccraft.FindWorkspaceRoot(bare)
		_, wantErr := speccraft.FindRoot(bare)
		if err == nil || wantErr == nil {
			t.Errorf("expected error parity with FindRoot; got err=%v wantErr=%v", err, wantErr)
		}
		if got != "" {
			t.Errorf("expected empty path on error, got %q", got)
		}
	})

	t.Run("NestedWorkspaces_ReturnsNearest", func(t *testing.T) {
		outer := t.TempDir()
		writeKind(t, outer, "workspace")
		inner := filepath.Join(outer, "inner")
		writeKind(t, inner, "workspace")
		got, err := speccraft.FindWorkspaceRoot(inner)
		if err != nil || got != inner {
			t.Errorf("got (%q, %v), want nearest workspace %q", got, err, inner)
		}
	})

	t.Run("MalformedKindAncestor_NotTreatedAsWorkspace", func(t *testing.T) {
		outer := t.TempDir()
		writeKind(t, outer, "workspace")
		mid := filepath.Join(outer, "mid")
		writeKind(t, mid, "bogus") // unknown kind → coerced to repo → not a workspace
		start := filepath.Join(mid, "pkg")
		if err := os.MkdirAll(start, 0o755); err != nil {
			t.Fatal(err)
		}
		got, err := speccraft.FindWorkspaceRoot(start)
		if err != nil || got != outer {
			t.Errorf("got (%q, %v), want outer workspace %q (malformed mid skipped)", got, err, outer)
		}
	})
}

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
