# Domain: spec-lifecycle

Spec lifecycle commands and their gating: `spec:revise` status gates, artifact archival, `revision:` counter, spec-reviser subagent, code cross-check.

- `/speccraft:spec:revise` operates on the active spec only, gated to source status `draft|reviewed|planned` (rejecting `in-progress`/`closed`/`archived` with a status-naming error) and errors when `active_spec` is empty (spec 0015)
- On a real spec.md edit, revise increments the `revision: N` frontmatter counter (inserting `revision: 0` if absent — command-owned, never agent-owned), archives stale downstream artifacts by renaming `review.md`/`plan.md`/`tasks.md` to `*-r<N_old>.md` per source status, and resets status to `draft`; a whitespace/newline-only edit is a no-op that changes nothing and prints `no changes — spec unchanged` (spec 0015)
- Revise's optional code cross-check greps identifier tokens found in backtick spans (regex `[A-Za-z_][A-Za-z0-9_]{3,}`) within `## What`/`## Acceptance criteria`/`## Out of scope` across `packages[]` using portable `find`/`grep` (never ripgrep); zero-match tokens become `^Q-DRIFT:`-prefixed re-interview questions, and an empty `packages[]` prints `packages[] empty — skipping code cross-check` and proceeds (spec 0015)
- The `spec-reviser` subagent (`tools: [Read, Write, Edit, Bash]`, no `Agent` tool) re-runs the Socratic interview against existing spec.md content and must not modify the command-owned frontmatter keys `revision:`/`status:`/`id:`/`created:` (spec 0015)
- Revise preflights before any mutation: it aborts (modifying nothing, not invoking the reviser) when a target `*-r<N_old>.md` archive path already exists or a required source artifact for the source status is missing (spec 0015)
