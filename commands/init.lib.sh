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

# ============================================================================
# Workspace-init helpers (spec 0042). Pure functions backing
# /speccraft:init --workspace. All deterministic mechanics live here; the
# model-driven approval prompt + orchestration live in commands/init.md. These
# only WRITE the two artifacts the 0037–0040 readers already parse (a
# kind = "workspace" speccraft.toml + a workspace.yml manifest); they never
# modify config.go / workspace_topology.go / ledger.go.
# ============================================================================

# ws_error <msg> — shared usage/error envelope: message + usage to stderr,
# non-zero. Keeps every helper's failure path uniform (spec 0042).
ws_error() {
  printf 'init --workspace: %s\n' "$1" >&2
  printf 'usage: /speccraft:init [--workspace] [--force]\n' >&2
  return 2
}

# ws_arg_parse <args...> — recognize --workspace/--force order-independently and
# idempotently; reject any unknown flag or stray positional. Prints the
# normalized flag set (one token per line: `workspace` and/or `force`) to stdout
# (AC6 order-independence).
ws_arg_parse() {
  local want_ws=0 want_force=0 a
  for a in "$@"; do
    case "$a" in
      --workspace) want_ws=1 ;;
      --force) want_force=1 ;;
      *) ws_error "unrecognized argument: $a"; return 2 ;;
    esac
  done
  [ "$want_ws" -eq 1 ] && printf 'workspace\n'
  [ "$want_force" -eq 1 ] && printf 'force\n'
  return 0
}

# ws_toml_body — read the existing speccraft.toml from stdin (empty ⇒ fresh) and
# emit the canonical workspace toml. A clean single kind="workspace" is returned
# unchanged (idempotent, other keys preserved); duplicate/malformed kind lines
# normalize to a single kind="workspace"; a well-formed kind="repo" REFUSES an
# in-place migration (non-zero, no stdout) (AC1/AC7).
ws_toml_body() {
  local content
  content="$(cat)"
  if [ -z "${content//[[:space:]]/}" ]; then
    printf 'kind = "workspace"\n'
    return 0
  fi
  # A well-formed repo kind is the migration signal → refuse (emit nothing).
  if printf '%s\n' "$content" | grep -q '^kind = "repo"$'; then
    ws_error "refusing in-place migration of a repo-kind root to workspace"
    return 3
  fi
  local nkind
  nkind="$(printf '%s\n' "$content" | grep -c '^[[:space:]]*kind[[:space:]]*=' || true)"
  if [ "$nkind" -eq 1 ] && printf '%s\n' "$content" | grep -q '^kind = "workspace"$'; then
    printf '%s\n' "$content" # idempotent: unchanged
    return 0
  fi
  # Normalize: one canonical kind line, then every non-kind line preserved.
  printf 'kind = "workspace"\n'
  printf '%s\n' "$content" | grep -v '^[[:space:]]*kind[[:space:]]*='
  return 0
}

# _ws_quote_member <seg> — emit the manifest value form of a path segment, or
# return 1 (caller skips) if it contains a double-quote (unrepresentable in the
# parser's grammar). Bare unless it has whitespace or '#', else double-quoted
# (the parser's literal quoted form).
_ws_quote_member() {
  local seg="$1"
  case "$seg" in
    *'"'*) return 1 ;;
  esac
  case "$seg" in
    *[[:space:]]*|*'#'*) printf '"%s"' "$seg" ;;
    *) printf '%s' "$seg" ;;
  esac
}

# ws_manifest_body <member>... — render the exact canonical workspace.yml (spec
# 0042 §Canonical shape): comment header, `members:`, sorted `  - path: <value>`
# lines, then the commented example. A "-bearing segment is skipped with a
# stderr reason. LF + single trailing newline (AC2).
ws_manifest_body() {
  printf '# speccraft workspace manifest — members orchestrated by /speccraft:arch:orchestrate\n'
  printf 'members:\n'
  if [ "$#" -gt 0 ]; then
    local seg val
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      if val="$(_ws_quote_member "$seg")"; then
        printf '  - path: %s\n' "$val"
      else
        printf 'skip: member with a double-quote in its name cannot be represented\n' >&2
      fi
    done < <(printf '%s\n' "$@" | LC_ALL=C sort)
  fi
  printf '#  - path: relative/child-repo\n'
}

# ws_detect_members <root> — the deterministic child-scan (AC3a). Emits, sorted,
# each immediate child directory that is a repo-kind speccraft repo. Excludes
# symlinks, hidden dot-dirs, "-bearing names, nested workspaces, and children
# with an unreadable/strict-invalid config — each with a stderr reason. Uses the
# strict `config-kind` reader (never a coerce-to-repo read). Never recurses.
ws_detect_members() {
  local root="$1" child base kind
  local -a found=()
  for child in "$root"/*; do
    [ -e "$child" ] || continue
    base="$(basename "$child")"
    case "$base" in .*) continue ;; esac          # hidden dot-dir
    [ -L "$child" ] && continue                    # symlinked child
    [ -d "$child" ] || continue
    case "$base" in *'"'*) printf 'skip: %s has a double-quote in its name\n' "$base" >&2; continue ;; esac
    [ -d "$child/.speccraft" ] || continue         # membership marker
    if ! kind="$(speccraft-state config-kind "$child" 2>/dev/null)"; then
      printf 'skip: %s config unreadable or strict-invalid\n' "$base" >&2
      continue
    fi
    case "$kind" in
      repo)      found+=("$base") ;;
      workspace) printf 'skip: %s is a nested workspace\n' "$base" >&2 ;;
      *)         printf 'skip: %s unexpected kind %q\n' "$base" "$kind" >&2 ;;
    esac
  done
  [ "${#found[@]}" -gt 0 ] && printf '%s\n' "${found[@]}" | LC_ALL=C sort
  return 0
}

# ws_write_root <root> [member...] — compose the artifacts in the AC9-mandated
# order: (1) write workspace.yml FIRST (only if absent — a curated manifest is
# preserved, AC6), then (2) ONLY after that flip speccraft.toml to kind=workspace
# via ws_toml_body (honoring its migration refusal). Never creates or touches
# ledger.md (AC4). A failure after (1) but before the toml flip leaves the
# manifest present and the kind un-flipped — never an orphan workspace kind.
ws_write_root() {
  local root="$1"; shift
  local yml="$root/workspace.yml"
  local toml="$root/.speccraft/speccraft.toml"

  # (1) manifest first — atomic tmp+rename; preserve an existing curated one.
  if [ ! -e "$yml" ]; then
    local ytmp="$yml.wstmp.$$"
    ws_manifest_body "$@" > "$ytmp" || { rm -f "$ytmp"; return 1; }
    mv "$ytmp" "$yml" || { rm -f "$ytmp"; return 1; }
  fi

  # (2) only now flip the toml to workspace kind.
  mkdir -p "$root/.speccraft"
  local existing="" body
  [ -f "$toml" ] && existing="$(cat "$toml")"
  body="$(printf '%s' "$existing" | ws_toml_body)" || return $?
  # Direct redirect: a non-regular-file target (e.g. a directory) fails here,
  # AFTER the manifest already exists — the AC9 ordering discriminator.
  printf '%s\n' "$body" > "$toml" || return 1
  return 0
}
