---
spec: "0029"
status: planned
strategy: tdd
---

# Plan — 0029 Consolidation routing hardening + zsh portability fix

Three independently-landable fixes inside the spec-0025 surfaces. No new command,
Go binary, or store. ALL edits are `.sh`/`.md`/`.bats`/`.yml`/e2e — ungated, so
**NO `/speccraft:spec:override` is needed**. The e2e leg (P3 / AC6) is
credit-gated; it is verified deterministically at implement time (`bash -n` + the
`consolidate_existing_domains` corpus pin at the bats layer) — the full `claude -p`
lifecycle run is the user's pending e2e step.

**Spec-immutability carve-out.** This spec edits spec 0025's IMPLEMENTATION files
(`commands/spec/consolidate.lib.sh`, `commands/spec/close.md`,
`agents/memory-keeper.md`, `tests/e2e/spec_consolidate.sh`) plus `.github/workflows/ci.yml`
— it does NOT touch 0025's `spec.md`/`plan.md`.

**RED precondition confirmed at plan time.** `zsh -uc 'source
commands/spec/consolidate.lib.sh'` on `main` aborts at line 24 with
`BASH_SOURCE[0]: parameter not set` (then exits 127 failing the sibling source).
zsh 5.8.1 is present in the devcontainer. The repo has exactly 8 `*.lib.sh` under
`commands/`; only `consolidate.lib.sh` references `BASH_SOURCE`.

## Test-first sequence

### P1 — Fix A: zsh-safe lib sourcing + exact-form regression guard + CI zsh

#### Step 1 — Real-zsh source pin + exact-form grep guard (RED) — AC1(a), AC1(b), CF-1, CF-2
- Extend `tests/hooks/spec-consolidate.bats` with:
  - `Test_consolidate_lib_sources_under_real_zsh` — asserts zsh is available
    (`command -v zsh` else `fail "zsh required for AC1(a) — never silent-skip"`;
    fail-loud, NOT `skip`), then runs
    `zsh -uc "source '$LIB'; typeset -f consolidate_routing_seed >/dev/null"`
    from an unrelated CWD and asserts `status -eq 0` (the lib loads AND its
    transitive `source` of `commands/history/compact.lib.sh` resolves). Uses REAL
    zsh — a bash simulated-unset harness is forbidden (bash re-populates
    `BASH_SOURCE` during `source`, yielding a false pass).
  - `Test_consolidate_lib_sources_under_bash_unchanged` — `bash -uc "source
    '$LIB'; typeset -f consolidate_routing_seed >/dev/null"` exits 0 (bash path
    unchanged).
  - `Test_no_lib_uses_bare_BASH_SOURCE_idiom` — exact-form guard across ALL
    `commands/**/*.lib.sh`: fails if any file contains a `${BASH_SOURCE[0]}`
    occurrence that is not exactly `${BASH_SOURCE[0]:-$0}`. Implemented by
    stripping every literal `${BASH_SOURCE[0]:-$0}` from each lib, then asserting
    no residual `BASH_SOURCE[0]` token remains. Credit-free; runs everywhere
    regardless of zsh presence.
- Tests fail: on `main`, `Test_consolidate_lib_sources_under_real_zsh` fails
  because `zsh -uc` aborts at line 24 (`BASH_SOURCE[0]: parameter not set`, exit
  127); `Test_no_lib_uses_bare_BASH_SOURCE_idiom` fails because line 24 holds the
  bare `${BASH_SOURCE[0]}`. (`..._under_bash_unchanged` already passes — it pins
  the no-regression side.)

#### Step 2 — Apply the canonical cross-shell idiom (GREEN) — AC1(a), AC1(b), CF-2, CF-5
- Edit `commands/spec/consolidate.lib.sh:24`: replace
  `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` so the `dirname` argument is
  exactly `${BASH_SOURCE[0]:-$0}`, and add an in-code comment (CF-5) explaining
  cross-shell correctness: bash always populates `BASH_SOURCE`, so the `:-$0`
  fallback never fires there; zsh sets `$0` to the sourced file path, so `$0` is
  exactly the right value where the fallback fires. Do NOT "simplify" back to the
  bare form.
- All Step-1 tests pass: real-zsh source exits 0, the exact-form guard finds only
  the canonical idiom, bash is unchanged.

#### Step 3 — Provision zsh in the CI bats job (GREEN, infra) — OQ-CI (resolved)
- Edit `.github/workflows/ci.yml` `hooks` job ("Hook tests (bats)",
  `runs-on: ubuntu-latest`): add `zsh` to the "Install bats" apt line so it reads
  `sudo apt-get install -y bats zsh`. The devcontainer already ships zsh 5.8.1
  (the e2e job is fine); only the bare-ubuntu bats runner lacks it. With zsh
  present, `Test_consolidate_lib_sources_under_real_zsh` runs faithfully in CI and
  fails loud (never silent-skip) if zsh is ever absent.

### P2 — Fix B: existing-domain enumeration (deterministic) + seed regression pin

#### Step 4 — Enumerate live domains + seed byte-pin + AC3b corpus precondition (RED) — AC2, AC3, AC3b, CF-3
- Extend `tests/hooks/spec-consolidate.bats` with:
  - `Test_consolidate_existing_domains_lists_live_areas_bytewise_sorted` — seed
    `specs/domains/{billing,auth}.md` and `specs/domains/.archive/auth.md`; assert
    `consolidate_existing_domains "$TEST_REPO"` emits exactly `auth` then `billing`
    (live `<area>` names only, `.archive` excluded, bytewise-sorted, one per line).
  - `Test_consolidate_existing_domains_empty_when_dir_absent` — fresh repo with no
    `specs/domains/`; assert empty output and `status -eq 0`.
  - `Test_consolidate_routing_seed_byte_unchanged_from_0025` — AC3 regression pin:
    explicit `domains:` yields exactly its listed areas, and an absent-`domains:`
    title-slug is byte-identical and stable across two runs (pins 0025 AC2; proves
    Fix B did NOT touch the seed — existing-domain awareness is a SEPARATE helper).
  - `Test_consolidate_existing_domains_AC6_corpus_precondition` — AC3b: seed the
    exact one-existing-domain corpus the AC6 e2e fixture builds and assert
    `consolidate_existing_domains` returns that expected singleton set, so a
    fixture-seeding regression fails credit-free on every bats job (the
    0025→0027→0028 fixture-flakiness-lineage convention).
- Tests fail: `consolidate_existing_domains` does not yet exist (the seed-pin and
  AC3b cases reference an undefined function); the seed-pin's domains/title cases
  pass already (they pin existing behavior) and stay green throughout.

#### Step 5 — Add `consolidate_existing_domains` (GREEN) — AC2, CF-3
- Implement `consolidate_existing_domains <repo-root>` in
  `commands/spec/consolidate.lib.sh` (pure, no source-time side effects): glob
  `<repo>/specs/domains/*.md`, take each basename minus `.md` as `<area>`, exclude
  the `.archive/` subtree, emit one area per line `sort`ed bytewise (`LC_ALL=C
  sort`), and emit nothing when `specs/domains/` is absent. `consolidate_routing_seed`
  is NOT modified (AC3). The new helper is the SEPARATE deterministic input that
  `memory-keeper Mode: consolidate` consumes alongside the seed; the
  "prefer-existing-else-propose-new" judgment stays model-tier and confirm-gated.
- All Step-4 tests pass.

### P3 — Fix C: un-confusable docs + verify.sh grep oracle + AC6 e2e

#### Step 6 — `specs/0029-.../verify.sh` grep oracle (RED on main) — AC4, AC5, CF-4
- Add `specs/0029-consolidation-routing-hardening/verify.sh`, mirroring the
  0025 grep-oracle structure (`set -euo pipefail`, `HERE`/`REPO_ROOT` resolution,
  `present`/`absent` helpers, non-zero exit naming the failing check). Pin:
  - `close.md` step 9 and `memory-keeper Mode: consolidate` each state consolidation
    routes ONLY to `specs/domains/` and NEVER writes
    `.speccraft/architecture.md`/`conventions.md`/`history.md` (AC4 never-`.speccraft`).
  - `memory-keeper Mode: close` carries a one-line "does not perform consolidation;
    see Mode: consolidate" disambiguator, and the docs state `Mode: close` updates
    are NOT a substitute for `Mode: consolidate` (AC4 no-substitute).
  - `close.md` step 9 + `Mode: consolidate` state a missing `delta:`/`domains:` is a
    confirm-gated model-proposed routing + ADD/MODIFY/REMOVE classification into the
    domain file — fallback, never a skip, never a `.speccraft/` write (AC5).
  - A residual-risk note (CF-4) that Fix C is mitigation, not enforcement.
- Tests fail: run `bash specs/0029-.../verify.sh` on `main` — the disambiguating
  wording is absent from `close.md` and `memory-keeper.md`, so it exits non-zero.

#### Step 7 — Harden the docs to satisfy the oracle (GREEN) — AC4, AC5, CF-4
- Edit `commands/spec/close.md` step 9: add the never-`.speccraft` blast-radius
  restatement, the fallback-not-skip wording for the no-`delta:`/no-`domains:` path,
  and the no-substitute statement vs the step-4 `Mode: close` memory updates.
- Edit `agents/memory-keeper.md`:
  - `Mode: consolidate` — never-`.speccraft` routing statement, fallback-not-skip
    wording, the no-substitute disambiguator, and the CF-4 residual-risk note.
  - `Mode: close` — a one-line "does not perform consolidation; see Mode:
    consolidate" disambiguator.
- `specs/0029-.../verify.sh` passes; 0025's `verify.sh` stays green.

#### Step 8 — AC6 existing-domain-aware e2e leg (RED→GREEN, credit-gated) — AC6, CF-6
- Extend the EXISTING `tests/e2e/spec_consolidate.sh` (do NOT create a new file)
  with an AC6 leg, structural predicates only, credit-gated:
  - Seed ONE existing domain (`specs/domains/<existing>.md`); snapshot
    `.speccraft/architecture.md`/`conventions.md`/`history.md`.
  - Close (i): a spec whose title does NOT match the existing domain → proposes and
    (on confirm) CREATES a new `specs/domains/<new>.md`; assert it exists and gained
    lines.
  - Close (ii): a spec whose title DOES fit → routes into
    `specs/domains/<existing>.md`; assert it gained lines.
  - After both closes, assert the three `.speccraft/*.md` are byte-unchanged
    (`cmp -s` against snapshots).
  - Add an `_assert_candidate_singleton`-style direct
    `consolidate_existing_domains` invocation so the leg's existing-domain
    precondition is also pinned in-run (mirrors the AC3b bats pin).
- RED→GREEN deterministically verified at implement time: `bash -n
  tests/e2e/spec_consolidate.sh` parses, `run.sh` source integrity holds, and the
  AC3b corpus pin (Step 4) covers the same corpus credit-free. The full `claude -p`
  run is the user's pending e2e leg.

### Step 9 — Final VERIFY (all green together)
- `bats tests/hooks/` green (new zsh source pin, exact-form guard,
  `consolidate_existing_domains` + AC3b corpus, seed byte-pin).
- `go test ./...` in `tools/` untouched-green (no Go changed).
- `bash specs/0025-.../verify.sh` AND `bash specs/0029-.../verify.sh` both green.
- `zsh -uc 'source commands/spec/consolidate.lib.sh'` exits 0 under real zsh.
- The exact-form `BASH_SOURCE` grep guard green.
- `bash -n` on every edited shell file (`consolidate.lib.sh`,
  `tests/e2e/spec_consolidate.sh`, `specs/0029-.../verify.sh`); `tests/e2e/run.sh`
  source integrity intact.

## Delegation

- Steps 1–5 (shell helper + bats, deterministic tier) → keep in the implementing
  thread; pure-shell + bats, no model judgment, tightest RED→GREEN loop.
- Step 6–7 (doc grep oracle + Fix C prose) → keep in-thread; the wording is
  load-bearing against the oracle and must be authored against the exact `present`
  regexes.
- Step 8 (AC6 e2e fixture) → keep in-thread; it depends on Step 5's helper and the
  Step 4 corpus and is verified deterministically (bash -n + AC3b pin) at implement
  time.

## Risk

- A bash simulated-unset harness silently passing against broken code → mitigation:
  AC1(a) mandates REAL `zsh -uc`; the bats test asserts zsh present and fails loud
  (never `skip`); Step 3 installs zsh in the CI bats job (OQ-CI resolved).
- The exact-form grep guard false-positiving on a valid alternative, or being
  loosened until it stops catching the bug → mitigation: single canonical idiom
  `${BASH_SOURCE[0]:-$0}` (CF-2), guard strips that exact literal then flags ANY
  residual `BASH_SOURCE[0]`.
- Fix B re-reading as a change to the routing seed (AC3 vs Fix B apparent conflict)
  → mitigation: seed is byte-pinned (Step 4) and untouched (Step 5);
  existing-domain awareness is a SEPARATE helper feeding the confirm-gated model tier.
- AC6 e2e flakiness from fixture-seeding drift → mitigation: the AC3b bats corpus
  pin (Step 4) reconstructs the AC6 corpus credit-free, per the 0025→0027→0028
  lineage; the e2e leg also asserts the precondition in-run.
- Fix C is mitigation, not enforcement — no deterministic guard can stop an agent
  writing requirements into `.speccraft/` during consolidation (a hook cannot tell a
  wrong consolidation write from a legitimate `Mode: close` write) → mitigation:
  named as residual risk (CF-4) in verify.sh + the docs; stronger enforcement is
  deliberately out of scope.
