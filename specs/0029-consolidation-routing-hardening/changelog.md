---
spec: "0029"
closed: 2026-06-27
---

# Changelog — 0029 Consolidation routing hardening + zsh portability fix

## What shipped vs spec

All ACs implemented across the deterministic tier (bats) and the doc/model tier
(verify.sh + e2e). Three first-use defects in spec 0025's consolidation, fixed
inside its existing surfaces — no new command, Go binary, or store.

- **Fix A — zsh-safe lib sourcing + exact-form guard (AC1).**
  `commands/spec/consolidate.lib.sh` now resolves its own dir via the canonical
  `${BASH_SOURCE[0]:-$0}` (the bare `${BASH_SOURCE[0]}` aborted the whole helper
  under zsh + `set -u`, breaking consolidation AND `/speccraft:sync` backfill). The
  RED was genuine: `zsh -uc 'source …'` exited 127 on the pre-fix code. Pinned by
  `Test_consolidate_lib_sources_under_real_zsh` (REAL zsh — a bash simulated-unset
  harness can't reproduce the bug; fail-loud if zsh absent, never silent-skip),
  `…_under_bash_unchanged`, and `Test_no_lib_uses_bare_BASH_SOURCE_idiom` (exact-form
  grep across all 8 `commands/**/*.lib.sh`). `.github/workflows/ci.yml` hooks job
  now installs `zsh` (OQ-CI resolved).
- **Fix B — existing-domain-aware routing (AC2/AC3/AC3b).** New deterministic
  `consolidate_existing_domains` (live-only, `.archive`-excluded, bytewise-sorted,
  empty-when-absent) grounds the routing proposal so `memory-keeper` can prefer a
  good existing-domain match or deliberately propose a clearly-named NEW domain.
  `consolidate_routing_seed` is left BYTE-UNCHANGED (regression-pinned) — the
  existing-domain awareness is a separate input; the prefer-existing-else-new
  judgment stays model-tier and confirm-gated.
- **Fix C — un-confusable docs (AC4/AC5).** `commands/spec/close.md` step 9 and
  `agents/memory-keeper.md` (`Mode: consolidate` + `Mode: close`) now state that
  consolidation routes ONLY to `specs/domains/` and NEVER to
  `.speccraft/architecture.md`/`conventions.md`/`history.md`; that a missing
  `delta:`/`domains:` is a fallback, never a skip; and that `Mode: close` memory
  updates are NOT a substitute for consolidation — with a named residual-risk note
  (mitigation, not enforcement). Pinned by `specs/0029-.../verify.sh` (10 checks).
  `close.md` step (a) now wires `consolidate_existing_domains`.
- **AC6 e2e leg.** `tests/e2e/spec_consolidate.sh` gains the existing-domain leg
  (no-match title → new domain; matching title → existing domain;
  `.speccraft/*.md` byte-unchanged), honoring the spec-0028 leg-isolation
  discipline.
- **Release 1.6.0 → 1.6.1.** Coordinated bump across `plugin.json`,
  `marketplace.json`, and the three binary `const version` (each RED→GREEN via its
  sibling version test). Patch-releases the 0029 fix so the host project that hit
  the bug gets it.

## Test coverage

`bats tests/hooks` 138/0; `go test ./...` green; `verify.sh` 0025 + 0029 green;
real `zsh -uc 'source consolidate.lib.sh'` exits 0; exact-form `BASH_SOURCE` guard
green; manifest grep oracle clean (1.6.1, no stray 1.6.0).

## Deviations

- **No `/speccraft:spec:override`** — every change is `.sh`/`.md`/`.bats`/`.yml`/
  e2e, ungated by `speccraft-guard`. The version-const edits used the normal
  RED→GREEN version-test path under the active spec.
- **AC6 e2e leg was credit-gated and initially failed in CI** — the first prompts
  said "propose and, on confirm, CREATE … Confirm.", which under non-interactive
  `claude -p` made the model propose and WAIT (no file created). Fixed by rewording
  to the proven imperative CONFIRM-leg style ("Approve and APPLY … now; do not wait
  for a separate confirmation; move the closed dir to `specs/.archive/`"). Commit
  `ddf38da`. The full `claude -p` lifecycle is the CI E2E (devcontainer) job;
  deterministic verification (bash -n, run.sh integrity, the AC3b corpus pin)
  passed at implement time.
- **Consolidation was NOT run on 0029's own close** — 0029 carries no
  `domains:`/`delta:` block and this repo has no `specs/domains/` tree yet; per the
  inline-at-close contract that is a non-blocking decline (the spec still closes
  and nothing is moved). 0029 remains a closed dir under `specs/`, eligible for a
  future `/speccraft:sync` backfill if a domain layer is ever started here.

## Provenance

Landed across commits `0d595d7` (feature + 1.6.1) and `ddf38da` (AC6 e2e
imperative-prompt fix); released as tag `v1.6.1`.
