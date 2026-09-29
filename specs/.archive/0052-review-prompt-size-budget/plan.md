---
spec: "0052"
status: planned
strategy: tdd
---

# Plan — 0052 Bound the spec:review reviewer payload

Stack: Bash + Go, but this spec touches **no Go**. Suite is **bats**; run with
`bats tests/hooks/`. New suite: `tests/hooks/spec-review-payload.bats`, fixtures
under `tests/hooks/fixtures/spec-review-payload/`. Models to imitate:
`tests/hooks/spec-review-diff.bats` (same lib) and `tests/hooks/history-compact.bats`.
Every test file's `setup()` does `export PATH="$PLUGIN_DIR/bin:$PATH"` so the
repo's own `./bin/` binaries run, never a stale cached plugin.

Production surfaces: `commands/spec/review.lib.sh` (the sole byte-producing owner),
`commands/spec/review.md`, `templates/prompts/review.md`,
`templates/speccraft/agents.toml`, `agents/aux-delegator.md`. Two existing
meta-guards are **extended, never duplicated** (`.speccraft/conventions.md`
§"One shared parser entrypoint"): `tests/hooks/portability-guard.bats` gains the
AC5 interval clause, and `tests/hooks/tests-portability-sweep.bats` gains the new
suite in its pinned mention-only set.

## Plan-time amendment to AC5 (scope narrowed, verified)

**AC5 as written overreaches and would fail on landing.** It forbids a regex
interval "in any `awk` or `grep` invocation" and pins that with a source scan over
whole lib files. But two correct, portable lines already ship:

- `commands/spec/review.lib.sh:24` — `grep -E '^reviewed_sha256: [0-9a-f]{64}$'`
- `commands/spec/revise.lib.sh:212` — `grep -oE '`[A-Za-z_][A-Za-z0-9_]{3,}`'`

Interval expressions are **required by POSIX ERE** and work in `grep -E` on BSD
and GNU alike (verified in this devcontainer). The hazard is **awk only**, because
mawk does not implement them and fails silently. A literal AC5 scan therefore reds
the tree on day one against two correct lines.

**Resolution:** the forbidden clause is **awk-scoped** — an interval inside an
`awk` program — and a `grep -E` interval ships as an explicit **permitted**
fixture with the reason recorded. Verified today: zero awk-interval occurrences
anywhere under the scanned roots, so the clause lands green. This narrowing makes
the criterion correct rather than weaker; it is recorded here and must be repeated
in `changelog.md` at close rather than applied silently.

## Other planning decisions taken before step 1

- **AC16 is pinned at the composer seam.** AC24 defers `review-diff --promote`, so
  there is no fresh `review-snapshot.md` at compose time and a naive AC16 assertion
  would invert. `review_compose_payload` takes `<spec-src>` as a path and never
  reads `spec.md` itself, so AC16 holds under the deferral. The driver's single-read
  is pinned separately at the `speccraft-state` stub seam (exactly one `review-diff`
  call, no `--promote`) plus the AC27 runbook-order test. Confirmed:
  `speccraft-state review-diff <dir>` without `--promote` emits the envelope
  read-only, so the deferral needs no Go change — it is a deletion at `review.md`
  step 2b plus a gate at step 6.
- **AC26's subagent half is confirm-only.** `agents/aux-delegator.md:4` already
  declares `tools: [Bash, Read]`; the test asserts it, no edit is planned.
- **The AC25 corpus is already captured.** The 12 real round-1..6 reviewer outputs
  existed only in `/tmp`; they are now committed under
  `tests/hooks/fixtures/spec-review-payload/responses/historical/`. They are
  ```yaml-fenced with free-form prose after the block — exactly the wrapping a
  too-strict validator would reject, which is why they are the right fixture.
- **The NUL boundary fails safe.** The single-scan shell buffer cannot carry NUL,
  so a NUL-bearing reference yields a digest the reviewer's read will not match;
  the verdict is not counted — the same outcome as an unread reference.

## Test-first sequence

### Step 1 — Tier table, heading grammar, interval guard (RED)

- Add `tests/hooks/spec-review-payload.bats`:
  - `review_context_tier classifies guardrails.md and index.md as inline`
  - `review_context_tier classifies architecture.md and conventions.md as reference`
  - `review_context_tier errors on history.md, on vendor/other/.speccraft/conventions.md, and on a spec-local conventions.md`
  - `review_context_tier is path-shape invariant across absolute, ./-prefixed and bare .speccraft/<name>`
  - `review_heading_index emits exactly the expected lines for each curated heading fixture`
  - `review_heading_index drops the trailing CR on a CRLF file`
  - `review_heading_index honours the fence grammar for each curated fence fixture`
  - `review_heading_index emits a NON-EMPTY index under the environment's own awk`
- Fixtures `headings/h01-none.md`, `h02-h2-only.md`, `h03-h3-only.md`,
  `h04-h4-excluded.md`, `h05-code-span.md`, `h06-non-ascii.md`, `h07-crlf.md`;
  `fences/f01-backtick.md`, `f02-tilde.md`, `f03-four-char-fence.md`,
  `f04-info-string.md`, `f05-indented-fence.md`, `f06-unclosed-fence.md`. Each
  asserted by exact expected output, never by a count of a live `.speccraft/` file.
- Extend `tests/hooks/portability-guard.bats`: forbidden fixtures `g16.sh`
  (`awk '/^#{2,3} /{print}' "$f"`) and `g17.sh` (an awk program with `{4}`), both
  added to the FLAGS loop; permitted fixtures `q15.sh` (the POSIX `grep -E`
  interval) and `q16.sh` (the bracket/anchor awk form plus `compact.lib.sh`'s
  `[0-9][0-9][0-9][0-9]`).
- Fails: `review_context_tier` / `review_heading_index` do not exist; the guard has
  no clause matching `g16`/`g17`, so the FLAGS loop reports `missed g16`.

### Step 2 — Tier table + heading extractor + guard clause (GREEN)

- `commands/spec/review.lib.sh`: `REVIEW_INLINE_SET` / `REVIEW_REFERENCE_SET` as a
  fixed table; `review_context_tier <path>` normalizing against
  `speccraft-state find-root` and matching the full repo-relative `.speccraft/<name>`,
  never the basename; `review_heading_index <file>` as one `LC_ALL=C awk` pass — a
  fence state machine (three-or-more backticks/tildes, info string allowed, closes
  only on the same character at ≥ opening length, unclosed suppresses to EOF) and
  heading matching via **bracket/anchor forms only** (`/^## /`, `/^### /`, never
  `{n,m}`), stripping a trailing CR per line.
- Extend `scan_gnu_forms()` with clause (f): an `awk` invocation whose program text
  (to the first `|` or `;`) contains `\{[0-9]+(,[0-9]*)?\}`. The clause comment
  states the awk-only scoping and why `grep -E` intervals are permitted.

### Step 3 — Round predicates, inert round, deferred promote (RED)

*Sequenced here deliberately — AC24 changes round ordering that later steps assert
against.*

- Add a `speccraft-state` stub on `PATH` appending every invocation to
  `$TEST_DIR/seam.log`, then:
  - `review_responses_complete is false when any required reviewer refused`
  - `review_responses_complete is true for two changes-requested verdicts`
  - `review_approval_quorum_met counts only approve and approve-with-comments`
  - `a complete changes-requested round writes review.md, stamps the fingerprint, and leaves status draft`
  - `an all-refused round invokes neither review-snapshot write nor review-commit at the seam`
  - `an all-refused round leaves review.md and review-snapshot.md byte-identical`
  - `an all-refused round does not invoke cross-reviewer`
  - `the round's opening review-diff call carries no --promote`
  - `a mixed round (one refusal, one verdict) is inert and names both in the report`
- Fails: the three helpers do not exist, and `commands/spec/review.md:32` still
  reads `speccraft-state review-diff "$SPEC_DIR" --promote`.

### Step 4 — Predicates + promote deferral (GREEN)

- `review_responses_complete`, `review_approval_quorum_met`, and
  `review_finalize_round` — the single place that calls `review-snapshot write`
  and `review-commit` and returns the round report naming every refusal and every
  verdict obtained.
- `commands/spec/review.md`: step 2b drops `--promote`; steps 5–7 gate on
  `responses_complete`, with the durable write moved behind that gate; status
  promotion stays gated on `approval_quorum_met` alone.

### Step 5 — Digest primitive, both polarities, one-scan proof (RED)

- `review_digest resolves shasum -a 256 when the GNU tool is absent from PATH`
- `review_digest resolves the GNU tool when shasum is absent from PATH`
- `review_digest errors with a named message when neither primitive exists`
- `review_digest matches a known vector for a committed fixture`
- `the reference record for a single-use FIFO carries a non-empty heading index AND a matching digest`
- `the naive two-pass shape disagrees with itself on the FIFO fixture` — the bite
  proof: a recorded `wc -c` + `grep -nE` reimplementation run against the same FIFO
  must produce an empty index.
- The FIFO is created at `$TEST_DIR/.speccraft/conventions.md` via `mkfifo` with a
  background writer, so it also passes `review_context_tier`. Gated at the **suite**
  level, never a runtime per-test skip.
- Update `tests/hooks/tests-portability-sweep.bats`: add `spec-review-payload.bats`
  to the pinned mention-only `expected` set.

### Step 6 — One primitive, one scan (GREEN)

- `_review_digest_cmd` resolves once, preferring `shasum -a 256`; `review_digest`
  emits bare lowercase hex.
- `_review_scan_reference <path>` reads once
  (`buf="$(cat -- "$f"; printf X)"; buf="${buf%X}"` under `LC_ALL=C`) and derives
  byte size, heading index and digest from that single buffer. Existence via
  `[ -e ]`, not `[ -f ]`, so a FIFO is accepted.
- The sweep's `expected`-set update lands in the **same commit**.

### Step 7 — The composer envelope (RED)

One compound envelope test per clause (spec-0048 style):

- `review_compose_payload rejects conventions.md passed in the inline position`
- `the composed payload orders template, then each inline file under ## File:, then the reference section`
- `the composed payload contains no reference BODY marker and no composition-time digest`
- `a reference file named but missing on disk is a named error`
- `an empty reference set emits the section with an explicit none marker`
- `--digest-out receives one "<sha256>  <path>" line per reference and the payload receives none`
- `a scoped round substitutes {{DIFF}} and {{CHANGED_SECTIONS}} and leaves no {{...}} surviving`
- `the composer reads spec content only from the <spec-src> it is given`
- `heading records are byte-identical under LC_ALL=C and under a UTF-8 locale`

Reference fixture bodies carry `SPECCRAFT-REF-BODY-MUST-NOT-APPEAR`, a marker the
heading grammar cannot emit.

### Step 8 — `review_compose_payload` (GREEN)

Implement the pinned signature, emitting composed bytes to **stdout only** and
writing exactly one other file, the `--digest-out` sidecar. Classifies every path,
errors on tier mismatch and on a named-but-missing reference, emits the "none"
marker for an empty reference set, and performs the `{{DIFF}}` /
`{{CHANGED_SECTIONS}}` substitution and prior-`review.md` attachment.
`spec-review-diff.bats` still passes (`review_build_payload` retained until step 19).

### Step 9 — Budget matrix, refusal message, overrides (RED)

- `review_budget_check exits 0 for ok and for every refusal`
- `the input-mode matrix is exhaustive: argv, acp, stdin, file, empty, absent`
- `each limit is pinned at limit-1, limit and limit+1 with the value AT the limit accepted`
- `refuse:payload-limit wins deterministically when both limits are exceeded`
- `the refusal reason enum is exactly refuse:argv-limit and refuse:payload-limit`
- `an argv-limit message carries agent, mode, bytes, effective limit, a named oversized file, the literal input = "stdin" and .speccraft/agents.toml`
- `a payload-limit message names compaction or a shorter spec and does NOT carry the migration line`
- `a both-limits message names both and states a stdin-mode agent would still be refused`
- `the message quotes the RUNTIME effective limit, not the compiled default`
- `each rejected override shape warns on stderr naming the variable and proceeds with the compiled default`
- `the budget check runs on the composed payload of BOTH --diff branches`

### Step 10 — Limits, budget check, refusal message (GREEN)

Three constants with derivation comments beside them and the **raise-me protocol**
on the payload constant; `review_effective_limit` validating and falling back
loudly; `review_budget_check` normalizing empty/absent to `stdin` and treating
`acp` as argv transport; `review_refusal_message` reading the effective limit.

### Step 11 — Materialize once, dispatch exactly, clean up always (RED)

*AC10/AC11/AC14 share one seam and are ONE compound envelope, per the spec's
planning notes; AC12 and AC13/13b ride the same driver.*

- `the round temp dir is 0700 and the payload artifact is 0600`
- `measured bytes equal wc -c of the artifact actually dispatched, for a payload ending in several newlines`
- `exactly one payload artifact is created per round at the instrumented seams`
- `the seam checker REJECTS the committed two-creation log fixture`
- `the round temp dir is removed on clean exit`
- `the round temp dir is removed on SIGINT and on SIGTERM`
- `a NUL-bearing payload is refused with a diagnostic naming NUL`
- `an invalid-UTF-8 payload is refused with a diagnostic naming UTF-8`
- `argv and acp dispatch deliver a digest equal to the artifact digest for zero, one and several trailing newlines`
- `aux-delegator review dispatch reaches the CLI boundary with the artifact bytes unmodified`
- `aux-delegator implement and analyze sections are byte-identical to the committed golden`

Fixtures: `binary/b01-nul.bin`, `binary/b02-invalid-utf8.bin`,
`forbidden/fb03-double-materialization.log`, `golden/aux-delegator-nonreview.golden`.
The CLI boundary is a stub `codex` on `PATH` digesting its stdin/argv into
`$TEST_DIR/boundary.sha`.

### Step 12 — Driver mechanics + `aux-delegator` as a pure dispatcher (GREEN)

`review_round_tmpdir` (0700, trap on `EXIT HUP INT TERM` installed immediately
after creation), `review_materialize_payload` (single 0600 artifact, stdout
redirected once — never command substitution), `review_payload_representable`
(NUL / UTF-8 gate naming which failed), `review_dispatch_bytes` (byte-preserving
file→argv read). `agents/aux-delegator.md` gains a precomposed-payload review path
and must not re-prefix, re-inline, or write a second copy; `implement` / `analyze`
untouched.

### Step 13 — Attestation validator, capability flags, shipped template (RED)

- `review_validate_reference_access accepts a well-formed response`
- `a missing expected path is rejected`
- `an unknown path is rejected`
- `a wrong digest is rejected`
- `duplicate entries for one path are rejected`
- `absent or malformed reference_access is rejected`
- `a non-empty reference_access_failures is rejected`
- `every CAPTURED historical reviewer response parses without the validator erroring on its YAML wrapping`
- `a failed attestation counts toward neither predicate and is reported in its own category`
- `review_agent_reference_read is true when the flag is absent, true, and false only for an explicit false`
- `a reference_read = false agent is refused with the named message`
- `agents/aux-delegator.md frontmatter lists Read` (confirm-only)
- `templates/prompts/review.md carries the reference_access schema, the read-with-your-own-tools instruction and the unreadable-invalidates-the-verdict line`
- `templates/speccraft/agents.toml parses PER AGENT: claude-p and opencode are stdin, no entry retains argv, every enabled entry carries reference_read = true`

### Step 14 — Validator, capability reader, template edits (GREEN)

`review_validate_reference_access` (fence-tolerant, exact set equality, exact
digest match) and `review_agent_reference_read` (opt-out: absent ⇒ true); the
prompt-template schema; the `agents.toml` input and capability changes.

### Step 15 — The ratio, on both corpora (RED)

- `the static fixture corpus composes under REVIEW_MAX_ARGV_BYTES AND at least 2x smaller than a full paste of the same inputs`
- `the live .speccraft plus the largest archived spec.md composes under REVIEW_MAX_ARGV_BYTES while the full paste exceeds it by more than 2x`
- `the largest archived spec is selected by size with a lexicographic-id tiebreaker`
- `the live-corpus test SKIPS with a stated reason when specs/.archive is absent or empty`

The RED is made honest by requiring `review_full_paste_bytes` — the counterfactual
denominator — which does not exist until step 16. Without it the ratio tests would
pass vacuously on the step-8 composer.

### Step 16 — The full-paste counterfactual + corpora (GREEN)

`review_full_paste_bytes <template> <spec-src> <files…>` — the pre-0052 shape,
retained solely as the ratio's denominator — plus the static corpus fixtures. This
repo has 45 archived specs, so the live arm runs rather than skips; the skip arm is
exercised against an empty temp tree.

### Step 17 — Runbook + prompt pins, and the bite proofs (RED)

- `commands/spec/review.md sources review.lib.sh, calls the composer, and calls review_budget_check, all BEFORE the dispatch marker`
- `the order assertion compares FOUND INDICES, not absolute line numbers`
- `commands/spec/review.md no longer instructs a full paste of a reference-tier file`
- `the no-full-paste checker REJECTS the committed forbidden runbook fixture`
- `the no-reference-body checker REJECTS the committed forbidden payload fixture`
- `the no-digest checker REJECTS the committed forbidden digest fixture`

Fixtures `forbidden/fb01-reference-body.md`, `fb02-expected-digest.md`,
`fb04-runbook-full-paste.md`. Each negative check is a **named predicate function**
run twice: against the real artifact (must pass) and against the committed
forbidden fixture (must reject) — AC29's requirement. Every negative uses
`run grep …; [ "$status" -ne 0 ]`, never a bare `! grep -q`, and every `done:`-style
predicate is one `&&` chain.

### Step 18 — Rewrite the runbook (GREEN)

`commands/spec/review.md` step 3 becomes source-lib → compose → materialize →
`review_budget_check` → dispatch, with the three named markers; the full-paste
instruction is removed; the per-agent refusal path and two-predicate gating are
written up.

### Step 19 — Refactor

Retire `review_build_payload` in favour of `review_compose_payload` and re-point
`spec-review-diff.bats`'s two payload tests at the new composer, so there is
exactly one composer. Factor the repeated bats scaffolding into `setup()` helpers.

### Step 20 — Whole-suite verification (no new code)

`bats tests/hooks/` green (all 27 files) with `./bin` first on `PATH`;
`go test ./...` green; the macOS-parity gates confirmed —
`tests-portability-sweep.bats` exact-set, `portability-guard.bats` live scan,
`no-gnu-userland.bats`.

## Delegation

- Step 1/2's interval clause → a **second-opinion read** from `codex` via
  `aux-delegator` (regex/portability is its recorded strength, and this clause
  scans the whole shipped tree — a false positive wedges every later step). Do not
  delegate the edit.
- Step 13's synthetic response fixtures → `claude-p` via `aux-delegator` (bulk
  structured-YAML variants, low coupling, each independently asserted). The
  historical corpus is copied verbatim, never generated.
- Everything else stays in-session: tightly coupled shell + meta-test work where a
  delegated edit costs more to verify than to write.

## Risk

- **AC5's literal wording vs. the live tree** → awk-scoped clause plus a permitted
  `grep -E` fixture, recorded above and repeated in `changelog.md`. Verified: zero
  awk-interval occurrences under the scanned roots, so the clause lands green.
- **The sweep's exact mention-only set goes red the moment the new suite names the
  GNU digest tool** → the `expected` update ships in the same commit as step 6.
- **Negative assertions that cannot fail before implementation** (AC6/AC11/AC27) →
  AC29's committed forbidden fixtures. The RED is "the checker rejects the forbidden
  fixture", which genuinely fails while no checker exists. Spec 0049 shipped three
  inert negatives on author discipline; this plan never relies on it.
- **A NUL-bearing reference file mis-sizes the single-scan buffer** → fails safe;
  the digest will not match, the verdict is not counted. Stated in the lib comment.
- **`review_finalize_round` becomes a second orchestration authority beside the
  runbook prose** → AC27's order meta-test reads the live `review.md`, so a
  divergence fails a test.
- **The composer's stdout contract under `set -euo pipefail`** → every helper is
  invoked through `run`, and the driver redirects rather than captures — the exact
  strip AC10 exists to catch.
- **`trap` cannot catch SIGKILL** → accepted and stated: the contract is
  `EXIT HUP INT TERM`; a `kill -9` leaves the temp dir, documented in the lib
  comment rather than claimed away.

## RED registration — author-enforced, not guard-enforced

`speccraft-guard`'s TDD gate classifies production code for Go/Python/Rust/JS-TS
only; **shell is explicitly out** (`.speccraft/conventions.md:533`, added by spec
0021 after that exact wrong assumption), and `IsAlwaysAllowed` short-circuits every
`.md` path (`tools/internal/speccraft/files.go:141`). The guard will therefore
never demand a RED anywhere in this spec. Every GREEN step must be preceded by an
observed `bats tests/hooks/spec-review-payload.bats` failure, pasted into the task
note.

"Function does not exist" is a weak RED: each helper's first test uses
`run <helper> …; [ "$status" -ne 0 ]` **plus** an output assertion, so it fails for
its own reason rather than on a bare `command not found` that a typo would also
satisfy.

Verify the AC5 behavioural arm bites by hand once before implementing —
`printf '## a\n### b\n' | awk '/^#{2,3} /{print}'` yields zero output and exit 0
here (mawk). That arm is the only thing distinguishing a working extractor from a
silently-empty one.

## Override budget

**Estimate: 0.** This spec touches only `*.sh` and `*.md`, and neither is
guard-gated. There is no compile step, so no new-symbol build failure, and
build-repair mode is irrelevant.

If spent at all, the likely place is step 2 or 12, one override, if a stale cached
`speccraft-guard` on `PATH` misclassifies `review.lib.sh` — mitigate first by
rebuilding `./bin/` and confirming `hooks/pre-tool-use.sh` resolves the local guard.

## ACs not fully testable at the bats layer

1. **AC14's bytes at the CLI boundary** — bats asserts against a stub `codex`.
   Real-CLI parity needs live credentialed runs; already booked as an out-of-scope
   known gap. Belongs in `tests/e2e/` if ever wanted.
2. **AC26's cwd contract for the subagent half** — bats can pin the instruction and
   the cwd argument, not that Claude Code launches it there. Credit-gated e2e; the
   spec frames it as pinning existing behaviour, not changing it.
3. **AC25's stronger reading** — that the model *incorporated* the bytes. The spec
   explicitly disclaims this; nothing to test.
4. **AC12 under SIGKILL** — `trap` cannot catch it; the boundary is stated.
