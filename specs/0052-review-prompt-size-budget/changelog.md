---
spec: "0052"
closed: 2026-09-28
---

# Changelog — 0052 Bound the spec:review reviewer payload

## What shipped vs spec

All 29 acceptance criteria (AC1–AC29, plus the interpolated AC13b) implemented
across T0–T20, in 13 commits from `57cd5aa` to `7720008`. The design shipped as
reviewed — the tier split, the pre-dispatch byte budget, the two-predicate
separation, the digest attestation, and the explicit rejections (auto-fallback,
section-excerpting, `ARG_MAX` probing) all landed unchanged.

- **Tiered context assembly (AC1–AC4, AC6–AC7).** `review_context_tier` resolves
  against `speccraft-state find-root` and matches the full repo-relative
  `.speccraft/<name>`, never the basename; `.speccraft/history.md` is an error.
  `review_heading_index` / `_review_heading_stream` emit `^## ` and `^### ` in
  file order under a full fence grammar (≥3 backticks or tildes, closed only by
  the same character at ≥ length, unclosed fence suppresses to EOF). An empty
  reference set emits an explicit "none" marker; a named-but-missing reference
  file is an error.
- **One composer (AC2, AC15, AC16).** `review_compose_payload` serves the full
  round **and** the spec-0035 scoped `--diff` round, emitting to **stdout**, with
  the composition-time digests going to the separate `--digest-out` channel so
  they never enter the payload. `review_build_payload` retired (T19),
  `spec-review-diff.bats` re-pointed.
- **Byte budget (AC19–AC21).** `REVIEW_MAX_ARGV_BYTES_DEFAULT=65536`,
  `REVIEW_MAX_PAYLOAD_BYTES_DEFAULT=262144`, `REVIEW_MIN_LIMIT_BYTES=1024`, each
  with its derivation and the raise-me protocol in a comment beside it.
  `review_budget_check` echoes `ok` / `refuse:<reason>` and exits 0 in both cases;
  `acp` is argv transport; empty/absent normalizes to stdin; an unrecognised mode
  is an error, so the next argv transport cannot slip in exempt.
  `review_refusal_message` derives the printed limit from `review_effective_limit`,
  not the compiled default.
- **Materialize once, dispatch exactly (AC10–AC14, AC13b).** `review_round_tmpdir`
  (0700, trap on `EXIT HUP INT TERM`), `review_materialize_payload` (0600, refuses
  a second materialization, redirects rather than captures),
  `review_payload_representable` (NUL vs invalid-UTF-8 named separately),
  `review_dispatch_bytes` (`IFS= read -r -d ''`), `review_dispatch_payload`
  (`file` mode passes the round's own artifact — the most natural place for a
  second copy to appear).
- **Attestation + capability (AC25, AC26, AC28).**
  `review_validate_reference_access` is exercised against the 12 captured
  historical reviewer responses from this spec's own six rounds; `reference_read`
  is opt-out in the registry; `templates/speccraft/agents.toml` ships
  `input = "stdin"` for all three CLIs with an explicit `reference_read = true`.
- **Runbook (AC27).** `commands/spec/review.md` step 3 rewritten as
  compose → budget-check → dispatch in one shell, with steps 5–7 gated on the two
  predicates; `agents/aux-delegator.md` gains the precomposed-payload path.

### Deviations

- **AC5 was amended at plan time, recorded rather than applied silently.** As
  written, AC5 forbade a regex interval in "any `awk` or `grep` invocation". That
  clause would have red-ed the tree on day one against two **correct** lines —
  `commands/spec/review.lib.sh`'s `reviewed_sha256` grammar and
  `commands/spec/revise.lib.sh`'s identifier token. Interval expressions are
  REQUIRED by POSIX ERE and work in `grep -E` on BSD and GNU alike; the hazard is
  `awk` ONLY, because mawk does not implement them and fails **silently**. Shipped
  clause (f) of `tests/hooks/portability-guard.bats` is therefore awk-scoped, and
  fixture `permitted/q15.sh` pins the `grep -E` permission so the scoping cannot
  later be "tightened" into a false positive against working code.
- **One contract deviation.** §Contracts pins `review_compose_payload --inline
  <f…>`. As implemented, the inline set accepts a path **outside** the tier table
  — that is how the prior `review.md` rides along as scoped-round evidence. Only a
  **reference-tier** file in the inline position is an error, which is AC2's actual
  wording. A typo cannot hide in the allowance, because a mistyped path will not
  exist on disk.
- **AC24 had a consequence neither the spec nor the plan named.** Dropping
  `--promote` from step 2b leaves `review-snapshot.md` at the last-REVIEWED
  version at compose time, so reviewers on a `--diff` round would have been shown
  the **OLD** spec. The round now freezes `spec.md` **once** into the round temp
  dir (`$REVIEW_ROUND_TMPDIR/spec-frozen.md`) and the promote happens at finalize
  inside `review_finalize_round`. AC16's single-read transaction still holds
  because the composer reads only the `<spec-src>` path it is handed — the
  guarantee was never tied to the file's name.
- **A real defect found while implementing, with its own test.** `trap … EXIT` in
  `review_round_tmpdir` silently **DESTROYED the caller's EXIT handler**. Under
  bats that makes a FAILING test report nothing at all — one test vanished from
  the run rather than failing — so every assertion in any test touching the helper
  would have been inert. Fixed by saving the prior handler with `trap -p EXIT`
  into `_REVIEW_PRIOR_EXIT` and re-firing it via `_review_fire_prior_exit`
  (quoting-safe unwrap of `trap -p`'s re-evalable word, fire-once so it cannot
  recurse). This is spec 0049's inert-`! grep -q` class arriving through the
  shell's trap table instead of through `set -e`.
- **Two runbook gaps, each given its own RED.** (1) `$OUTCOMES` was appended to but
  never assigned — the round would have written outcome records to an unbound path.
  (2) `review_agent_field … cmd` returns **raw TOML**, so dispatch would have tried
  to exec `["codex",`. Added `review_agent_cmd`.
- **Two test-authoring defects.** (1) `RESP="$FIX/…"` at bats **file scope**
  expanded before `setup()` ran, leaving 11 tests asserting against the literal
  `/responses`. (2) Comparing a verdict against the whole of `$output` broke as
  soon as a rejection carried its diagnostic on **stderr**, which bats merges into
  `$output`.
- **Bite proofs moved earlier than planned.** `fb01` (reference-body-absent) and
  `fb02` (expected-digest-absent) landed in **T7**, not T17; `fb03` in T11 and
  `fb05` in T3 for the same reason. An inert negative sitting in the tree for ten
  tasks is the exact thing this repo has shipped three times before (spec 0049).
  Only `fb04` (runbook no-full-paste) remained in T17.

## The measured result

Against this repository's live `.speccraft/` plus the largest archived `spec.md`,
selected dynamically at test time:

| composition | bytes | vs the 65,536 argv limit |
|---|---|---|
| tiered (shipped) | **51,535** | fits |
| full paste (today's behavior) | **207,675** | **3.2× OVER** |

Compression ratio **4.03×**. AC18's static counterpart asserts the same ratio
bidirectionally over bundled fixtures and never skips, so the mechanism is proved
everywhere — including where `specs/.archive/` is absent.

## Files touched

Production:

| file | +/- | what |
|---|---|---|
| `commands/spec/review.lib.sh` | +1158 / −29 | the byte boundary; 35 helpers |
| `commands/spec/review.md` | +145 / −46 | step 2b read-only, step 3 rewritten, steps 5–7 gated |
| `agents/aux-delegator.md` | +31 / −5 | review mode becomes a pure dispatcher |
| `templates/prompts/review.md` | +24 / −2 | two-tier explanation + `reference_access` schema |
| `templates/speccraft/agents.toml` | +21 / −3 | `input = "stdin"` ×3, `reference_read = true` ×4 |

Tests:

| file | +/- | what |
|---|---|---|
| `tests/hooks/spec-review-payload.bats` | +1643 | new suite, 117 tests |
| `tests/hooks/portability-guard.bats` | +57 / −1 | clause (f); forbidden g16/g17/g18, permitted q15/q16/q17 |
| `tests/hooks/tests-portability-sweep.bats` | +34 / −2 | `fixtures/` scope boundary + exact-set update |
| `tests/hooks/spec-review-diff.bats` | +28 / −4 | re-pointed off the retired `review_build_payload` |

51 fixtures under `tests/hooks/fixtures/spec-review-payload/`: headings, fences,
binary, static corpus, digest vector, 6 forbidden bite proofs, 1 golden, 9
`reference_access` arms, and the 12 captured historical reviewer responses.

Release (1.17.0 → 1.18.0, bumped in-spec before close, separate commit `7720008`):
`.claude-plugin/{plugin,marketplace}.json`,
`tools/cmd/speccraft-{state,guard,drift}/main.go` + their `version_test.go`,
`tools/internal/speccraft/manifest_version_test.go`.

## Verification

- bats **468 ok / 28 files**
- `go test ./...` green, `go vet` green, `speccraft-drift scan-all` clean
- the four macOS-parity gates green (portability-guard live scan + both fixture
  polarities, tests-portability-sweep exact set, no-gnu-userland, lib-zsh-safety)
- **Override budget: 0 stated, 0 actual.** The spec touches only `*.sh` and `*.md`,
  neither guard-gated; the plan's one anticipated override (a stale cached guard on
  `PATH`) never materialised.
- Shipped in **1.18.0**, bumped inside the spec before close in a separate commit,
  per the `bump-before-close` / close-commit-invariant split established by 0051.

## Review

Six rounds, two reviewers each, every output hash-verified distinct. codex
`changes-requested` ×5; claude-p `approve-with-comments` ×5; round 6 a
confirmation round. The spec grew from 12 criteria to 29. See `review.md` for the
round-by-round findings; the round-1 **false quorum** incident became a convention
at close.

## Known gaps, carried not hidden

- **No live-credentialed proof that each aux CLI parses a stdin prompt identically
  to argv.** The template flip is a behavioral change, not a label change.
  Mitigation: this repository has run `claude -p` on **stdin** for its own reviews
  since before this spec, including all six rounds of this spec's own review at
  185–209 KB.
- **AC26's cwd LAUNCH needs a credentialed e2e.** bats pins the instruction and the
  `cwd` argument (`b4c6119`); it cannot assert that Claude Code launches the
  subagent there. The spec frames AC26 as pinning existing behavior
  (`.speccraft/architecture.md:211`), not changing it.
- **AC25's stronger reading is explicitly disclaimed.** A matching digest proves a
  process with filesystem access obtained the bytes. It does **not** prove the
  model incorporated them into its reasoning. A digest proves access, not attention.
- **AC12 under `SIGKILL`** — `trap` cannot catch it; stated boundary, not claimed away.

## Follow-ups filed

1. `/speccraft:sync` should surface a still-`argv` `.speccraft/agents.toml` in its
   drift report. Existing repos own their copy and are not rewritten, so the argv
   budget refusal is the only nudge today — a drift line is the durable one.
2. `commands/spec/review-code.md` should migrate to these helpers. It is the only
   other command sharing the full-paste pattern.
3. **Spec B — memory size limits, `/speccraft:memory:compact`, and close-time
   content routing.** The other half of `feedback-on-review-command.md`. This spec
   makes review survive large memory files; it does not make the files small — and
   `history.md` is now the largest single `.speccraft/` file at 120,899 B, which is
   a direct argument for it.
