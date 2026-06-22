#!/usr/bin/env bash
# commands/spec/new.lib.sh — testable shell helpers backing /speccraft:spec:new
# (spec 0022, AC5/AC8). Sourced by commands/spec/new.md at runtime and by
# tests/hooks/spec-new-from.bats at test time.
#
# All functions are pure (no top-level side effects). Errors / non-fatal notes
# go to stderr; stdout is reserved for structured output. Mirrors the
# commands/{pm,arch}/new.lib.sh colocation pattern.
#
# The --from bridge is PULL-ONLY and ADVISORY (spec §Lifecycle): a missing,
# deleted, or closed referent NEVER blocks spec:new — an unresolvable link
# surfaces a non-fatal note and the command proceeds (AC8). Plain spec:new
# writes NO informed-by key, keeping byte-shape parity with today (AC5).

set -euo pipefail

# spec_referent_artifact <repo-root> <referent>
# Maps a --from referent (product/<id> or design/<id>) to its artifact file.
# Returns non-zero with a stderr note for an unrecognized referent shape.
spec_referent_artifact() {
  local root="$1" ref="$2"
  case "$ref" in
    product/*) printf '%s\n' "$root/$ref/brief.md" ;;
    design/*)  printf '%s\n' "$root/$ref/design.md" ;;
    *)
      echo "spec_referent_artifact: unrecognized referent '$ref' (expected product/<id> or design/<id>)" >&2
      return 1
      ;;
  esac
}

# spec_extract_section <file> <header>
# Echoes the body lines under "## <header>" up to the next "## " header or EOF.
# A missing file or absent section yields empty output (exit 0) — extraction is
# best-effort and never fatal.
spec_extract_section() {
  local file="$1" header="$2"
  [ -f "$file" ] || return 0
  awk -v h="## $header" '
    $0 == h { grab=1; next }
    grab && /^## / { exit }
    grab { print }
  ' "$file"
}

# spec_new_scaffold <spec-file> <id> <title> <created> <repo-root> [referent]
# Writes a draft spec.md mirroring the commands/spec/new.md template.
#   - With a referent: pulls the referent's Why/What into the new spec and
#     writes a NON-EMPTY `informed-by: [<referent>]` frontmatter key. A missing
#     referent is non-fatal — a note goes to stderr, the advisory link is still
#     recorded, and placeholder sections are used (AC8).
#   - Without a referent: NO informed-by key is written (AC5 byte-shape parity).
spec_new_scaffold() {
  local file="$1" id="$2" title="$3" created="$4" root="$5" ref="${6:-}"
  local why="<motivation>" what="<scope description>" informed_line=""

  if [ -n "$ref" ]; then
    informed_line="informed-by: [$ref]"
    local art ex_why ex_what
    if art="$(spec_referent_artifact "$root" "$ref")" && [ -f "$art" ]; then
      ex_why="$(spec_extract_section "$art" Why)"
      ex_what="$(spec_extract_section "$art" What)"
      if [ -n "$(printf '%s' "$ex_why" | tr -d '[:space:]')" ]; then why="$ex_why"; fi
      if [ -n "$(printf '%s' "$ex_what" | tr -d '[:space:]')" ]; then what="$ex_what"; fi
    else
      echo "spec_new_scaffold: --from referent '$ref' not found; recording advisory link and proceeding" >&2
    fi
  fi

  mkdir -p "$(dirname "$file")"
  {
    echo "---"
    echo "id: \"$id\""
    echo "title: \"$title\""
    echo "status: draft"
    echo "created: $created"
    echo "authors: [claude]"
    echo "packages: []"
    echo "related-specs: []"
    [ -n "$informed_line" ] && echo "$informed_line"
    echo "---"
    echo ""
    echo "# Spec $id — $title"
    echo ""
    echo "## Why"
    echo ""
    printf '%s\n' "$why"
    echo ""
    echo "## What"
    echo ""
    printf '%s\n' "$what"
    echo ""
    echo "## Acceptance criteria"
    echo ""
    echo "1. <observable behavior>"
    echo "2. <observable behavior>"
    echo "3. <observable behavior>"
    echo ""
    echo "## Out of scope"
    echo ""
    echo "- <item>"
    echo ""
    echo "## Open questions"
    echo ""
    echo "_none_"
  } > "$file"
}
