#!/usr/bin/env bats
# Spec 0054 ACs 18 / 18a — the `reviewer` subagent definition, and the naming
# contrast against `cross-reviewer`.
#
# The `subagent` dispatch mode launches a reviewer inside THIS session via the
# Agent tool. Unlike a CLI reviewer, it inherits no sandbox of its own: its
# only confinement is the `tools:` list in its own frontmatter. So that list is
# a security boundary and is pinned here EXACTLY — a widened entry must red,
# not merely be noticed.
#
# Everything here is an assertion over MARKDOWN. A subagent definition is
# executed by a model, so its text is the implementation.
#
# AC18a exists because the two names are one word apart. `speccraft:reviewer`
# reviews ONE document and returns ONE verdict; `speccraft:cross-reviewer`
# synthesizes MANY verdicts into one review.md. Dispatching either where the
# other is meant produces a confident, wrong round — a synthesizer handed one
# payload "agrees with itself", and a reviewer handed N responses reviews the
# responses rather than the spec.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  REVIEWER="$PLUGIN_DIR/agents/reviewer.md"
  CROSS="$PLUGIN_DIR/agents/cross-reviewer.md"
  AUX_SKILL="$PLUGIN_DIR/skills/aux-agents/SKILL.md"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# fm <file> <key> — the value of a top-level frontmatter key, from the FIRST
# `---`-delimited block only. Reading the whole file would let a `tools:` line
# inside a fenced example satisfy a frontmatter assertion.
fm() {
  awk -v key="$2" '
    NR == 1 && $0 == "---" { inb = 1; next }
    inb && $0 == "---"     { exit }
    inb {
      k = $0; sub(/:.*/, "", k)
      if (k == key) { v = $0; sub(/^[^:]*:[ \t]*/, "", v); print v; exit }
    }
  ' "$1"
}

# flat <file> — the file with newlines collapsed to spaces. Prose assertions
# must not depend on where markdown happened to wrap a sentence; a line-based
# grep silently misses any phrase that straddles a break.
flat() {
  tr '\n' ' ' < "$1"
}

# first_prose <file> <n> — the first n non-blank lines of the BODY, i.e. after
# the frontmatter. "In its first lines" has to mean the body's opening, not the
# description field, or a one-word description would satisfy AC18a.
first_prose() {
  awk -v n="$2" '
    NR == 1 && $0 == "---" { inb = 1; next }
    inb && $0 == "---"     { inb = 0; body = 1; next }
    body && NF             { print; c++; if (c >= n) exit }
  ' "$1"
}

# ---------------------------------------------------------------------------
# AC18 — frontmatter
# ---------------------------------------------------------------------------

@test "agents/reviewer.md exists" {
  [ -f "$REVIEWER" ]
}

@test "agents/reviewer.md frontmatter name is reviewer" {
  [ "$(fm "$REVIEWER" name)" = "reviewer" ]
}

@test "the frontmatter reader really reads only the frontmatter" {
  # Premise for every fm-based row below: a key appearing after the first
  # block must NOT be found, or a fenced example could satisfy a security
  # assertion about the tools list.
  cat > "$TEST_DIR/decoy.md" <<'DECOY'
---
name: real-name
---

Body text.

```yaml
name: decoy-name
tools: [Edit, Bash]
```
DECOY
  [ "$(fm "$TEST_DIR/decoy.md" name)" = "real-name" ]
  [ -z "$(fm "$TEST_DIR/decoy.md" tools)" ]
}

@test "its tools are exactly Read, Grep, Glob, Bash(shasum:*), Bash(sha256sum:*), Write" {
  # Pinned EXACTLY, not by membership: this list is the subagent's only
  # confinement, so an added entry has to red rather than pass unnoticed.
  [ "$(fm "$REVIEWER" tools)" = "[Read, Grep, Glob, Bash(shasum:*), Bash(sha256sum:*), Write]" ]
}

@test "its model is inherit" {
  # AC19's no-model case relies on this: when the registry names no model, the
  # runbook passes none and the reviewer runs on the session's own model. A
  # concrete model here would silently override every such round.
  [ "$(fm "$REVIEWER" model)" = "inherit" ]
}

@test "it declares no Edit" {
  # A reviewer that can Edit can rewrite the very document it is judging.
  local tools
  tools="$(fm "$REVIEWER" tools)"
  [ -n "$tools" ] || { echo "no tools line found; this row would pass vacuously" >&2; return 1; }
  printf '%s\n' "$tools" | grep -qE '(^|[][ ,])Edit([][ ,]|$)' && {
    echo "reviewer.md declares Edit: $tools" >&2
    return 1
  }
  return 0
}

@test "it declares no bare Bash" {
  # Mechanical scoping is the point: `Bash` unqualified is every command on the
  # machine, which makes the two Bash(...) entries decorative.
  local tools
  tools="$(fm "$REVIEWER" tools)"
  [ -n "$tools" ] || { echo "no tools line found; this row would pass vacuously" >&2; return 1; }
  printf '%s\n' "$tools" | grep -qE '(^|[][ ,])Bash([][ ,]|$)' && {
    echo "reviewer.md declares a bare Bash: $tools" >&2
    return 1
  }
  return 0
}

@test "the Edit and bare-Bash guards bite on lists that contain them" {
  # Prove both negatives above are real. `Bash(shasum:*)` must NOT trip the
  # bare-Bash pattern, and `Edit` inside `EditFile` must NOT trip the Edit one;
  # a sloppy substring check would do both and then never fail for a real cause.
  local bad good
  for bad in \
    '[Read, Edit, Write]' \
    '[Read, Write, Edit]' \
    '[Edit]'; do
    printf '%s\n' "$bad" | grep -qE '(^|[][ ,])Edit([][ ,]|$)' || {
      echo "the Edit guard missed: $bad" >&2
      return 1
    }
  done
  for bad in \
    '[Read, Bash, Write]' \
    '[Bash]' \
    '[Read, Write, Bash]'; do
    printf '%s\n' "$bad" | grep -qE '(^|[][ ,])Bash([][ ,]|$)' || {
      echo "the bare-Bash guard missed: $bad" >&2
      return 1
    }
  done
  for good in \
    '[Read, Bash(shasum:*), Bash(sha256sum:*), Write]' \
    '[Read, EditFile, Write]'; do
    printf '%s\n' "$good" | grep -qE '(^|[][ ,])(Edit|Bash)([][ ,]|$)' && {
      echo "a guard false-positived on the legitimate list: $good" >&2
      return 1
    }
  done
  return 0
}

# ---------------------------------------------------------------------------
# AC18 — body instructions
# ---------------------------------------------------------------------------

@test "its body instructs reading the payload by path, never pasted content" {
  # The whole point of the one-artifact contract: the reviewer opens the file
  # whose digest it then attests. A pasted payload cannot be attested at all.
  grep -qiE 'read .*payload.*(by|from) (its )?path|payload file .*path' "$REVIEWER" || {
    echo "reviewer.md does not instruct reading the payload by path:" >&2
    grep -niF 'payload' "$REVIEWER" >&2
    return 1
  }
}

@test "its body instructs reporting payload_sha256" {
  grep -qF 'payload_sha256' "$REVIEWER"
}

@test "its body instructs reporting permission_denied" {
  # A tool refused mid-review is OUR dispatch bug. A reviewer that silently
  # skips the file instead returns a verdict about bytes it never read.
  grep -qF 'permission_denied' "$REVIEWER"
}

@test "its body names the speccraft verdict vocabulary" {
  # Read from the lib rather than retyped, so the two can never drift: the lib
  # is what classifies the recorded outcome.
  local v vocab
  vocab="$(grep -E '^REVIEW_VERDICTS=' "$LIB" | sed 's/^[^=]*="//; s/"$//')"
  [ -n "$vocab" ] || { echo "could not read REVIEW_VERDICTS from the lib" >&2; return 1; }
  for v in $vocab; do
    grep -qF "$v" "$REVIEWER" || {
      echo "reviewer.md never names the verdict '$v'" >&2
      return 1
    }
  done
}

@test "its body confines Write to the round dir's own agent artifact" {
  grep -qE '<round-dir>/<agent>\.out|\$ROUND_DIR/<agent>\.out' "$REVIEWER" || {
    echo "reviewer.md does not name <round-dir>/<agent>.out as its output:" >&2
    grep -niE 'write|\.out' "$REVIEWER" >&2
    return 1
  }
}

@test "its body forbids writing any other path" {
  # Write is in the tools list because the reviewer must produce an artifact
  # the round reads from disk (AC17a). Nothing scopes that tool to one path
  # mechanically, so the prohibition has to be stated.
  grep -qiE 'no other path|never write (any )?other|only file you (may )?write' "$REVIEWER" || {
    echo "reviewer.md does not forbid writing other paths:" >&2
    grep -niE 'write' "$REVIEWER" >&2
    return 1
  }
}

# Both halves of the no-transcription contract, each anchored on the REPLY.
# A first draft of these patterns was satisfied by "reference bodies are
# deliberately not pasted" — true, unrelated prose about a different file — so
# deleting the whole paragraph left the row green.
ARTIFACT_IS_RESPONSE_RE='artifact IS your response|artifact is the (verdict|output|answer)'
NO_TRANSCRIBE_RE='(do not|never) (also )?(transcribe|paste)[^.]*(reply|orchestrator|Agent result)'

@test "its body tells the reviewer not to transcribe its verdict into the reply" {
  # AC17a: the round reads <agent>.out from disk. A reviewer that also pastes
  # its verdict into the Agent result invites the orchestrator to record the
  # pasted copy, and then the artifact's digest attests nothing.
  flat "$REVIEWER" | grep -qE "$ARTIFACT_IS_RESPONSE_RE" || {
    echo "reviewer.md does not say the artifact IS the response:" >&2
    grep -niE 'artifact|reply|respon' "$REVIEWER" >&2
    return 1
  }
  flat "$REVIEWER" | grep -qiE "$NO_TRANSCRIBE_RE" || {
    echo "reviewer.md does not forbid transcribing the verdict into the reply:" >&2
    grep -niE 'transcribe|paste' "$REVIEWER" >&2
    return 1
  }
}

@test "the no-transcription patterns are not satisfied by the reference-tier prose" {
  # Premise for the row above. The payload prose legitimately says reference
  # bodies "are deliberately not pasted"; that sentence must satisfy NEITHER
  # pattern, or the whole response contract can be deleted without a red.
  printf 'Their bodies are deliberately not pasted. Nothing is pasted into your prompt.\n' \
    > "$TEST_DIR/reference-prose"
  flat "$TEST_DIR/reference-prose" | grep -qE "$ARTIFACT_IS_RESPONSE_RE" && {
    echo "the artifact-is-response pattern matched unrelated reference prose" >&2
    return 1
  }
  flat "$TEST_DIR/reference-prose" | grep -qiE "$NO_TRANSCRIBE_RE" && {
    echo "the no-transcribe pattern matched unrelated reference prose" >&2
    return 1
  }
  # And both must match the real contract sentences — across a line break,
  # which is why the assertions flatten the file first. A line-based grep
  # would miss a sentence that markdown happened to wrap.
  cat > "$TEST_DIR/real-prose" <<'REAL'
That artifact IS your response. The round reads it from disk. Do not also
transcribe your verdict into the reply you return to the orchestrator.
REAL
  flat "$TEST_DIR/real-prose" | grep -qE "$ARTIFACT_IS_RESPONSE_RE" || {
    echo "the artifact-is-response pattern misses the real sentence" >&2
    return 1
  }
  flat "$TEST_DIR/real-prose" | grep -qiE "$NO_TRANSCRIBE_RE" || {
    echo "the no-transcribe pattern misses the real sentence" >&2
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# AC18a — the naming contrast
# ---------------------------------------------------------------------------

@test "agents/reviewer.md states the reviewer-vs-synthesizer contrast in its first lines" {
  local head
  head="$(first_prose "$REVIEWER" 6)"
  printf '%s\n' "$head" | grep -qF 'cross-reviewer' || {
    echo "reviewer.md's opening does not contrast itself with cross-reviewer:" >&2
    printf '%s\n' "$head" >&2
    return 1
  }
}

# `reviewer` as its OWN word — not the tail of `cross-reviewer`. A plain
# `\breviewer\b` matches inside `cross-reviewer`, because `-` is a word
# boundary, so every such row passed on the file's existing first sentence
# without the contrast ever being written.
BARE_REVIEWER_RE='(^|[^-[:alnum:]])reviewer\b'

@test "agents/cross-reviewer.md states the contrast in its first lines" {
  local head
  head="$(first_prose "$CROSS" 6)"
  printf '%s\n' "$head" | grep -qE "$BARE_REVIEWER_RE" || {
    echo "cross-reviewer.md's opening does not name the per-document reviewer:" >&2
    printf '%s\n' "$head" >&2
    return 1
  }
}

@test "the bare-reviewer pattern does not match the tail of cross-reviewer" {
  # Premise for the row above. Without this, that row passes on any file whose
  # opening merely says "You are the cross-reviewer".
  printf 'You are the cross-reviewer. Your job is to synthesize.\n' > "$TEST_DIR/only-cross"
  grep -qE "$BARE_REVIEWER_RE" "$TEST_DIR/only-cross" && {
    echo "the pattern matched 'cross-reviewer' alone, so the row is vacuous" >&2
    return 1
  }
  printf 'Unlike the reviewer subagent, you read no document yourself.\n' > "$TEST_DIR/has-both"
  grep -qE "$BARE_REVIEWER_RE" "$TEST_DIR/has-both" || {
    echo "the pattern missed a genuine mention of the reviewer" >&2
    return 1
  }
  return 0
}

@test "reviewer.md describes reviewing ONE document, not synthesizing many" {
  local head
  head="$(first_prose "$REVIEWER" 6)"
  printf '%s\n' "$head" | grep -qiE 'one (document|payload|spec)|a single (document|payload)' || {
    echo "reviewer.md's opening does not say it reviews one document:" >&2
    printf '%s\n' "$head" >&2
    return 1
  }
}

@test "neither file describes itself with the other's role" {
  # reviewer.md must not claim to synthesize, and cross-reviewer.md must not
  # claim to produce a verdict of its own by reading the document.
  local head
  head="$(first_prose "$REVIEWER" 6)"
  printf '%s\n' "$head" | grep -qiE 'you (are the cross-reviewer|synthesize)' && {
    echo "reviewer.md describes itself as the synthesizer:" >&2
    printf '%s\n' "$head" >&2
    return 1
  }
  head="$(first_prose "$CROSS" 6)"
  printf '%s\n' "$head" | grep -qiE 'you are the reviewer\b' && {
    echo "cross-reviewer.md describes itself as the reviewer:" >&2
    printf '%s\n' "$head" >&2
    return 1
  }
  return 0
}

@test "the self-description guard bites on a swapped opening" {
  # Prove the row above is real by running its patterns over the openings each
  # file must NOT have.
  printf 'You are the cross-reviewer. You synthesize many verdicts.\n' > "$TEST_DIR/swapped-reviewer"
  grep -qiE 'you (are the cross-reviewer|synthesize)' "$TEST_DIR/swapped-reviewer" || {
    echo "the reviewer-side guard does not match a swapped opening" >&2
    return 1
  }
  printf 'You are the reviewer. You read the document and return a verdict.\n' > "$TEST_DIR/swapped-cross"
  grep -qiE 'you are the reviewer\b' "$TEST_DIR/swapped-cross" || {
    echo "the cross-reviewer-side guard does not match a swapped opening" >&2
    return 1
  }
}

@test "skills/aux-agents/SKILL.md documents both names" {
  grep -qE '^#+ .*\breviewer\b' "$AUX_SKILL" || {
    echo "aux-agents skill has no section for the reviewer subagent:" >&2
    grep -nE '^#+' "$AUX_SKILL" >&2
    return 1
  }
  grep -qF 'cross-reviewer' "$AUX_SKILL" || {
    echo "aux-agents skill never names cross-reviewer" >&2
    return 1
  }
}

@test "the aux-agents skill states which of the two to dispatch when" {
  # Documenting both names without the distinction is how the wrong one gets
  # dispatched. The skill is what a model reads when deciding.
  grep -qiE 'synthesi' "$AUX_SKILL" || {
    echo "aux-agents skill does not distinguish the synthesizer:" >&2
    grep -niF 'reviewer' "$AUX_SKILL" >&2
    return 1
  }
}

@test "the plugin registers the reviewer agent under the speccraft prefix" {
  # The runbook and the Go loader both default subagent_type to
  # `speccraft:reviewer`. That resolves to agents/reviewer.md only because the
  # file's frontmatter name is the bare `reviewer` — pinned above — so this row
  # ties the dispatch default to the file that answers it.
  local default
  default="$(grep -oE 'a\.SubagentType = "[^"]+"' "$PLUGIN_DIR/tools/internal/delegate/toml.go" \
    | head -1 | sed 's/.*"\(.*\)"/\1/')"
  [ -n "$default" ] || { echo "could not read the Go default" >&2; return 1; }
  [ "$default" = "speccraft:$(fm "$REVIEWER" name)" ] || {
    echo "the dispatch default '$default' does not name agents/reviewer.md" >&2
    return 1
  }
}
