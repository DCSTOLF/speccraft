---
spec: "0014"
status: planned
strategy: tdd
---

# Plan — 0014 Tighten e2e history.md assertion to ADR structural match

## Notes for executor

This is a **Bash test-harness fix**, not Go production code. The spec-0012
`speccraft-guard` red-phase gate only fires on production-language edits;
edits under `tests/e2e/` are test infrastructure and do not trigger it.
TDD discipline still applies in spirit: we drive the change by adding a
new fixture (`tests/e2e/contains_adr_assertion_test.sh`) that exercises
the **exact predicate** the production assertion uses, and we wire that
fixture into the language-only CI job before flipping the production
assertion site.

The RED→GREEN framing for this spec:
- **RED** = the new fixture sources `tests/e2e/lib.sh` (which does not
  exist yet); running the fixture fails with `No such file or directory`.
- **GREEN** = `tests/e2e/lib.sh` exists with `contains_regex` (and
  the other shared helpers), both `run.sh` and the new fixture source
  it, both fixture cases (positive + negative) behave as asserted.

### Critical sequencing constraints

- T1 (create `lib.sh`) must precede T2 (refactor `run.sh` to source it)
  because dropping helper definitions from `run.sh` while `lib.sh` is
  empty would break every existing fixture invocation.
- T2 must precede T3 (write the new fixture) because the fixture
  sources `lib.sh`; if `lib.sh` were created in T3 alongside the
  fixture, the spec's "exact predicate" invariant would be unverified
  for `run.sh`'s consumption path until T5.
- T3 must precede T5 (flip the brittle assertion) because the
  assertion flip and the new fixture together codify a single
  predicate. Reversing the order would leave a window in which the
  production assertion uses `contains_regex` but the fixture that
  proves the predicate's shape doesn't yet exist.
- T4 (wire `run_helper_unit_tests`) must precede T7 (verification),
  otherwise the language-only CI job will not pick the new fixture
  up.

### Load-bearing decision: `fail()` lives in `lib.sh` (option A)

`run.sh`'s existing `fail()` references `$LAST_LOG` and `$LOG_DIR` —
harness state set in `run.sh`'s main body. The new fixture will not
have those set. We resolve this by **moving `fail()` to `lib.sh` and
guarding the log-cat block with a `[ -n "${LAST_LOG:-}" ] && [ -n
"${LOG_DIR:-}" ] && [ -f "$LOG_DIR/$LAST_LOG" ]` check**. When unset
(fixture context), `fail()` still exits 2 with the message but skips
the log dump. This preserves `run.sh`'s existing behavior unchanged
in lifecycle context, and gives the fixture the same `fail()` exit
contract (exit 2) the conventions require.

Why option A over a minimal-`lib.sh` (option B, which would keep
`fail()` in `run.sh`): the spec's AC2 invariant is that the fixture
exercises **the exact predicate** the production assertion uses.
Option A keeps the entire helper layer identical between `run.sh`
and the fixture — same `contains_regex`, same `fail()`, same
`pass()`. Option B introduces asymmetric fail semantics (different
fail functions on either side of the predicate boundary) and weakens
the invariant.

### Source-path resolution for `run.sh → lib.sh`

`run.sh` already captures `E2E_DIR` from `${BASH_SOURCE[0]}` at line 23
**before** any `cd`. The `source` line goes immediately after that
`E2E_DIR=` assignment and reads:

```bash
# shellcheck source=lib.sh
source "$E2E_DIR/lib.sh"
```

This placement is load-bearing: by the time `cd "$TEST_ROOT"` runs
at line 75, `lib.sh` is already sourced and its functions are in
scope for the rest of the script.

The new fixture computes its own equivalent:

```bash
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$LIB_DIR/lib.sh"
```

### Negative-case mechanics in the fixture

The fixture's negative case asserts that `contains_regex` **fails**
(exits non-zero) on the bare template-only history. Naively writing
`contains_regex "$tmp/history.md" "^## 20…"` would exit the fixture
via `fail()` (exit 2). The fixture inverts the check by running
`contains_regex` in a subshell with `set +e`-style inversion:

```bash
if ( contains_regex "$tmp_neg/history.md" "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}" ) 2>/dev/null; then
  fail "negative case: contains_regex unexpectedly matched template-only history.md"
fi
note "negative case: contains_regex correctly rejected template-only history.md"
```

This pattern is non-obvious bash; it is documented inline in the
fixture and called out here so reviewers don't accidentally
"simplify" it into a form that breaks under `set -e`.

## Test-first sequence

### Step 1 — Extract assertion helpers into `tests/e2e/lib.sh` (GREEN-setup)
- Add `tests/e2e/lib.sh` (new file, marked executable not required;
  sourced, not executed):
  - `#!/usr/bin/env bash` shebang + `set -euo pipefail` per the
    repository Bash convention (defensive — the file is sourced, but
    the shebang documents intent and `set -euo pipefail` becomes
    active in the sourcing shell if not already set).
  - `fail()` — moved verbatim from `run.sh`, log-cat block guarded
    with `[ -n "${LAST_LOG:-}" ] && [ -n "${LOG_DIR:-}" ] && [ -f
    "$LOG_DIR/$LAST_LOG" ]` so it is safe to call from contexts
    (the new fixture) that don't set those vars. Always exits 2 on
    assertion failure.
  - `pass()` — moved verbatim from `run.sh`.
  - `exists()` — moved verbatim from `run.sh`.
  - `contains()` — moved verbatim from `run.sh`. Uses `grep -qF`
    (fixed-string). Unchanged semantics.
  - `contains_regex()` — NEW. Mirrors `contains()`'s pass/fail shape
    but uses `grep -qE` so callers can pass an extended regex.
    Signature: `contains_regex <file> <pattern>`. On match: `pass
    "contains_regex $1: $2"`. On miss: `fail "expected regex '$2'
    in $1"`.
  - `status_is()` — moved verbatim from `run.sh`.
- This is a pre-RED setup step. No test exercises `lib.sh` directly
  yet; T3 builds the fixture that does.

### Step 2 — Refactor `run.sh` to source `lib.sh` (GREEN-refactor)
- Edit `tests/e2e/run.sh`:
  - Add `source "$E2E_DIR/lib.sh"` immediately after the `E2E_DIR=`
    assignment at line 23 (i.e. between line 23 and the blank line
    before the flag parser at line 25).
  - Delete the now-duplicated definitions of `fail()`, `pass()`,
    `exists()`, `contains()`, `status_is()` from `run.sh` (lines
    100-120 in current `run.sh`).
  - Keep `LAST_LOG=""` at module scope in `run.sh` — `fail()` in
    `lib.sh` references it via the guarded check, and `run_claude`
    in `run.sh` continues to write it.
- Verification (manual, run after the edit): `bash tests/e2e/run.sh
  --language-only` runs to completion locally — all four existing
  language cycles pass with the helper functions sourced rather
  than locally defined.

### Step 3 — RED+GREEN for the new fixture (TDD core)
- Add `tests/e2e/contains_adr_assertion_test.sh` (executable):
  - `#!/usr/bin/env bash` + `set -euo pipefail` per the Bash
    convention.
  - Resolve `LIB_DIR` from `${BASH_SOURCE[0]}` per the convention
    "Use absolute paths derived from `${BASH_SOURCE[0]}`".
  - `source "$LIB_DIR/lib.sh"`.
  - AC3 precondition sanity check (runs once at fixture start):
    ```bash
    REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
    if grep -nE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}' \
         "$REPO_ROOT/templates/speccraft/history.md" >/dev/null; then
      fail "AC3 precondition: templates/speccraft/history.md unexpectedly contains a date-anchored ADR header"
    fi
    note "AC3 precondition: templates/speccraft/history.md has no date-anchored ADR header"
    ```
  - **Positive case** in `mktemp -d -t adr-assert-pos.XXXXXX` work
    dir:
    - Write `history.md` with `# History\n\nAppend-only. Newest
      first.\n\n## 2026-06-10 — Sample (spec 0001)\n\nbody\n`.
    - Call `contains_regex "$tmp_pos/history.md" "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}"`.
    - Helper invokes `pass` on match, fixture continues. On
      mismatch the helper would call `fail` (exit 2) and the
      fixture exits red.
  - **Negative case** in `mktemp -d -t adr-assert-neg.XXXXXX` work
    dir:
    - Write `history.md` with **only** `# History\n\nAppend-only.
      Newest first.\n` (no ADR yet — mirrors the bare template).
    - Run `contains_regex` in a subshell and invert exit per the
      "Negative-case mechanics" note above.
  - On all checks passing: `echo "PASS:
    contains_adr_assertion_test.sh"` and `exit 0`.
- New named helper `note()` mirrored from `python_cycle.sh` for
  intra-scenario progress lines, per the
  E2E-language-fixture-pattern convention (even though this
  fixture is not a language fixture per se, the cosmetic conform
  keeps reading-style uniform across `tests/e2e/`).
- **RED check (verifiable mid-step)**: temporarily remove
  `contains_regex` from `lib.sh` and run the fixture; it must exit
  non-zero with `contains_regex: command not found` (or similar).
  Restore `contains_regex` and re-run; positive case passes,
  negative case correctly rejects, fixture exits 0. (This is a
  belt-and-braces check the executor performs locally; it does
  not leave a committed RED step.)
- **GREEN end state**: positive case `PASS`, negative case
  inverted-fail correctly handled, fixture exits 0.

### Step 4 — Wire `run_helper_unit_tests()` into `run.sh` (GREEN-wiring)
- Edit `tests/e2e/run.sh`:
  - Add a new sibling helper alongside `run_language_fixtures` at
    around line 85:
    ```bash
    run_helper_unit_tests() {
      ( bash "$E2E_DIR/contains_adr_assertion_test.sh" ) \
        || fail "contains_adr_assertion_test.sh failed"
      pass "contains_adr_assertion_test.sh"
    }
    ```
  - Call `run_helper_unit_tests` from both dispatch points where
    `run_language_fixtures` is called:
    - The `--language-only` short-circuit branch at line 196 — call
      `run_helper_unit_tests` **before** `run_language_fixtures` so
      a helper regression fails fast before the language fixtures
      run.
    - The full-lifecycle path at line 292 — same ordering.
  - The `e2e-language-only` CI job picks the new fixture up
    automatically because it executes `bash tests/e2e/run.sh
    --language-only` (per `architecture.md` §1 item 12 and per
    `conventions.md` §CI).
  - **Step counter / progress prefix**: the current `run.sh`
    headers say `[8/10]`, `[9/10]`, `[10/10]` for the language
    dispatch echo lines. The helper-unit-test step is invoked
    from the language-only short-circuit AND the lifecycle path;
    the lifecycle echo block at lines 285–291 grows by one line.
    The new echo line:
    ```bash
    echo "==> [11/11] Helper unit tests (spec 0014)"
    ```
    is added immediately above the existing `[8/10]` line, and the
    `[N/M]` denominators on existing language echoes are bumped
    from `/10` to `/11`. The renumbering is bounded and cosmetic;
    no other site reads these counters.

### Step 5 — Flip the brittle assertion site (GREEN — the actual fix)
- Edit `tests/e2e/run.sh` line 278:
  - From: `contains ".speccraft/history.md" "farewell"`
  - To:   `contains_regex ".speccraft/history.md" "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}"`
- AC1 mechanical verification (runs after the edit):
  - `grep -nF 'contains_regex ".speccraft/history.md" "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}"' tests/e2e/run.sh`
    returns exactly one match.
  - `grep -nF 'contains ".speccraft/history.md" "farewell"' tests/e2e/run.sh`
    returns zero matches.
  - The unrelated `farewell` mentions at lines 242, 264, 268, 269
    (in `/spec:new` prompt text and in `main.go` assertions) are
    intentionally untouched and remain.

### Step 6 — Refactor (optional)
- No refactor needed. The extraction in T1 is itself the
  refactor; subsequent steps reuse the extracted helper without
  duplication.

### Step 7 — Verification gate
- Local `bash tests/e2e/run.sh --language-only` runs to completion
  green, including the new helper-unit-test step.
- AC1 grep oracles both produce the expected counts (1 / 0).
- AC3 grep oracle (`grep -nE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}'
  templates/speccraft/history.md`) continues to return zero
  matches — the precondition the fixture sanity-checks at start.
- Push to a feature branch; the GitHub Actions `e2e-language-only`
  job picks up the new fixture and passes. After merge to `main`,
  the next `e2e-devcontainer` run satisfies AC4: step `[7/9]
  /speccraft:spec:close` passes the history.md assertion
  regardless of memory-keeper's ADR title — the relevant log line
  becomes `PASS: contains_regex .speccraft/history.md: ^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}`
  (per `lib.sh`'s `contains_regex` pass-line shape) instead of the
  previous `FAIL: expected 'farewell' in .speccraft/history.md`.

## Delegation

- T1 (extraction) and T2 (refactor) → keep in primary agent. Both
  are bounded bash mechanical moves; cross-model review on small
  refactors slows the cycle without finding additional risk.
- T3 (new fixture) → keep in primary agent. The fixture is small
  (~50 lines) and exercises a single predicate; the load-bearing
  decisions (sourcing path, negative-case inversion) are already
  pinned in this plan.
- T5 (assertion flip) → keep in primary agent. One-line edit at a
  pinned location.
- T7 (verification gate) → keep in primary agent. Runs are
  mechanical greps + local fixture runs.
- **No aux-agent delegation for this spec.** The work is Bash
  test-harness plumbing; codex/opencode would not add signal
  beyond the cost. Cross-model review is reserved for spec.md
  itself (already completed in `review.md`).

## Risk

- **R1: `source "$E2E_DIR/lib.sh"` placed after a `cd`.** If the
  `source` line is accidentally moved below the `cd "$TEST_ROOT"`
  at line 75, the relative resolution would still work (because
  `$E2E_DIR` is absolute), but the failure mode for any future
  edit that loses `$E2E_DIR`'s absoluteness would be silent — a
  fresh test root with no `lib.sh` next to the harness. Mitigation:
  T2 places the `source` line *immediately after* the `E2E_DIR=`
  assignment with a comment explaining why; T7 verifies by running
  `--language-only` end-to-end.
- **R2: `fail()` log-cat block leaks log output to fixture
  stderr.** If the `[ -n "${LAST_LOG:-}" ] && [ -n "${LOG_DIR:-}" ]
  && [ -f "$LOG_DIR/$LAST_LOG" ]` guard is wrong, calling `fail`
  from the new fixture (where both vars are unset) could
  unintentionally cat a stale log or fail the guard expression
  under `set -u`. Mitigation: T1's `lib.sh` uses the
  `${VAR:-}` default-empty parameter expansion on all three
  references, so `set -u` is satisfied even when the vars are
  unset. T3's fixture exercises this exact path (its negative
  case's setup never sets `LAST_LOG` or `LOG_DIR`, so any
  inadvertent assertion failure would prove the guard works or
  doesn't).
- **R3: Step-counter renumbering breaks another script that reads
  the prefix.** Unlikely — `[N/M]` prefixes are cosmetic echo
  output, not parsed elsewhere — but a `grep '\[8/10\]'` in a CI
  log-parsing helper would silently miss the renumbered line.
  Mitigation: `grep -rnE '\[(8|9|10)/10\]' .github/ scripts/
  tests/` before T4; if any match, update in lockstep.
- **R4: AC3 precondition oracle drifts later.** A future spec that
  prepends an ADR to `templates/speccraft/history.md` (intended or
  accidental) would silently invalidate the fixture's
  setup-precondition oracle. The fixture itself catches this at
  CI run time (it `fail`s on a non-empty grep), so the drift is
  surfaced; no silent escape. No additional mitigation needed.
- **R5: The `set -euo pipefail` in `lib.sh` mutates the sourcing
  shell.** Both `run.sh` and the fixture already set this at top;
  re-applying it via the sourced file is idempotent. Risk only
  matters if a future caller sources `lib.sh` from a shell that
  intentionally has these off — that caller would need to know
  and re-toggle. Documented inline in `lib.sh`.
