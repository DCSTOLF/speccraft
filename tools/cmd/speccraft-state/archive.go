package main

// Spec 0036 (AC3/AC4/AC15) — the self-healing, no-clobber archive move lives in
// the speccraft-state CMD package (not internal/speccraft) so it rides the run()
// seam RED and its fault-injection test is a same-package sibling — keeping the
// override budget at exactly 1 (see plan Guard notes).

import (
	"os"
	"strconv"
)

// linkNoReplace / unlinkFile are seams so the AC15 link-ok/unlink-fail fault is
// unit-testable. os.Link is a genuine no-replace primitive: it fails with EEXIST
// if the destination exists (no-clobber), never overwriting an archived artifact.
var (
	linkNoReplace = os.Link
	unlinkFile    = os.Remove
)

// artifactPaths returns the live source and archived destination paths for a
// disposable artifact kind (review/plan/tasks) at the given ordinal.
func artifactPaths(specDir, kind string, ordinal uint64) (src, dst string) {
	src = specDir + "/" + kind + ".md"
	dst = specDir + "/" + kind + "-r" + strconv.FormatUint(ordinal, 10) + ".md"
	return src, dst
}

// sameInodeSibling reports whether any existing <kind>-r*.md archive in specDir
// is the SAME inode (os.SameFile) as srcFI — i.e. an incomplete prior hard-link
// move (AC15). Byte-equality is deliberately not used: unrelated revisions can
// share bytes. (No strings import: manual prefix/suffix keeps guard edits clean.)
func sameInodeSibling(specDir, kind string, srcFI os.FileInfo) bool {
	entries, err := os.ReadDir(specDir)
	if err != nil {
		return false
	}
	prefix := kind + "-r"
	for _, e := range entries {
		name := e.Name()
		if len(name) < len(prefix)+4 || name[:len(prefix)] != prefix || name[len(name)-3:] != ".md" {
			continue
		}
		fi, err := os.Stat(specDir + "/" + name)
		if err != nil {
			continue
		}
		if os.SameFile(srcFI, fi) {
			return true
		}
	}
	return false
}

// moveArtifactNoReplace archives specDir/<kind>.md to specDir/<kind>-r<ordinal>.md
// with genuine no-replace semantics: link (fails EEXIST if the target exists) then
// unlink the source. spec.md is never a kind, so it is never archived.
//
// AC15 interrupted-move recovery: if the live source is the SAME inode as an
// already-present same-kind archive, a prior link succeeded but its unlink did
// not — complete that move by unlinking the source, never creating a duplicate at
// a fresh ordinal. If no same-inode sibling exists it fails safe (never deletes
// the source on a mere byte coincidence).
func moveArtifactNoReplace(specDir, kind string, ordinal uint64) error {
	src, dst := artifactPaths(specDir, kind, ordinal)
	if fi, err := os.Stat(src); err == nil && sameInodeSibling(specDir, kind, fi) {
		return unlinkFile(src)
	}
	if err := linkNoReplace(src, dst); err != nil {
		return err
	}
	return unlinkFile(src)
}
