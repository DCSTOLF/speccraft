#!/usr/bin/env bash
# commands/spec/revise.lib.sh — testable shell helpers backing
# /speccraft:spec:revise (spec 0015). Sourced both by commands/spec/revise.md
# at runtime and by tests/hooks/spec-revise-preflight.bats at test time.
#
# All functions are pure (no top-level side effects). Output: human-readable
# stderr on error; stdout reserved for structured output (drift items,
# diff signals). Return: 0 on success; non-zero with stderr message on
# failure.
#
# Dependencies: bash 4+, POSIX awk/sed/grep, jq. yq is intentionally NOT
# required — packages[] parsing uses an awk-based subset parser that handles
# the narrow `packages: [...]` single-line and block shapes spec 0015 accepts.

set -euo pipefail

# ---------------------------------------------------------------------------
# Internal: emit a uniform "function: detail" error to stderr. Centralised
# so any future change to the error envelope (log level, category prefix,
# JSON wrapping for hook integration) lands in one place.
# ---------------------------------------------------------------------------
revise_error() {
  local func="$1"; shift
  printf '%s: %s\n' "$func" "$*" >&2
}

# ---------------------------------------------------------------------------
# Internal: extract the YAML frontmatter block (between the first two `---`
# lines) of a Markdown file to stdout. Empty if no frontmatter present.
# ---------------------------------------------------------------------------
_revise_extract_frontmatter() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    BEGIN { state = 0 }
    /^---$/ {
      if (state == 0) { state = 1; next }
      else if (state == 1) { state = 2; next }
    }
    state == 1 { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# preflight_status_gate <spec.md path>
#
# Reads the `status:` frontmatter field. Accepts draft, reviewed, planned.
# Rejects any other value with a stderr message naming the offending status.
# Implements spec 0015 §Mechanism step 2 (status gate) and AC1.
# ---------------------------------------------------------------------------
preflight_status_gate() {
  local spec_md="$1"
  local fm status
  fm="$(_revise_extract_frontmatter "$spec_md")"
  status="$(printf '%s\n' "$fm" | awk -F'[: ]+' '/^status:/ { print $2; exit }')"
  case "$status" in
    draft|reviewed|planned)
      return 0
      ;;
    "")
      echo "preflight_status_gate: $spec_md has no status: field in frontmatter" >&2
      return 1
      ;;
    *)
      echo "preflight_status_gate: $spec_md has status '$status' which is not revisable (must be one of: draft, reviewed, planned)" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# preflight_active_spec_set <state.json path>
#
# Verifies state.json's active_spec field is set and non-empty. Errors with
# a stderr message pointing to /speccraft:spec:new otherwise. Implements
# spec 0015 §Mechanism step 1 and AC2.
# ---------------------------------------------------------------------------
preflight_active_spec_set() {
  local state_json="$1"
  local active
  if [ ! -f "$state_json" ]; then
    echo "preflight_active_spec_set: $state_json not found — run /speccraft:spec:new first" >&2
    return 1
  fi
  active="$(jq -r '.active_spec // ""' "$state_json")"
  if [ -z "$active" ]; then
    echo "preflight_active_spec_set: no active spec — run /speccraft:spec:new first" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# ensure_revision_field <spec.md path>
#
# Idempotently ensures the spec.md frontmatter has a `revision:` key. If
# absent, inserts `revision: 0` immediately after the `created:` line (or
# before the closing `---` if `created:` is absent). Idempotent: re-running
# against a spec.md that already has `revision:` is a no-op (file byte-
# identical pre/post). Implements spec 0015 §Mechanism step 2a.
# ---------------------------------------------------------------------------
ensure_revision_field() {
  local spec_md="$1"
  local fm
  fm="$(_revise_extract_frontmatter "$spec_md")"
  if printf '%s\n' "$fm" | grep -qE '^revision:'; then
    return 0  # already present — idempotent no-op
  fi
  # Insert `revision: 0` after the `created:` line (or before the closing
  # `---` if no `created:` line is present).
  local tmp
  tmp="$(mktemp)"
  awk '
    BEGIN { state = 0; inserted = 0 }
    /^---$/ {
      if (state == 0) { state = 1; print; next }
      else if (state == 1) {
        if (!inserted) { print "revision: 0"; inserted = 1 }
        state = 2; print; next
      }
    }
    state == 1 && /^created:/ {
      print
      print "revision: 0"
      inserted = 1
      next
    }
    { print }
  ' "$spec_md" > "$tmp"
  mv "$tmp" "$spec_md"
}

# ---------------------------------------------------------------------------
# preflight_archive_collisions <spec dir> <source status> <N_old>
#
# Verifies that the archive target paths the revise command would write to
# do not already exist on disk. For source status `reviewed`, checks
# review-r<N_old>.md. For `planned`, additionally checks plan-r<N_old>.md
# and tasks-r<N_old>.md. For `draft`, exits zero (nothing to archive).
# Errors with a stderr message naming the conflicting path. Implements
# spec 0015 §Mechanism step 4 and AC9.
# ---------------------------------------------------------------------------
preflight_archive_collisions() {
  local spec_dir="$1"
  local source_status="$2"
  local n_old="$3"
  local conflict=""
  case "$source_status" in
    reviewed)
      if [ -e "$spec_dir/review-r${n_old}.md" ]; then
        conflict="$spec_dir/review-r${n_old}.md"
      fi
      ;;
    planned)
      if [ -e "$spec_dir/review-r${n_old}.md" ]; then
        conflict="$spec_dir/review-r${n_old}.md"
      elif [ -e "$spec_dir/plan-r${n_old}.md" ]; then
        conflict="$spec_dir/plan-r${n_old}.md"
      elif [ -e "$spec_dir/tasks-r${n_old}.md" ]; then
        conflict="$spec_dir/tasks-r${n_old}.md"
      fi
      ;;
    draft)
      return 0
      ;;
    *)
      echo "preflight_archive_collisions: unknown source status '$source_status' (expected: draft, reviewed, planned)" >&2
      return 1
      ;;
  esac
  if [ -n "$conflict" ]; then
    echo "preflight_archive_collisions: archive target $conflict already exists; refusing to overwrite" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# preflight_source_artifacts <spec dir> <source status>
#
# Verifies that the source artifacts the revise command will rename actually
# exist. For `reviewed`, requires review.md. For `planned`, requires
# review.md, plan.md, and tasks.md. For `draft`, exits zero. Errors with a
# stderr message naming the missing file. Implements spec 0015 §Mechanism
# step 5 and AC10.
# ---------------------------------------------------------------------------
preflight_source_artifacts() {
  local spec_dir="$1"
  local source_status="$2"
  case "$source_status" in
    reviewed)
      if [ ! -f "$spec_dir/review.md" ]; then
        echo "preflight_source_artifacts: $spec_dir/review.md missing (required for reviewed-source revise)" >&2
        return 1
      fi
      ;;
    planned)
      local f
      for f in review.md plan.md tasks.md; do
        if [ ! -f "$spec_dir/$f" ]; then
          echo "preflight_source_artifacts: $spec_dir/$f missing (required for planned-source revise)" >&2
          return 1
        fi
      done
      ;;
    draft)
      return 0
      ;;
    *)
      echo "preflight_source_artifacts: unknown source status '$source_status' (expected: draft, reviewed, planned)" >&2
      return 1
      ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# extract_identifiers <spec.md path>
#
# Emits, one per line, the set of identifier tokens used in single-backtick
# spans inside §What, §Acceptance criteria, and §Out of scope. Tokens must
# match `[A-Za-z_][A-Za-z0-9_]{3,}` (at least 4 characters). Fenced code
# blocks (triple-backtick) are EXCLUDED. Output is deduplicated via sort -u.
# Implements spec 0015 §Identifier-extraction rule.
# ---------------------------------------------------------------------------
extract_identifiers() {
  local spec_md="$1"
  [ -f "$spec_md" ] || { echo "extract_identifiers: $spec_md not found" >&2; return 1; }
  # Stage 1: filter to lines inside the three tracked sections, excluding
  # fenced code blocks. Fenced-block tracking toggles on any line that
  # begins with ``` (with optional language tag).
  local stage1
  stage1="$(awk '
    BEGIN { tracked = 0; fenced = 0 }
    /^```/ { fenced = !fenced; next }
    fenced { next }
    /^## What$/                { tracked = 1; next }
    /^## Acceptance criteria$/ { tracked = 1; next }
    /^## Out of scope$/        { tracked = 1; next }
    /^## /                     { tracked = 0; next }
    tracked { print }
  ' "$spec_md")"
  # Stage 2: extract backtick-wrapped tokens that match the identifier shape.
  # Pattern is anchored on the regex `[A-Za-z_][A-Za-z0-9_]{3,}` inside
  # backticks. We grep with -oE for token-with-backticks, then strip the
  # backticks via tr.
  printf '%s\n' "$stage1" \
    | grep -oE '`[A-Za-z_][A-Za-z0-9_]{3,}`' \
    | tr -d '`' \
    | sort -u
}

# ---------------------------------------------------------------------------
# Internal: parse the inline YAML `packages: [...]` line in a spec.md
# frontmatter and emit one entry per line on stdout. Strips surrounding
# whitespace and quote characters. Handles empty list (returns nothing).
# Non-list shapes (block style) are not supported in v1 — the spec contract
# requires the inline-list shape.
# ---------------------------------------------------------------------------
_revise_parse_packages() {
  local spec_md="$1"
  local fm packages_line content
  fm="$(_revise_extract_frontmatter "$spec_md")"
  packages_line="$(printf '%s\n' "$fm" | grep -E '^packages:' || true)"
  if [ -z "$packages_line" ]; then
    return 0
  fi
  # Extract content between the first `[` and last `]`.
  content="$(printf '%s' "$packages_line" | sed -n 's/^packages:[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p')"
  if [ -z "$content" ]; then
    return 0
  fi
  # Split by comma, trim whitespace and surrounding double quotes.
  printf '%s' "$content" | awk -v RS=',' '
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      gsub(/^"|"$/, "")
      if (length($0) > 0) print
    }
  '
}

# ---------------------------------------------------------------------------
# validate_packages <spec.md path> <repo root>
#
# Validates each entry in the spec.md's `packages:` list:
#   - Rejects entries containing glob characters (`*`, `?`, `[`, `]`).
#   - Rejects entries containing `..` (path escape).
#   - Rejects entries that don't resolve to an existing file or directory
#     under the repo root.
# Accepts an empty list. Exits non-zero with stderr naming the offending
# entry on any rejection.
# ---------------------------------------------------------------------------
validate_packages() {
  local spec_md="$1"
  local repo_root="$2"
  local entry
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    # Non-string sentinel: an entry that begins with `{` or `[` came from a
    # non-string YAML structure (inline mapping / nested list) that survived
    # our naive split. Reject.
    case "$entry" in
      \{*|\[*)
        echo "validate_packages: non-string entry '$entry' is not supported" >&2
        return 1
        ;;
    esac
    # Glob characters.
    case "$entry" in
      *\**|*\?*)
        echo "validate_packages: entry '$entry' contains glob/wildcard characters; globs are not supported in v1" >&2
        return 1
        ;;
    esac
    # Path escape.
    case "$entry" in
      *..*)
        echo "validate_packages: entry '$entry' contains '..' (path escape outside repo); not supported" >&2
        return 1
        ;;
    esac
    # Existence under repo root.
    if [ ! -e "$repo_root/$entry" ]; then
      echo "validate_packages: entry '$entry' does not resolve to an existing file or directory under repo root" >&2
      return 1
    fi
  done < <(_revise_parse_packages "$spec_md")
  return 0
}

# ---------------------------------------------------------------------------
# run_cross_check <spec.md path> <repo root>
#
# Orchestrates the optional code cross-check. If `packages:` is empty,
# prints a skip warning to stdout and returns zero. Otherwise validates
# packages, extracts identifiers, and runs a portable recursive grep across
# each package entry. Tokens with zero matches across all paths are
# emitted to stdout (one per line) as drift items. Implements spec 0015
# §Mechanism step 6 and AC7.
# ---------------------------------------------------------------------------
run_cross_check() {
  local spec_md="$1"
  local repo_root="$2"
  local entries token found pkg
  entries="$(_revise_parse_packages "$spec_md")"
  if [ -z "$entries" ]; then
    echo "packages[] empty — skipping code cross-check"
    return 0
  fi
  validate_packages "$spec_md" "$repo_root" || return 1
  # For each extracted token, search across each package entry. Emit tokens
  # that match in zero paths.
  while IFS= read -r token; do
    [ -z "$token" ] && continue
    found=0
    while IFS= read -r pkg; do
      [ -z "$pkg" ] && continue
      local target="$repo_root/$pkg"
      if [ -d "$target" ]; then
        if find "$target" -type f -print0 2>/dev/null \
           | xargs -0 grep -l -- "$token" 2>/dev/null \
           | grep -q .; then
          found=1
          break
        fi
      elif [ -f "$target" ]; then
        if grep -l -- "$token" "$target" >/dev/null 2>&1; then
          found=1
          break
        fi
      fi
    done <<< "$entries"
    if [ "$found" = "0" ]; then
      echo "$token"
    fi
  done < <(extract_identifiers "$spec_md")
  return 0
}

# ---------------------------------------------------------------------------
# Internal: extract the four command-owned frontmatter fields (id, created,
# revision, status) from spec.md into a sorted key=value text shape suitable
# for byte-comparison. Missing fields produce a `<key>=<MISSING>` line so a
# field-absence change is also caught.
# ---------------------------------------------------------------------------
_revise_extract_owned_fm() {
  local spec_md="$1"
  local fm key value
  fm="$(_revise_extract_frontmatter "$spec_md")"
  for key in id created revision status; do
    value="$(printf '%s\n' "$fm" | awk -v k="$key" '
      $0 ~ "^"k":" {
        sub("^"k":[[:space:]]*", "")
        print
        exit
      }
    ')"
    if [ -z "$value" ]; then
      printf '%s=<MISSING>\n' "$key"
    else
      printf '%s=%s\n' "$key" "$value"
    fi
  done | sort
}

# ---------------------------------------------------------------------------
# snapshot_spec <spec.md path> <snapshot dir>
#
# Captures the pre-revise state of spec.md for later integrity and no-op
# comparison. Writes two files into the snapshot dir:
#   spec.md.pre        — verbatim copy of spec.md
#   frontmatter.pre    — sorted key=value lines for the four command-owned
#                        fields (id, created, revision, status)
# Implements spec 0015 §Mechanism step 3.
# ---------------------------------------------------------------------------
snapshot_spec() {
  local spec_md="$1"
  local snap_dir="$2"
  [ -f "$spec_md" ] || { echo "snapshot_spec: $spec_md not found" >&2; return 1; }
  mkdir -p "$snap_dir"
  cp "$spec_md" "$snap_dir/spec.md.pre"
  _revise_extract_owned_fm "$spec_md" > "$snap_dir/frontmatter.pre"
}

# ---------------------------------------------------------------------------
# frontmatter_integrity_check <spec.md path> <snapshot dir>
#
# Compares the current command-owned frontmatter (id, created, revision,
# status) against the snapshot captured by `snapshot_spec`. Exits non-zero
# naming the changed key(s) if any of the four differ. Used post-spec-reviser
# to structurally enforce the prose contract that the agent must not modify
# command-owned frontmatter (see review.md round-2 concern #3).
# ---------------------------------------------------------------------------
frontmatter_integrity_check() {
  local spec_md="$1"
  local snap_dir="$2"
  local snap_file="$snap_dir/frontmatter.pre"
  [ -f "$snap_file" ] || { echo "frontmatter_integrity_check: snapshot $snap_file not found" >&2; return 1; }
  local current_fm tmp_current diff_output
  current_fm="$(_revise_extract_owned_fm "$spec_md")"
  tmp_current="$(mktemp)"
  printf '%s\n' "$current_fm" > "$tmp_current"
  if cmp -s "$snap_file" "$tmp_current"; then
    rm -f "$tmp_current"
    return 0
  fi
  diff_output="$(diff "$snap_file" "$tmp_current" || true)"
  rm -f "$tmp_current"
  # Identify the changed keys from the diff output.
  local changed
  changed="$(printf '%s\n' "$diff_output" | awk -F= '/^[<>] / { sub(/^[<>] /, ""); print $1 }' | sort -u | tr '\n' ' ')"
  echo "frontmatter_integrity_check: command-owned frontmatter changed: $changed (these fields must not be edited by spec-reviser)" >&2
  return 1
}

# ---------------------------------------------------------------------------
# diff_against_snapshot <spec.md path> <snapshot dir>
#
# Reports `no-op` to stdout if the current spec.md is byte-identical to the
# pre-revise snapshot OR differs only in (a) trailing horizontal whitespace
# on individual lines or (b) trailing blank lines / terminal newline.
# Reports `changed` otherwise. Always exits zero; callers branch on stdout
# value. Implements spec 0015 §Mechanism step 8/9 and the AC6 no-op
# detection contract.
# ---------------------------------------------------------------------------
diff_against_snapshot() {
  local spec_md="$1"
  local snap_dir="$2"
  local snap_file="$snap_dir/spec.md.pre"
  [ -f "$snap_file" ] || { echo "diff_against_snapshot: snapshot $snap_file not found" >&2; return 1; }
  local norm_pre norm_cur
  norm_pre="$(mktemp)"
  norm_cur="$(mktemp)"
  # Normalisation: strip trailing horizontal whitespace from every line,
  # then strip trailing blank lines and any terminal newline.
  sed 's/[[:space:]]*$//' "$snap_file" | awk '
    { lines[NR] = $0 }
    END {
      n = NR
      while (n > 0 && lines[n] == "") n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ' > "$norm_pre"
  sed 's/[[:space:]]*$//' "$spec_md" | awk '
    { lines[NR] = $0 }
    END {
      n = NR
      while (n > 0 && lines[n] == "") n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ' > "$norm_cur"
  if cmp -s "$norm_pre" "$norm_cur"; then
    echo "no-op"
  else
    echo "changed"
  fi
  rm -f "$norm_pre" "$norm_cur"
  return 0
}

# ---------------------------------------------------------------------------
# bump_revision <spec.md path> <source status>
#
# Increments the `revision: N` line in spec.md frontmatter by 1, and flips
# `status:` to `draft` (a no-op for draft-source revises). Implements spec
# 0015 §Mechanism step 10a and 10c.
# ---------------------------------------------------------------------------
bump_revision() {
  local spec_md="$1"
  local source_status="$2"
  [ -f "$spec_md" ] || { echo "bump_revision: $spec_md not found" >&2; return 1; }
  local current new_rev
  current="$(grep -E '^revision:[[:space:]]*[0-9]+' "$spec_md" | head -1 | sed -E 's/^revision:[[:space:]]*([0-9]+).*/\1/')"
  if [ -z "$current" ]; then
    echo "bump_revision: $spec_md has no revision: N field (run ensure_revision_field first)" >&2
    return 1
  fi
  new_rev=$((current + 1))
  sed -i.bak -E "s/^revision:[[:space:]]*[0-9]+/revision: ${new_rev}/" "$spec_md"
  rm -f "${spec_md}.bak"
  # Flip status to draft (idempotent for draft-source). `source_status` is
  # accepted as a documentation hint for callers; the flip itself is
  # status-blind to keep the helper simple.
  case "$source_status" in
    draft|reviewed|planned)
      sed -i.bak -E 's/^status:[[:space:]]*(draft|reviewed|planned)/status: draft/' "$spec_md"
      rm -f "${spec_md}.bak"
      ;;
    *)
      echo "bump_revision: unknown source status '$source_status' (expected: draft, reviewed, planned)" >&2
      return 1
      ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# archive_rename <spec dir> <source status> <N_old>
#
# Renames stale review/plan/tasks artifacts per the source status:
#   reviewed → review.md → review-r<N_old>.md
#   planned  → review.md → review-r<N_old>.md, plan.md → plan-r<N_old>.md,
#              tasks.md → tasks-r<N_old>.md
#   draft    → no-op
# Implements spec 0015 §Mechanism step 10b.
# ---------------------------------------------------------------------------
archive_rename() {
  local spec_dir="$1"
  local source_status="$2"
  local n_old="$3"
  case "$source_status" in
    reviewed)
      mv "$spec_dir/review.md" "$spec_dir/review-r${n_old}.md" \
        || { echo "archive_rename: failed to rename review.md" >&2; return 1; }
      ;;
    planned)
      mv "$spec_dir/review.md" "$spec_dir/review-r${n_old}.md" \
        || { echo "archive_rename: failed to rename review.md" >&2; return 1; }
      mv "$spec_dir/plan.md" "$spec_dir/plan-r${n_old}.md" \
        || { echo "archive_rename: failed to rename plan.md" >&2; return 1; }
      mv "$spec_dir/tasks.md" "$spec_dir/tasks-r${n_old}.md" \
        || { echo "archive_rename: failed to rename tasks.md" >&2; return 1; }
      ;;
    draft)
      return 0
      ;;
    *)
      echo "archive_rename: unknown source status '$source_status' (expected: draft, reviewed, planned)" >&2
      return 1
      ;;
  esac
  return 0
}
