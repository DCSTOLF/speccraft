---
spec: "0029"
---

# Tasks

## P1 — Fix A: zsh-safe sourcing + exact-form guard + CI zsh

- [x] T1 — RED: real-zsh source pin + exact-form BASH_SOURCE grep guard in spec-consolidate.bats (AC1a/AC1b, CF-1/CF-2)
- [x] T2 — GREEN: apply canonical `${BASH_SOURCE[0]:-$0}` + cross-shell comment at consolidate.lib.sh:24 (AC1a/AC1b, CF-2/CF-5)
- [x] T3 — GREEN(infra): add `zsh` to the ci.yml hooks job apt install line (OQ-CI resolved)

## P2 — Fix B: existing-domain enumeration + seed regression pin

- [x] T4 — RED: consolidate_existing_domains cases + seed byte-pin + AC3b corpus precondition in bats (AC2/AC3/AC3b, CF-3)
- [x] T5 — GREEN: implement consolidate_existing_domains (live-only, .archive-excluded, bytewise-sorted, empty-when-absent); seed untouched (AC2/AC3, CF-3)

## P3 — Fix C: un-confusable docs + verify.sh oracle + AC6 e2e

- [x] T6 — RED: add specs/0029-.../verify.sh grep oracle (fails on main) (AC4/AC5, CF-4)
- [x] T7 — GREEN: harden close.md step 9 + memory-keeper Mode: consolidate/Mode: close wording (AC4/AC5, CF-4)
- [x] T8 — RED→GREEN(credit-gated): extend tests/e2e/spec_consolidate.sh with the AC6 existing-domain leg; deterministically verified (bash -n + AC3b pin) (AC6, CF-6)

## Verify

- [x] T9 — Final VERIFY: bats green, go test ./... untouched-green, 0025+0029 verify.sh green, real-zsh source + exact-grep guard green, bash -n all edited shell, run.sh source integrity
