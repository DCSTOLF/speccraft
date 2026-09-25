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

  # --- spec 0049: forbidden for the OTHER TWO artifact kinds ---
  # Spec 0022 added design.md and brief.md outside spec-0036's guardrail, so the
  # scanner's path-shape filter never saw them and two byte-identical GNU-only
  # in-place edits shipped. f5 is the ACTUAL escaped line, carried verbatim.
  printf '%s\n' 'sed -i -E "0,/^status:/s/^status: .*/status: $new/" "$file"'     > "$FIX/forbidden/f5.lib.sh"
  printf '%s\n' "sed -i 's/^status:.*/status: decided/' design/0001-x/design.md"  > "$FIX/forbidden/f6.lib.sh"
  printf '%s\n' "sed -i 's/^status:.*/status: prioritized/' product/0001-x/brief.md" > "$FIX/forbidden/f7.lib.sh"
  printf '%s\n' 'sed -i "s/^status:.*/status: decided/" "$DESIGN"'               > "$FIX/forbidden/f8.lib.sh"
  printf '%s\n' 'sed -i "s/^status:.*/status: prioritized/" "$BRIEF"'            > "$FIX/forbidden/f9.lib.sh"
  printf '%s\n' "perl -pi -e 's/^status:.*/status: decided/' \"\$design_md\""    > "$FIX/forbidden/f10.lib.sh"

  # --- permitted: reads, stderr prints, awk-to-tmp, unrelated in-place edits ---
  printf '%s\n' "sed -n '/^status:/p' \"\$SPEC_MD\""              > "$FIX/permitted/p1.lib.sh"
  # spec 0049: read-only inspection of a design/brief is how the live helpers
  # gate their source status — it must not be flagged.
  printf '%s\n' "awk -F': ' '/^status:/{print \$2; exit}' \"\$DESIGN\""  > "$FIX/permitted/p6.lib.sh"
  printf '%s\n' "grep -E '^status:' product/0001-x/brief.md"             > "$FIX/permitted/p7.lib.sh"
  printf '%s\n' 'speccraft-state set-status --kind design "$file" decided' > "$FIX/permitted/p8.lib.sh"
  printf '%s\n' "grep -E '^status:' \"\$SPEC_MD\""                > "$FIX/permitted/p2.lib.sh"
  printf '%s\n' 'echo "status: $s (reviewed)" >&2'               > "$FIX/permitted/p3.lib.sh"
  printf '%s\n' "awk '/revision: 0/{ins=1} {print}' \"\$spec_md\" > \"\$tmp\"" > "$FIX/permitted/p4.lib.sh"
  printf '%s\n' "sed -i 's/foo/bar/' README.md"                  > "$FIX/permitted/p5.lib.sh"
  export PLUGIN_DIR FIX
}
teardown() { rm -rf "$FIX"; }

# The meta-guard scanner (also the shape the review-time guard uses). Prints
# offending "file:line:text" rows; empty output ⇒ clean.
#
# SCAN ROOT: `commands/` only, NEVER `specs/` — see the archive-safety test
# below before widening it.
#
# ARTIFACT-KIND COVERAGE (spec 0049 AC7): the path-shape filter covers all THREE
# artifact kinds. It used to match only `spec.md`-shaped targets, which is how
# spec 0022's design.md and brief.md writers sat outside spec 0036's guardrail
# and shipped two byte-identical GNU-only in-place edits. A guard scoped to one
# artifact kind is a guard that will miss the next two.
#
# Non-literal targets stay scoped IN per the conventions' "scope conservatively
# IN, never silently skip" rule: `"$file"`, `"$DESIGN"`, `$brief_md` and friends
# are all treated as artifact targets, because a guard that skipped variable
# targets would be trivially evadable by assigning the path first.
scan_offenders() {
  local root="$1"
  # Any of the three artifact kinds, literal or variable-held. `file`/`FILE` is
  # included because that is exactly what the escaped helpers used.
  local shapes='spec\.md|SPEC_MD|spec_md|design\.md|DESIGN|design_md|brief\.md|BRIEF|brief_md|\$file|\$FILE'
  # (a) sed -i / perl -i / perl -pi in-place edits whose script touches
  #     status:/revision: and whose target is an artifact-shaped path.
  grep -rnE 'sed -i|perl -i|perl -pi' "$root" 2>/dev/null \
    | grep -E '(status|revision):' \
    | grep -E "$shapes" || true
  # (b) awk that REDIRECTS (>) onto an artifact-shaped target with the fields in body.
  grep -rnE "awk .*>[[:space:]]*[\"']?\\\$?[A-Za-z0-9_/.-]*(spec|design|brief)\.md" "$root" 2>/dev/null \
    | grep -E '(status|revision):' || true
}

@test "meta-guard FLAGS every forbidden raw frontmatter-write fixture" {
  out="$(scan_offenders "$FIX/forbidden")"
  for f in f1 f2 f3 f4 f5 f6 f7 f8 f9 f10; do
    echo "$out" | grep -q "$f.lib.sh" || { echo "missed $f:"; echo "$out"; return 1; }
  done
}

# Spec 0049 AC7 — the scan root stays `commands/` and must NEVER widen to
# `specs/`. Load-bearing once this spec closes: consolidation moves it to
# specs/.archive/0049-command-lib-portability/spec.md carrying the forbidden
# in-place edit quoted verbatim in its Why section, and f5 above carries the
# same line as a fixture. A scan root widened to specs/** would flag the
# project's own historical evidence and wedge the guard on its own archive.
@test "meta-guard scan root excludes specs/ (archive-safety, AC7)" {
  # The live scan must be scoped to commands/ only.
  #
  # NOTE the bracket-escaped patterns (`command[s]`, `spec[s]`): a plain literal
  # would match THIS test's own source line, making the positive assertion
  # vacuously true and the negative one permanently false. The brackets match
  # the real call sites without matching the pattern itself.
  grep -q 'scan_offenders "$PLUGIN_DIR/command[s]"' "$BATS_TEST_FILENAME"
  run grep -n 'scan_offenders "$PLUGIN_DIR/spec[s]"' "$BATS_TEST_FILENAME"
  [ "$status" -ne 0 ] || { echo "scan root must not include specs/"; echo "$output"; false; }

  # And prove the boundary behaviourally: a planted offender under a specs/
  # shaped tree is NOT reported by a commands/-rooted scan.
  planted="$FIX/tree/commands"
  mkdir -p "$planted" "$FIX/tree/specs/0049-x"
  printf '%s\n' "sed -i -E \"0,/^status:/s/^status: .*/status: decided/\" \"\$file\"" \
    > "$FIX/tree/specs/0049-x/spec.md"
  out="$(scan_offenders "$planted")"
  [ -z "$out" ] || { echo "commands/-rooted scan reached specs/:"; echo "$out"; false; }
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
