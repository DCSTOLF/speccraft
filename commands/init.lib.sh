#!/usr/bin/env bash
# commands/init.lib.sh — deterministic helper backing /speccraft:init's
# conventions.md seeding (spec 0034 AC5). SOURCED by commands/init.md at runtime
# and by tests/hooks/init-seed-conventions.bats at test time.
#
# Pure function (no side effects at source time). Mirrors the
# commands/spec/*.lib.sh colocation convention (spec 0015). Cross-shell self-use
# is not required here (no sibling-lib sourcing), but the file stays
# `set -euo pipefail`-safe. This is PURE SHELL — .sh is not guard-gated, so no
# /speccraft:spec:override is ever involved.

# _seed_json_field <json> <field> — extract a string field from the single-line
# detect-stack JSON envelope. Detected commands/languages contain no interior
# quotes, so a minimal non-greedy-by-class match is sufficient.
_seed_json_field() {
  local json="$1" field="$2"
  printf '%s' "$json" | sed -n 's/.*"'"$field"'":"\([^"]*\)".*/\1/p'
}

# _seed_replace_marker <file> <cmd> — replace the FIRST test-command marker line
# with one carrying <cmd>. awk keeps it delimiter-safe (cmd contains ./..., &&,
# etc.). Minimal escaping: backslash then double-quote, matching the reader's
# \" / \\ unescape grammar (spec 0034 marker grammar).
_seed_replace_marker() {
  local file="$1" cmd="$2"
  local esc="${cmd//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  local marker="<!-- speccraft:test-command = \"$esc\" -->"
  awk -v m="$marker" '
    /<!-- speccraft:test-command = / && !done { print m; done=1; next }
    { print }
  ' "$file" > "$file.seedtmp" && mv "$file.seedtmp" "$file"
}

# seed_conventions <root> <template_path> — seed <root>/.speccraft/conventions.md
# from the detected stack. PRESERVES an existing file byte-for-byte (idempotent);
# on a fresh seed, copies the stack-agnostic template and fills the marker +
# a detected-stack note. Unknown stack → empty marker + TODO placeholder.
seed_conventions() {
  local root="$1" template="$2"
  local dest="$root/.speccraft/conventions.md"

  # Editable source of truth: never clobber an existing conventions.md.
  if [ -f "$dest" ]; then
    return 0
  fi

  mkdir -p "$root/.speccraft"
  cp "$template" "$dest"

  # Detect from the repo root so find-root resolves .speccraft/.
  local json lang cmd
  json="$(cd "$root" && speccraft-state detect-stack 2>/dev/null || true)"
  lang="$(_seed_json_field "$json" language)"
  cmd="$(_seed_json_field "$json" test_command)"

  if [ -z "$lang" ] || [ "$lang" = "unknown" ] || [ -z "$cmd" ]; then
    _seed_replace_marker "$dest" ""
    printf '\n<!-- TODO: speccraft could not detect this repo'\''s stack. Set your\n     test command in the marker above (e.g. "<your test command>"). -->\n' >> "$dest"
  else
    _seed_replace_marker "$dest" "$cmd"
    printf '\n<!-- Seeded by /speccraft:init from the detected stack: %s. -->\n' "$lang" >> "$dest"
  fi
}
