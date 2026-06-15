---
spec: "0020"
status: planned
strategy: tdd
---

# Plan — 0020 Robust e2e revise no-op assertion

## Overview

The e2e step `[6/13] /speccraft:spec:revise no-op` asserts the no-op branch ran by
fixed-string grepping the live `claude -p` final-message log for `"no changes"`
(`tests/e2e/run.sh:289`, via `contains` = `grep -qF`). The model paraphrased the
deterministic marker (`no changes — spec unchanged`) as "no-op"/"byte-identical",
so the literal match missed and CI failed on phrasing, not a defect.

The fix (spec 0020) is a one-line robustness change: swap the fixed-string
`contains` at run.sh:289 for the existing `contains_regex` (= `grep -qE`) helper in
`tests/e2e/lib.sh`, with a tolerant pattern that matches the marker AND its
paraphrases:

```
[Nn]o.?op|[Nn]o changes|byte-identical|unchanged
```

The structural proof that the no-op branch actually ran — `contains_regex
"$SPEC_DIR/spec.md" "^revision: 1"` at run.sh:291 — stays unchanged and remains the
load-bearing assertion (spec 0014's structural-over-content lesson). No edit to
`commands/spec/revise.md` or `revise.lib.sh` (spec 0017: hardening model-output
compliance isn't durable).

Because this is a shell-only change with no Go hook gating it, RED→GREEN is made
genuine by mirroring the spec 0014 meta-test precedent
(`tests/e2e/contains_adr_assertion_test.sh`): a new sibling fixture
`tests/e2e/revise_noop_assertion_test.sh` that exercises the *exact* predicate the
no-op step uses, against synthetic log fixtures. Written to fail while run.sh still
uses fixed-string `contains "no changes"` and pass once run.sh switches to the
tolerant regex.

## Decision: duplication vs. extraction of the regex pattern

**Decision: duplicate the pattern string in the meta-test, with an inline comment
asserting it is the exact predicate run.sh uses — NOT a shared variable.**

Rationale (proportionality + precedent):
- The spec 0014 ADR meta-test chose duplication: it re-states the
  `^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}` predicate verbatim with a comment, rather than
  extracting it to a shared var sourced by both run.sh and the fixture. Consistency
  with the established repo convention is the default and there is no countervailing
  pressure here.
- Extraction would introduce a new shared symbol in `lib.sh` (or a new sourced
  constants file), expanding scope. The spec explicitly lists "new lib.sh helper" as
  out of scope; a shared pattern var is the same class of scope creep for a one-line
  fix.
- The "exact predicate" invariant is preserved the same way the ADR fixture
  preserves it: both sites source the same `lib.sh` (so `contains_regex`'s *semantics*
  are provably identical), and the duplicated pattern string is guarded by a comment
  plus the AC1 enumeration test (below) that pins the three required match cases.
- Drift risk (the two pattern strings diverging) is real but small and is mitigated
  by the AC1 enumeration assertions, which would fail loudly if the run.sh pattern
  were weakened.

**How RED is observed under duplication:** the meta-test does NOT call the run.sh
pattern indirectly; it independently asserts the *behavior contract* the no-op step
must satisfy — i.e. that the no-op assertion predicate matches a log containing only
`"no-op"`. To make the test couple to run.sh's actual choice (so it goes RED before
the fix and GREEN after), the meta-test extracts the live predicate from run.sh by
grepping run.sh's no-op assertion line and checking it is a `contains_regex`
call (not `contains`) whose pattern matches all three required phrasings. See Step 1.

## Test-first sequence

### Step 1 — Add the revise-no-op assertion meta-test (RED)
- Add `tests/e2e/revise_noop_assertion_test.sh` (mirrors
  `contains_adr_assertion_test.sh`): `#!/usr/bin/env bash`, `set -euo pipefail`,
  `LIB_DIR` from `${BASH_SOURCE[0]}`, `source "$LIB_DIR/lib.sh"`, `note()` helper,
  `==>` header, final `PASS:` line, exit 2 on failure via `fail()`.
- The fixture asserts three things, named as inline scenario blocks via `note()`:
  - **Scenario A — production assertion uses `contains_regex`, not `contains`
    (AC1 / AC3):** locate the no-op log assertion line in
    `tests/e2e/run.sh` (the line asserting against `06-revise-noop.log`) and
    `fail` unless it is a `contains_regex` invocation. While run.sh:289 still reads
    `contains "$LOG_DIR/06-revise-noop.log" "no changes"`, this `fail`s → RED.
  - **Scenario B — the no-op pattern matches all required phrasings (AC1):**
    extract the regex argument from that run.sh line, then for each of the three
    fixture strings — `no changes — spec unchanged`, `no-op`, `byte-identical` —
    write it to a temp file and `contains_regex "$tmp" "$PATTERN"` must pass. With
    the old fixed-string line there is no extractable `contains_regex` pattern, so
    Scenario A already fails first; once GREEN, all three must match.
  - **Scenario C — negative case (no false positive):** a log fixture containing an
    unrelated line (e.g. `the spec was extensively rewritten`) must NOT match the
    pattern; invert via subshell exactly as the ADR fixture does
    (`if ( contains_regex ... ) >/dev/null 2>&1; then fail ...; fi`).
- Tests fail: run.sh:289 still uses fixed-string `contains "no changes"`, so
  Scenario A's "must be `contains_regex`" assertion fails and the fixture exits 2
  (RED). Observe by running `bash tests/e2e/revise_noop_assertion_test.sh` directly.

### Step 2 — Wire the meta-test into the harness (RED, still failing)
- Edit `run_helper_unit_tests` in `tests/e2e/run.sh` (currently
  `tests/e2e/run.sh:113-117`) to invoke the new fixture in a subshell with `|| fail`,
  immediately after the ADR one:
  ```bash
  ( bash "$E2E_DIR/revise_noop_assertion_test.sh" ) \
    || fail "revise_noop_assertion_test.sh failed"
  pass "revise_noop_assertion_test.sh"
  ```
- This runs in both the `--language-only` path (run.sh:202) and the full-lifecycle
  path (run.sh:347), so the gate is credit-free.
- Still RED: the fixture fails because run.sh:289 is unchanged. Observe via
  `bash tests/e2e/run.sh --language-only` (no API key / credits needed) → exits 2.

### Step 3 — Make the no-op assertion tolerant (GREEN)
- Edit `tests/e2e/run.sh:289`, replacing:
  ```bash
  contains "$LOG_DIR/06-revise-noop.log" "no changes"
  ```
  with:
  ```bash
  # Tolerant: model paraphrases the no-op marker (spec 0020). Same predicate
  # pinned by revise_noop_assertion_test.sh. Structural ^revision: 1 below is
  # the load-bearing proof the no-op branch ran.
  contains_regex "$LOG_DIR/06-revise-noop.log" "[Nn]o.?op|[Nn]o changes|byte-identical|unchanged"
  ```
- Leave run.sh:291 `contains_regex "$SPEC_DIR/spec.md" "^revision: 1"` unchanged (AC2).
- GREEN: `bash tests/e2e/revise_noop_assertion_test.sh` passes (Scenario A sees
  `contains_regex`; Scenario B matches all three phrasings; Scenario C rejects the
  unrelated line). `bash tests/e2e/run.sh --language-only` passes the helper gate.

### Step 4 — Parse + lint verification (verification, not a code step)
- `bash -n tests/e2e/run.sh` parses cleanly (AC3).
- `bash -n tests/e2e/revise_noop_assertion_test.sh` parses cleanly.
- Optional: `shellcheck` both files if available in the environment.

### Step 5 — Refactor (optional)
- No duplication introduced beyond the deliberately-duplicated pattern string
  (justified above). If desired, factor the "find the no-op assertion line in
  run.sh" grep in the meta-test into a small local helper within the fixture for
  readability. Not required; the fixture is already small. All tests still pass.

## Delegation

- All steps → keep in-thread (no delegation). This is a single bash fixture plus a
  three-line run.sh diff; the work is too small and too tightly coupled to the spec
  0014 precedent to benefit from a subagent. No Go/Python/JS code is touched, so no
  language-specialist delegation applies.

## Risk

- **Pattern-string drift between run.sh and the fixture** (duplication cost) →
  mitigation: the fixture extracts run.sh's *actual* pattern at runtime (Scenario A/B
  greps run.sh for the live assertion line) rather than hardcoding its own copy, so
  the test validates the real production pattern and cannot silently diverge.
- **Brittle extraction of the assertion line from run.sh** (grep could miss if the
  line is reformatted) → mitigation: anchor the grep on the stable substring
  `06-revise-noop.log` and `fail` with a clear message if zero or >1 matches, so a
  future reformat fails loudly instead of silently passing.
- **`grep -qE` case-sensitivity** → mitigation: pattern uses `[Nn]` classes for
  sentence-initial caps; the AC1 enumeration (Scenario B) pins lowercase `no-op` and
  capitalized variants implicitly via the three fixtures, catching a regression to a
  case-broken pattern.
- **False sense of coverage**: the meta-test proves the *predicate* is tolerant, not
  that the live model log will match — but that is exactly the spec 0014 design
  intent, and the `^revision: 1` structural check remains the real proof the branch
  ran. Accepted, documented inline.
