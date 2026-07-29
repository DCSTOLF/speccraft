---
spec: "0034"
---

# Tasks

- [x] T1 — DetectStack stub bootstrap (Stack type + DetectStack→unknown)
- [x] T2 — Detection table + polyglot + unknown tests (RED) — AC1, AC2
- [x] T3 — Implement DetectStack (GREEN) — AC1, AC2
- [x] T4 — detect-stack subcommand run()-seam tests (RED) — AC3
- [x] T5 — Wire detect-stack, versioned JSON envelope (GREEN) — AC3
- [x] T6 — test-command precedence + marker grammar tests (RED) — AC4
- [x] T7 — Wire test-command + EffectiveTestCommand marker parser (GREEN) — AC4
- [x] T8 — init seed_conventions bats: fresh/preserve/unknown (RED) — AC5
- [x] T9 — Implement init.lib.sh seeding + wire init.md (GREEN) — AC5
- [x] T10 — Authoring-prose recurrence guard (RED) — AC6
- [x] T11 — Rewrite tdd-planner/plan/implement/delegate stack-neutral (GREEN) — AC6
- [x] T12 — Shipped-template purity guard (RED) — AC7
- [x] T13 — Strip Go idioms from templates/speccraft/conventions.md (GREEN) — AC7
- [x] T14 — Version assertions → 1.8.0 across state/guard/drift + manifest oracle (RED) — AC8
- [x] T15 — Bump const version + plugin.json/marketplace.json to 1.8.0; final VERIFY (GREEN) — AC8

## Bypasses

- 2026-07-25 — override: bootstrap the brand-new `DetectStack`/`Stack` symbol
  (T1). The Step-2 sibling test (`detect_test.go`) references `DetectStack`, so the
  guard's pre-edit red-check compiles the package WITHOUT `detect.go` →
  `OutcomeBuildFailed`, which is not a valid RED (guardrails §TDD-invariant AC13
  new-symbol limitation). Scope: this ONE `detect.go` stub-creation edit only.
  Immediately after, the stub compiles and the table tests fail BEHAVIORALLY
  (genuine observed RED); every subsequent edit (T3 impl onward) is strict
  RED→GREEN with no override. Mirrors spec 0031's single-symbol-bootstrap pattern.
