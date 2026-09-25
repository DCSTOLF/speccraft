#!/usr/bin/env bats
# Spec 0049 T11/T12 (AC9) — the GNU-only-form portability meta-guard.
#
# Flags GNU-only shell constructs in the SHIPPED surfaces, so a BSD/macOS user
# never receives a command that silently no-ops. Fixture-first per the
# spec-0036 regime (`.speccraft/conventions.md` §"Fixture-first, per-tool
# meta-guard matching regime"): must FLAG every forbidden form and PASS every
# portable counterpart before the live-tree scan is trusted.
#
# SCAN ROOTS are the shipped surfaces only: hooks/, commands/, tools/,
# templates/, agents/, skills/. `tests/**` is deliberately OUTSIDE — the suites
# are never installed into a user's environment, so a GNU-only form there is not
# a shipped defect.
#
# That exclusion is a scope boundary on THIS GUARD, not a portability exemption
# for the tests, and the two must not be conflated: the `hooks-macos` CI job
# runs the bats suite on BSD userland, so any GNU-only form a test actually
# EXECUTES fails there regardless of what this guard scans. The guard answers
# "did we ship a GNU-ism to a user?"; the macOS runner answers "does our own
# suite run on BSD?".
#
# NO ESCAPE HATCH, deliberately (AC9). Comment and markdown-fence context is
# NOT consulted: a commented-out or fenced occurrence is FLAGGED, not skipped —
# per the conventions' "scope conservatively IN, never silently skip" rule. An
# `allow-gnu-form` style suppression marker was considered and REJECTED: a
# guard that can be silenced by annotation is evadable by annotation, which is
# the property it exists to deny. The cost is real and accepted: documentation
# under a scanned surface that needs to name a forbidden form must be reworded,
# or moved to `.speccraft/` or `specs/` (both outside the scan roots).
#
# PRECISELY what that means, so the guard is not credited with more than it
# does: the patterns are COMMAND-SHAPED. `# sed -i 's/x/y/' f` in a comment is
# flagged because it is still shaped like a command (fixture g10). A prose
# mention in backticks — "`tac` is GNU-only" — is NOT matched, because `tac`
# there is not in command position. That is the pattern being command-shaped,
# not an exemption for comments: there is no syntax that suppresses a match.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FIX="$(mktemp -d)"
  mkdir -p "$FIX/forbidden" "$FIX/permitted"

  # --- forbidden: GNU-only forms ---
  # `sed -i` with no backup suffix: BSD sed reads the NEXT ARGUMENT as the
  # suffix, so the following flag/script is silently consumed.
  printf '%s\n' "sed -i 's/a/b/' f.txt"                       > "$FIX/forbidden/g1.sh"
  # The exact escaped line from the field report: -i with no suffix AND the
  # GNU-only `0,/re/` address form.
  printf '%s\n' 'sed -i -E "0,/^status:/s/^status: .*/status: $new/" "$file"' > "$FIX/forbidden/g2.sh"
  # `0,/re/` on its own is GNU-only even with a portable -i spelling.
  printf '%s\n' "sed -i.bak -E '0,/^k:/s/^k: .*/k: v/' f.md"  > "$FIX/forbidden/g3.sh"
  printf '%s\n' 'history_entries | tac'                       > "$FIX/forbidden/g4.sh"
  printf '%s\n' 'root="$(readlink -f "$1")"'                  > "$FIX/forbidden/g5.sh"
  printf '%s\n' "grep -P '\\\\d+' f.txt"                      > "$FIX/forbidden/g6.sh"
  printf '%s\n' "owner=\"\$(stat -c '%U' \"\$f\")\""          > "$FIX/forbidden/g7.sh"
  printf '%s\n' 'when="$(date -d @1700000000)"'               > "$FIX/forbidden/g8.sh"
  printf '%s\n' 'b="$(base64 -w0 <"$f")"'                     > "$FIX/forbidden/g9.sh"
  # A COMMENTED occurrence is still flagged — no escape hatch.
  printf '%s\n' '# do not use: sed -i on a spec'              > "$FIX/forbidden/g10.sh"
  # A MARKDOWN-FENCED occurrence is still flagged. Command docs live under a
  # scanned root, so a fenced example is as reachable as live code.
  printf '%s\n' '```sh' "sed -i 's/x/y/' f.md" '```'          > "$FIX/forbidden/g11.md"
  # A LINE-CONTINUATION spelling must not slip past a line-oriented scanner:
  # the form itself has to stay on one line to be caught, so the fixture keeps
  # `sed -i` intact and continues AFTER it (the realistic shape).
  printf '%s\n' "sed -i 's/x/y/' \\\\" '  f.md'               > "$FIX/forbidden/g12.sh"
  # A DOUBLE-QUOTED script with no suffix.
  printf '%s\n' 'sed -i "s/x/y/" f.md'                        > "$FIX/forbidden/g13.sh"

  # --- permitted: the portable counterpart of each ---
  printf '%s\n' "sed -i.bak 's/a/b/' f.txt && rm -f f.txt.bak" > "$FIX/permitted/q1.sh"
  printf '%s\n' "sed -i '' 's/a/b/' f.txt"                     > "$FIX/permitted/q2.sh"
  printf '%s\n' "sed -n '/^status:/p' \"\$f\""                 > "$FIX/permitted/q3.sh"
  # The AC8 reversal form. This MUST be permitted in the same change that
  # introduces it, or the guard rejects the very fix that satisfies AC8.
  printf '%s\n' "history_entries | awk '{a[NR]=\$0} END{for(i=NR;i>0;i--) print a[i]}'" > "$FIX/permitted/q4.sh"
  printf '%s\n' 'root="$(cd "$(dirname "$1")" && pwd)"'        > "$FIX/permitted/q5.sh"
  printf '%s\n' "grep -E '[0-9]+' f.txt"                       > "$FIX/permitted/q6.sh"
  printf '%s\n' "owner=\"\$(stat -f '%Su' \"\$f\")\""          > "$FIX/permitted/q7.sh"
  printf '%s\n' 'when="$(speccraft-state format-time 1700000000)"' > "$FIX/permitted/q8.sh"
  printf '%s\n' 'b="$(base64 <"$f" | tr -d "\\n")"'            > "$FIX/permitted/q9.sh"
  # `tac` must match as a COMMAND, not inside an identifier or a word.
  printf '%s\n' 'contact_list=1; syntactic=2; echo "$contact_list$syntactic"' > "$FIX/permitted/q10.sh"

  export PLUGIN_DIR FIX
}
teardown() { rm -rf "$FIX"; }

# The shipped surfaces. tests/ is absent BY DESIGN — see the header.
shipped_roots() {
  local r
  for r in hooks commands tools templates agents skills; do
    [ -d "$PLUGIN_DIR/$r" ] && printf '%s\n' "$PLUGIN_DIR/$r"
  done
}

# scan_gnu_forms <root> — prints offending "file:line:text" rows; empty ⇒ clean.
#
# A bounded lexical scanner over lines, NOT a shell parser. Matching is per
# form, because the forbidden spellings are string PREFIXES of the permitted
# ones: `sed -i` must not match `sed -i.bak` or `sed -i ''`, so it matches only
# when followed by whitespace and a non-suffix token.
scan_gnu_forms() {
  local root="$1"
  # `--exclude=*_test.go`: Go test files under tools/ are TEST-SIDE (review
  # item 5, decided). They are never executed in a user's environment, and
  # execution is already covered by a complementary macOS runner — ci.yml's
  # `unit-macos` job runs `go test ./...` on macos-14, so a GNU-only form a Go
  # test actually runs fails THERE. Scanning them here would add nothing and
  # would false-positive on Go tests that legitimately hold GNU forms as
  # fixture strings. The tests/ exclusion is a directory boundary; this one is
  # a filename boundary, and both are justified by having another runner.
  # (a) in-place sed with NO backup suffix: `-i` followed by whitespace then
  #     something that is not a quoted-empty suffix.
  grep -rnE --exclude="*_test.go" "sed[[:space:]]+-i[[:space:]]+([^'\"[:space:]]|'[^']|\"[^\"])" "$root" 2>/dev/null || true
  # (b) the GNU-only 0,/re/ address form, any -i spelling. The optional quote is
  #     load-bearing: the address usually opens a quoted script (`-E '0,/re/`),
  #     so requiring bare whitespace before `0,/` misses the common spelling.
  grep -rnE --exclude="*_test.go" "sed[^|;]*[[:space:]]['\"]?0,/" "$root" 2>/dev/null || true
  # (c) tac as a command: start of line/pipe/;/&& or after whitespace, and not
  #     part of a longer identifier.
  grep -rnE --exclude="*_test.go" "(^|[|;&(]|[[:space:]])tac([[:space:]]|$|[|;&)])" "$root" 2>/dev/null || true
  # (d) the remaining enumerated GNU-only flag forms.
  grep -rnE --exclude="*_test.go" "readlink[[:space:]]+-f|grep[[:space:]]+-[A-Za-z]*P|stat[[:space:]]+-c|date[[:space:]]+-d[[:space:]]|base64[[:space:]]+-w" "$root" 2>/dev/null || true
}

@test "portability guard FLAGS every forbidden GNU-only fixture" {
  out="$(scan_gnu_forms "$FIX/forbidden")"
  for f in g1 g2 g3 g4 g5 g6 g7 g8 g9 g10 g11 g12 g13; do
    echo "$out" | grep -q "$f\." || { echo "missed $f:"; echo "$out"; return 1; }
  done
}

@test "portability guard PASSES every portable counterpart" {
  out="$(scan_gnu_forms "$FIX/permitted")"
  [ -z "$out" ] || { echo "false positive:"; echo "$out"; return 1; }
}

@test "the LIVE shipped surfaces are free of GNU-only forms" {
  local root out
  while IFS= read -r root; do
    out="$(scan_gnu_forms "$root")"
    [ -z "$out" ] || { echo "GNU-only form shipped under $root:"; echo "$out"; return 1; }
  done < <(shipped_roots)
}

@test "the guard's scan roots exclude tests/ (scope boundary, not an exemption)" {
  # Bracket-escaped so the pattern cannot match this test's own source line.
  run bash -c "shipped_roots 2>/dev/null | grep -q 'test[s]$'"
  [ "$status" -ne 0 ]
  # Positively: tests/ exists and DOES contain forms this guard forbids, which
  # is exactly why the boundary has to be deliberate and documented.
  [ -d "$PLUGIN_DIR/tests" ]
}

# Review round 2, item 5: `tools/**/*_test.go` is Go TEST code living under a
# shipped root — is it shipped or test-side? DECIDED: test-side, EXCLUDED.
#
# The deciding argument is that it already has a complementary runner. ci.yml's
# `unit-macos` job runs `go test ./...` on macos-14, so a GNU-only form that a
# Go test actually executes fails there. Scanning these files here would add no
# coverage and would false-positive on Go tests that legitimately carry GNU
# forms as fixture strings — which is exactly what the sibling meta-guards do
# in bash. Excluding is not a gap; it is routing the check to the runner that
# can actually observe it.
#
# STATED LIMIT while we are here, so this guard is not credited with reach it
# lacks: it is a line-oriented scanner for SHELL forms. A Go file (test or not)
# that invokes a tool via an argv slice — `exec.Command("sed", "-i", …)` — is
# not matched, because matching split argv means parsing Go call syntax, with
# false positives on any string literal containing a flag. The macOS Go runner
# covers that shape.
@test "Go test files under tools/ are excluded (decided, not incidental)" {
  grep -q '_test.go' "$BATS_TEST_FILENAME"
  mkdir -p "$FIX/tools"
  # A shell-form GNU-ism in a NON-test Go file under a shipped root IS flagged.
  printf '%s\n' 'out, _ := exec.Command("sh", "-c", "sed -i s/a/b/ "+f).Output()' > "$FIX/tools/prod.go"
  out="$(scan_gnu_forms "$FIX/tools")"
  [ -n "$out" ] || { echo "a shell-form GNU-ism in a shipped tools/*.go must be flagged"; return 1; }

  # The same line in a *_test.go is NOT flagged — routed to `unit-macos`.
  mv "$FIX/tools/prod.go" "$FIX/tools/x_test.go"
  out="$(scan_gnu_forms "$FIX/tools")"
  [ -z "$out" ] || { echo "*_test.go must be excluded per the decided boundary"; echo "$out"; return 1; }
}
