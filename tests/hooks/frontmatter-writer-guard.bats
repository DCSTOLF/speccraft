#!/usr/bin/env bats
# Spec 0036 T25/T26 (AC10, AC9) — the frontmatter-writer meta-guard. Flags raw
# in-place rewrites of status:/revision: targeting a spec.md-shaped path in the
# command libs, so the sanctioned speccraft-state writers are the only path. Pinned
# fixture-first (spec-0030 grep-oracle): must FLAG every forbidden form, PASS every
# permitted form, and find the LIVE commands/ tree clean.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FIX="$(mktemp -d)"
  mkdir -p "$FIX/forbidden" "$FIX/permitted"

  # --- forbidden: raw in-place field rewrites onto a spec.md-shaped target ---
  printf '%s\n' "sed -i 's/^status:.*/status: reviewed/' specs/0001-x/spec.md" > "$FIX/forbidden/f1.lib.sh"
  printf '%s\n' 'sed -i "s/status: draft/status: reviewed/" "$SPEC_MD"'        > "$FIX/forbidden/f2.lib.sh"
  printf '%s\n' "perl -pi -e 's/^revision:.*/revision: 5/' specs/0001-x/spec.md" > "$FIX/forbidden/f3.lib.sh"
  printf '%s\n' "awk 'BEGIN{print \"revision: 9\"}' > specs/0001-x/spec.md"     > "$FIX/forbidden/f4.lib.sh"

  # --- permitted: reads, stderr prints, awk-to-tmp, unrelated in-place edits ---
  printf '%s\n' "sed -n '/^status:/p' \"\$SPEC_MD\""              > "$FIX/permitted/p1.lib.sh"
  printf '%s\n' "grep -E '^status:' \"\$SPEC_MD\""                > "$FIX/permitted/p2.lib.sh"
  printf '%s\n' 'echo "status: $s (reviewed)" >&2'               > "$FIX/permitted/p3.lib.sh"
  printf '%s\n' "awk '/revision: 0/{ins=1} {print}' \"\$spec_md\" > \"\$tmp\"" > "$FIX/permitted/p4.lib.sh"
  printf '%s\n' "sed -i 's/foo/bar/' README.md"                  > "$FIX/permitted/p5.lib.sh"
  export PLUGIN_DIR FIX
}
teardown() { rm -rf "$FIX"; }

# The meta-guard scanner (also the shape the review-time guard uses). Prints
# offending "file:line:text" rows; empty output ⇒ clean.
scan_offenders() {
  local root="$1"
  # (a) sed -i / perl -i / perl -pi in-place edits whose script touches
  #     status:/revision: and whose target is a spec.md-shaped path.
  grep -rnE 'sed -i|perl -i|perl -pi' "$root" 2>/dev/null \
    | grep -E '(status|revision):' \
    | grep -E 'spec\.md|SPEC_MD|spec_md' || true
  # (b) awk that REDIRECTS (>) onto a spec.md-shaped target with the fields in body.
  grep -rnE "awk .*>[[:space:]]*[\"']?\\\$?[A-Za-z0-9_/.-]*spec\.md" "$root" 2>/dev/null \
    | grep -E '(status|revision):' || true
}

@test "meta-guard FLAGS every forbidden raw frontmatter-write fixture" {
  out="$(scan_offenders "$FIX/forbidden")"
  for f in f1 f2 f3 f4; do
    echo "$out" | grep -q "$f.lib.sh" || { echo "missed $f:"; echo "$out"; return 1; }
  done
}

@test "meta-guard PASSES every permitted fixture (reads, stderr, awk-to-tmp, unrelated sed -i)" {
  out="$(scan_offenders "$FIX/permitted")"
  [ -z "$out" ] || { echo "false positive:"; echo "$out"; return 1; }
}

@test "the LIVE commands/ tree has no raw frontmatter-write offenders" {
  out="$(scan_offenders "$PLUGIN_DIR/commands")"
  [ -z "$out" ] || { echo "live offenders:"; echo "$out"; return 1; }
}

@test "close.md sets the closed status via the sanctioned set-status writer (AC9 call site)" {
  grep -qE 'speccraft-state set-status .*closed' "$PLUGIN_DIR/commands/spec/close.md"
}
